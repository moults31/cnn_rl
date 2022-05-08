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

# Name for generated cohort
COHORT_NAME = ''

def parse_csv_to_images( csv_file: str ):
    """
    Top-level function that loads the provided 
    csv and saves images to disk as png.
    """
    patient_visits = dict()
    unknown_items  = list()

    item2feature, stats = generate_stats()

    print( f"Parsing {csv_file}" )
    parse_start_time = time.time()
    with open( csv_file, 'r' ) as f:
    
        i             = 0
        i_batch       = 0
        visit_id_prev = 0
        
        for row in reader(f):
            if i == 0:
                # Skip header row, we'll parse the columns ourselves
                i = i + 1
                continue

            if int( row[common.Input_event_col.PATIENT_ID] ) == common.MAPPING_PATIENT_ID:
                # Skip rows with our special patient id.
                continue

            # Apply names to each column
            patient_id, visit_id, itemid, hour, var_type, val_num, \
                val_min, val_max, ref_min, ref_max, val_default, hospital_expire_flag = cast_csv_row( row )

            # Skip patient ids outside our range limits
            if common.CSV_PARSER_PATIENTID_DO_LIMIT:
                if patient_id < common.CSV_PARSER_PATIENTID_MIN:
                    continue
                if patient_id > common.CSV_PARSER_PATIENTID_MAX:
                    break

            # If the hour is out of the range we care about, skip this row
            if hour >= common.N_HOURS:
                continue

            # If we don't have a row mapping for this itemid, note that down
            if not itemid in item2feature:
                if not itemid in unknown_items:
                    unknown_items.append( itemid )
                continue

            # Get the object for this patient, creating one if we haven't seen them before
            if not visit_id in patient_visits:
                patient_visits[visit_id] = patient_visit.Patient_visit( patient_id, visit_id, hospital_expire_flag, stats, item2feature )
            subject = patient_visits[visit_id]

            # Lookup Feature ID
            feature_id = item2feature[itemid]

            # If this item ID falls in the range of our special ones, handle that
            if itemid in [item.value for item in common.Special_itemids]:
                handle_special_itemid( itemid, val_num, subject, stats, item2feature )
            else:
                # Otherwise, normalize valuenum
                valuenum_norm = common.normalize( stats, val_num, ref_min, ref_max, feature_id, var_type, common.NORM_METHOD, itemid )

                if var_type == common.Var_type.BINARY_POINT:
                    # Write valuenum to specified hour without carry-over
                    subject.img[feature_id, hour] = valuenum_norm
                else:
                    # Write valuenum to the remainder of the appropriate row
                    subject.img[feature_id, hour:] = valuenum_norm

            # Record clinical score component vals if relevant to this itemid
            record_clinical_score_component(itemid, val_num, hour, subject, item2feature)

            # Generate images if we've completed a batch
            if (i_batch >= common.CSV_PARSER_BATCH_SIZE) and (visit_id_prev != visit_id):
                print(f"\nDone {i} rows")
                process_batch_images_and_clinical_scores(patient_visits, stats, item2feature)
                patient_visits.clear()
                i_batch = 0

            # Update visit_id_prev so we can track whether visit_id changes on next iter
            visit_id_prev = visit_id

            # Print progress indicator
            if (i % 500000) == 0:
                print('.', end='', flush=True)

            i = i + 1
            i_batch = i_batch + 1

    # Report any itemids encountered on input that we don't have a stats mapping for
    if len(unknown_items) > 0:
        print(f"Skipped unknown items:")
        for item in unknown_items:
            print(item)

    # Process the final partial batch
    process_batch_images_and_clinical_scores( patient_visits, stats, item2feature )

    print("Parsing took {:.2f} sec".format( time.time() - parse_start_time) )

def process_batch_images_and_clinical_scores( patient_visits, stats, item2feature ):
    """
    Function to process a batch. Generates images, tallies braden/morse, and computes MEWS/SOFA.
    """
    # Generate images
    print( f"Generating {len(patient_visits)} images" )
    gen_start_time = time.time()
    generate_images( patient_visits )
    print("Image generation took {:.2f} sec".format( time.time() - gen_start_time) )

    # Tally braden/morse
    tally_clinical_scores( patient_visits, stats, item2feature )


def generate_stats():
    """
    Function to build up stats based on embedded mapping info
    """
    item2feature = dict()
    stats = np.zeros((common.N_ROWS, common.Stats_col.N_COLS), dtype=np.float64)

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

                stats[row_id][common.Stats_col.VAR_TYPE]    = float( row[common.Input_event_col.VAR_TYPE]    )
                stats[row_id][common.Stats_col.VAL_NUM ]    = float( row[common.Input_event_col.VAL_NUM ]    )
                stats[row_id][common.Stats_col.VAL_MIN ]    = float( row[common.Input_event_col.VAL_MIN ]    )
                stats[row_id][common.Stats_col.VAL_MAX ]    = float( row[common.Input_event_col.VAL_MAX ]    )
                stats[row_id][common.Stats_col.REF_MIN ]    = float( row[common.Input_event_col.REF_MIN ]    )
                stats[row_id][common.Stats_col.REF_MAX ]    = float( row[common.Input_event_col.REF_MAX ]    )
                stats[row_id][common.Stats_col.VAL_DEFAULT] = float( row[common.Input_event_col.VAL_DEFAULT] )

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
    patient_id  = int(   row[common.Input_event_col.PATIENT_ID]  )
    visit_id    = int(   row[common.Input_event_col.VISIT_ID]    )
    itemid      = int(   row[common.Input_event_col.EVENT_ID]    )
    hour        = int(   row[common.Input_event_col.HOUR]        )
    var_type    = int(   row[common.Input_event_col.VAR_TYPE]    )
    val_num     = float( row[common.Input_event_col.VAL_NUM]     )
    val_min     = float( row[common.Input_event_col.VAL_MIN]     )
    val_max     = float( row[common.Input_event_col.VAL_MAX]     )
    ref_min     = float( row[common.Input_event_col.REF_MIN]     )
    ref_max     = float( row[common.Input_event_col.REF_MAX]     )
    val_default = float( row[common.Input_event_col.VAL_DEFAULT] )
    hospital_expire_flag = int( row[common.Input_event_col.DIED] )

    return patient_id, visit_id, itemid, hour, var_type, \
        val_num, val_min, val_max, ref_min, ref_max, val_default, hospital_expire_flag

