from csv import reader, writer
from typing import Tuple
from datetime import datetime
import os
import sys
import patient_visit
import common
import numpy as np
import cv2
import time

# Optional suffix for output image name, use for debugging.
OUT_IMG_SUFFIX = ''

def parse_csv_to_images(csv_file: str):
    """
    Top-level function that loads the provided 
    csv and saves images to disk as png.
    """
    patient_visits = dict()
    unknown_items = list()

    item2feature, stats = generate_stats()

    print(f"Parsing {csv_file}")
    parse_start_time = time.time()
    with open(csv_file, 'r') as f:
        i = 0
        i_batch = 0
        visit_id_prev = 0
        for row in reader(f):
            if i == 0:
                # Skip header row, we'll parse the columns ourselves
                i = i + 1
                continue

            if int(row[common.Input_event_col.PATIENT_ID]) == common.MAPPING_PATIENT_ID:
                # Skip rows with our special patient id.
                continue

            # Apply names to each column
            patient_id, visit_id, itemid, hour, var_type, val_num, \
                val_min, val_max, ref_min, ref_max, val_default, hospital_expire_flag = cast_csv_row(row)

            # If we don't have a row mapping for this itemid, note that down
            if not itemid in item2feature:
                if not itemid in unknown_items:
                    unknown_items.append(itemid)
                continue

            # Get the object for this patient, creating one if we haven't seen them before
            if not visit_id in patient_visits:
                patient_visits[visit_id] = patient_visit.Patient_visit(patient_id, visit_id, hospital_expire_flag)
            subject = patient_visits[visit_id]

            # Compute the hour that this chart event happened at, relative to admission
            if hour >= 48:
                continue

            # Lookup Feature ID
            feature_id = item2feature[itemid]

            # Normalize valuenum
            valuenum_norm = common.normalize(stats, val_num, ref_min, ref_max, feature_id, var_type, common.NORM_METHOD, itemid)

            # Write valuenum to the remainder of the appropriate row
            # print(f"visit {visit_id} [{feature_id}, {hour}] ")
            subject.img[feature_id, hour:] = valuenum_norm

            if (i_batch >= common.CSV_PARSER_BATCH_SIZE) and (visit_id_prev != visit_id):
                print(f"\nDone {i} rows")
                print(f"Generating {len(patient_visits)} images")
                gen_start_time = time.time()
                generate_images(patient_visits)
                patient_visits.clear()
                i_batch = 0
                print("Image generation took {:.2f} sec".format(time.time() - gen_start_time))

            visit_id_prev = visit_id

            # Print progress indicator
            if (i % 500000) == 0:
                print('.', end='', flush=True)

            i = i + 1
            i_batch = i_batch + 1

    print("Parsing took {:.2f} sec".format(time.time() - parse_start_time))

    if len(unknown_items) > 0:
        print(f"Skipped unknown items:")
        for item in unknown_items:
            print(item)

    print(f"Generating {len(patient_visits)} images")
    gen_start_time = time.time()
    generate_images(patient_visits)
    print("Image generation took {:.2f} sec".format(time.time() - gen_start_time))

def generate_stats():
    """
    Function to build up stats based on embedded mapping info
    """
    item2feature = dict()
    stats = np.zeros((common.N_ROWS, common.Stats_col.N_COLS), dtype=np.float64)

    print(f"Parsing {csv_file}")
    parse_start_time = time.time()
    i = 0
    with open(csv_file, 'r') as f:
        for row in reader(f):
            if i == 0:
                # Skip header row, we'll parse the columns ourselves
                i = i + 1
                continue

            if int(row[common.Input_event_col.PATIENT_ID]) == common.MAPPING_PATIENT_ID:
                # We only care about rows with our special patient id.
                # In this special case, treat the visit_id column as row_id.
                row_id = int(row[common.Input_event_col.VISIT_ID])
                item2feature[int(row[common.Input_event_col.EVENT_ID])] = row_id

                stats[row_id][common.Stats_col.VAR_TYPE] = float(row[common.Input_event_col.VAR_TYPE])
                stats[row_id][common.Stats_col.VAL_NUM] = float(row[common.Input_event_col.VAL_NUM])
                stats[row_id][common.Stats_col.VAL_MIN] = float(row[common.Input_event_col.VAL_MIN])
                stats[row_id][common.Stats_col.VAL_MAX] = float(row[common.Input_event_col.VAL_MAX])
                stats[row_id][common.Stats_col.VAL_DEFAULT] = float(row[common.Input_event_col.VAL_DEFAULT])

                i = i + 1
            else:
                # We've finished reading the special mapping rows, so we're done here.
                break

    print(f"Generated stats for {i} itemids")

    return item2feature, stats

