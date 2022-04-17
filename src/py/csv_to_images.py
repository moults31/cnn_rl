from csv import reader, writer
from typing import Tuple
from datetime import datetime
import os
import sys
import patient
import common
import numpy as np
import cv2
import time

# Optional suffix for output image name, use for debugging.
OUT_IMG_SUFFIX = ''

def parse_csv_to_images(csv_file: str, norm_method: common.Norm_method = common.Norm_method.MINMAX):
    """
    Top-level function that loads the provided 
    csv and saves images to disk as png.
    """
    patients = dict()
    unknown_items = list()

    print(f"Parsing {csv_file}")
    parse_start_time = time.time()
    with open(csv_file, 'r') as f:
        i = 0
        for row in reader(f):
            if i == 0:
                # Skip header row, we'll parse the columns ourselves
                i = i + 1
                continue

            # Apply names to each column
            subject_id, itemid, admittime, dischtime, charttime, \
                value, valuenum, valueuom, hospital_expire_flag = cast_csv_row(row)
            if not itemid in common.item2feature:
                if not itemid in unknown_items:
                    unknown_items.append(itemid)
                continue

            # Get the object for this patient, creating one if we haven't seen them before
            if not subject_id in patients:
                patients[subject_id] = patient.Patient(subject_id, admittime, dischtime, hospital_expire_flag)
            subject = patients[subject_id]

            # Compute the hour that this chart event happened at, relative to admission
            hour = compute_hour_diff(charttime, admittime)
            if hour >= 48:
                continue

            # Lookup Feature ID
            feature_id = common.item2feature[itemid]

            # Normalize valuenum
            valuenum_norm = common.normalize(valuenum, feature_id, norm_method, itemid)

            # Write valuenum to the remainder of the appropriate row
            subject.img[feature_id, hour:] = valuenum_norm

            # Print progress indicator
            if (i % 500000) == 0:
                print('.', end='', flush=True)
            i = i + 1

    print("Parsing took {:.2f} sec".format(time.time() - parse_start_time))

    if len(unknown_items) > 0:
        print(f"Skipped unknown items:")
        for item in unknown_items:
            print(item)

    print(f"Generating images")
    gen_start_time = time.time()
    generate_images(patients)
    print("Image generation took {:.2f} sec".format(time.time() - gen_start_time))

def cast_csv_row(row: list) -> Tuple[int, int, datetime, datetime, datetime, str, float, str, int]:
    """
    Casts each element of the provided row to the correct datatype
    """
    subject_id  = int(row[0])
    itemid      = int(row[1])
    admittime = datetime.strptime(row[2], '%Y-%m-%d %H:%M:%S.%f')
    dischtime = datetime.strptime(row[3], '%Y-%m-%d %H:%M:%S.%f')
    charttime = datetime.strptime(row[4], '%Y-%m-%d %H:%M:%S.%f')
    value       = row[5]
    valuenum    = float(row[6])
    valueuom    = row[7]
    hospital_expire_flag = int(row[8])

    return subject_id, itemid, admittime, dischtime, charttime, \
        value, valuenum, valueuom, hospital_expire_flag

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

def generate_images(patients: dict, test_split: float = 0.2, val_split: float = 0.3):
    """
    Generates an image for the given patient using OpenCV.
    Images are saved to IMAGES_DIR and named by subject_id.
    """

    test_start_idx = len(patients) * (1 - val_split) * (1 - test_split)
    val_start_idx = len(patients) * (1 - test_split)

    i = 0
    for subjectid in patients:
        subject = patients[subjectid]

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

            img_name = os.path.join(img_path, f"{subjectid}{OUT_IMG_SUFFIX}.png")
            # Write label for this patient into labels.csv
            line = [c.strip() for c in f"{os.path.basename(img_name)}, {subject.hospital_expire_flag}".strip(', ').split(',')]
            label_writer.writerow(line)

            # Create 3-channel image
            img = np.zeros((common.N_ROWS, common.N_COLS, 3), dtype=int)

            # Populate it with patient timeline, duplicated in all 3 channels
            subject.img = subject.img
            img[:, :, 0] = subject.img
            img[:, :, 1] = subject.img
            img[:, :, 2] = subject.img

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

    parse_csv_to_images(os.path.join(os.getenv('DATA_DIR'), csv_file))