def record_clinical_score_component(itemid, val_num, hour, visit, item2feature):
    """
    Record the value of a clinical score component for a given patient on a given hour
    """
    if itemid in common.braden_item2row:
        visit.braden[ common.braden_item2row[itemid], hour ] = val_num

    if itemid in common.morse_item2row:
        visit.morse[ common.morse_item2row[itemid], hour ] = val_num


def tally_clinical_scores( patient_visits, stats, item2feature ):
    """
    Handles itemids that have special meanings. Often involves directly updating
    the image for the given patient. 
    """
    braden_cumulative_default_normalized = common.normalize(
        stats,
        stats[common.BRADEN_ROWID, common.Stats_col.VAL_DEFAULT],
        stats[common.BRADEN_ROWID, common.Stats_col.REF_MIN],
        stats[common.BRADEN_ROWID, common.Stats_col.REF_MAX],
        common.BRADEN_ROWID,
        stats[common.BRADEN_ROWID, common.Stats_col.VAR_TYPE],
        common.NORM_METHOD
    )

    morse_cumulative_default_normalized = common.normalize(
        stats,
        stats[common.MORSE_ROWID, common.Stats_col.VAL_DEFAULT],
        stats[common.MORSE_ROWID, common.Stats_col.REF_MIN],
        stats[common.MORSE_ROWID, common.Stats_col.REF_MAX],
        common.MORSE_ROWID,
        stats[common.MORSE_ROWID, common.Stats_col.VAR_TYPE],
        common.NORM_METHOD
    )

    # Compute bounds for normalization
    for key in patient_visits:
        visit = patient_visits[key]

        # Assign cumulative sum of braden/morse scores for each hour
        braden = visit.braden.sum(axis=0)
        morse = visit.morse.sum(axis=0)

        braden_normalized = np.zeros_like(braden)
        morse_normalized = np.zeros_like(morse)
        for hour in range(common.N_HOURS):
            # Normalize
            braden_normalized[hour] = common.normalize(
                stats,
                braden[hour],
                stats[common.BRADEN_ROWID, common.Stats_col.REF_MIN],
                stats[common.BRADEN_ROWID, common.Stats_col.REF_MAX],
                common.BRADEN_ROWID,
                stats[common.BRADEN_ROWID, common.Stats_col.VAR_TYPE],
                common.NORM_METHOD
            )

            morse_normalized[hour] = common.normalize(
                stats,
                morse[hour],
                stats[common.MORSE_ROWID, common.Stats_col.REF_MIN],
                stats[common.MORSE_ROWID, common.Stats_col.REF_MAX],
                common.MORSE_ROWID,
                stats[common.MORSE_ROWID, common.Stats_col.VAR_TYPE],
                common.NORM_METHOD
            )

            # Write morse/braden timelines to image
            if braden[hour] != braden_cumulative_default_normalized:
                visit.img[common.BRADEN_ROWID, hour:] = braden_normalized[hour]
                
            if morse[hour] != morse_cumulative_default_normalized:
                visit.img[common.MORSE_ROWID, hour:] = morse_normalized[hour]

def handle_special_itemid(itemid, val_num, visit, stats, item2feature):
    """
    Handles itemids that have special meanings. Often involves directly updating
    the image for the given patient. 
    """

    if itemid == common.Special_itemids.ADMIT_HOUR:
        hour_reel = np.mod(np.arange(visit.img.shape[1]), 24)
        hour_reel = np.roll(hour_reel, int(-val_num))
        hour_reel = (hour_reel / 23.0) * common.NORM_OUT_MAX
        visit.img[itemid, :] = hour_reel

def generate_images(patient_visits: dict):
    """
    Generates an image for each patientvisit using OpenCV.
    Images are saved in the following structure:
    <repo>/images/<orig_cohort_name>/master/<all_the_images>
    """
    i = 0
    img_path = os.getenv( 'IMAGES_DIR' )

    img_path = os.path.join( img_path, COHORT_NAME, 'master' )

    try:
        os.makedirs(img_path)
    except:
        pass

    for key in patient_visits:
        visit = patient_visits[key]

        # Name image based on patient, visit, ground truth
        img_name = os.path.join( 
            img_path, 
            f"{visit.patient_id}_{visit.visit_id}_{visit.hospital_expire_flag}.png" 
        )

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
        print("Usage: python csv_to_images.py <csv_file> <cohort_name>")
        raise

    # Store output image name suffix if supplied, but carry on if not
    try:
        COHORT_NAME = sys.argv[2]
    except:
        print("Usage: python csv_to_images.py <csv_file> <cohort_name>")
        raise

    path = os.path.join( os.getenv('DATA_DIR'), csv_file )
    parse_csv_to_images( path )