def cast_csv_row(row: list):
    """
    Casts each element of the provided row to the correct datatype
    """
    patient_id  = int(row[common.Input_event_col.PATIENT_ID])
    visit_id    = int(row[common.Input_event_col.VISIT_ID])
    itemid      = int(row[common.Input_event_col.EVENT_ID])
    hour        = int(row[common.Input_event_col.HOUR])
    var_type    = int(row[common.Input_event_col.VAR_TYPE])
    val_num     = float(row[common.Input_event_col.VAL_NUM])
    val_min     = float(row[common.Input_event_col.VAL_MIN])
    val_max     = float(row[common.Input_event_col.VAL_MAX])
    ref_min     = float(row[common.Input_event_col.REF_MIN])
    ref_max     = float(row[common.Input_event_col.REF_MAX])
    val_default = float(row[common.Input_event_col.VAL_DEFAULT])
    hospital_expire_flag = int(row[common.Input_event_col.DIED])

    return patient_id, visit_id, itemid, hour, var_type, \
        val_num, val_min, val_max, ref_min, ref_max, val_default, hospital_expire_flag

def compute_hour_diff(charttime: datetime, admittime: datetime) -> int:
    """
    Computes the difference in hours between charttime and admittime.
    Drops minutes and seconds info, so e.g. (2:59 - 1:00) = 1
    """
    # Clear minute and second and microsecond info
    charttime = charttime.replace(minute=0, second=0, microsecond=0)
    admittime = admittime.replace(minute=0, second=0, microsecond=0)

    # Compute the number of hours between the two times
    diff = int((charttime - admittime).total_seconds() / 3600)

    # Verify that the number of hours falls in our allowable range
    assert diff >= 0

    return diff

def generate_images(patient_visits: dict, test_split: float = 0.2, val_split: float = 0.3):
    """
    Generates an image for the given patient using OpenCV.
    Images are saved to IMAGES_DIR and named by patient_id.
    """

    test_start_idx = len(patient_visits) * (1 - val_split) * (1 - test_split)
    val_start_idx = len(patient_visits) * (1 - test_split)

    i = 0
    for key in patient_visits:
        visit = patient_visits[key]

        # Determine which split this patient will fall into and set the path accordingly.
        # Todo: Add a feature for shuffling splits
        img_path = os.getenv('IMAGES_DIR')
        if i >= test_start_idx and i < val_start_idx:
            img_path = os.path.join(img_path, 'test')
        elif i >= val_start_idx:
            img_path = os.path.join(img_path, 'val')
        else:
            img_path = os.path.join(img_path, 'train')

        # Todo: Come up with a way to open in 'w' mode the first time we touch a file in a given run
        with open(os.path.join(img_path, common.ANNOTATIONS_FILE_NAME), 'a', newline='') as f:
            label_writer = writer(f, delimiter=',')

            img_name = os.path.join(img_path, f"{visit.patient_id}_{visit.visit_id}{OUT_IMG_SUFFIX}.png")
            # Write label for this patient into labels.csv
            line = [c.strip() for c in f"{os.path.basename(img_name)}, {visit.hospital_expire_flag}".strip(', ').split(',')]
            label_writer.writerow(line)

            # Create 3-channel image
            img = np.zeros((common.N_ROWS, common.N_COLS, 3), dtype=int)

            # Populate it with patient timeline, duplicated in all 3 channels
            visit.img = visit.img
            img[:, :, 0] = visit.img
            img[:, :, 1] = visit.img
            img[:, :, 2] = visit.img

            cv2.imwrite(img_name, img)

            i = i + 1

if __name__ == "__main__":
    """
    Main section for when this file is invoked directly. Should only
    be used for debugging csv parsing down to image generation.
    """
    # Store csv_filename, and fail if not supplied
    try:
        csv_file = sys.argv[1]
    except:
        print("Usage: python csv_to_images.py <csv_file>")
        raise

    # Store output image name suffix if supplied, but carry on if not
    try:
        OUT_IMG_SUFFIX = sys.argv[2]
    except:
        pass

    path = os.path.join(os.getenv('DATA_DIR'), csv_file)
    parse_csv_to_images(path)