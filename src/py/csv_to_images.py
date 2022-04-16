from csv import reader
from locale import normalize
from typing import Tuple
from datetime import datetime
import os
import sys
import patient
import common
import numpy as np
import cv2

# Optional suffix for output image name, use for debugging.
OUT_IMG_SUFFIX = ''

def parse_csv_to_images(csv_file: str, norm_method: common.Norm_method = common.Norm_method.MINMAX):
    """
    Top-level function that loads the provided 
    csv and saves images to disk as png.
    """
    patients = dict()
    unknown_items = list()

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

            # Normalize valuenum
            valuenum_norm = normalize(valuenum, itemid, norm_method)

            # Write valuenum to the remainder of the appropriate row
            img_row = common.item2feature[itemid]
            subject.img[img_row, hour:] = valuenum_norm

    print(f"Skipped unknown items:")
    for item in unknown_items:
        print(item)

    for subject_id in patients:
        generate_image(patients[subject_id])

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
    assert diff <= common.N_HOURS
    return diff

def normalize(valuenum: float, itemid: str, method: common.Norm_method) -> float:
    """
    Normalizes valuenum using the specified normalization method.
    MINMAX linearly interpolates the value within NORM_OUT_MIN and NORM_OUT_MAX.
    CUSTOM uses medical knowledge to assign a value 
    between NORM_OUT_MIN and NORM_OUT_MAX where higher is healthier.
    For more info see the paper.
    """
    assert method in common.Norm_method

    feature_id = common.item2feature[itemid]

    if method == common.Norm_method.MINMAX:
        min = common.stats[feature_id][common.Stats_col.MIN]
        max = common.stats[feature_id][common.Stats_col.MAX]
        return np.interp(valuenum, [min, max], [common.NORM_OUT_MIN, common.NORM_OUT_MAX])
    elif method == common.Norm_method.CUSTOM:
        raise NotImplementedError

def generate_image(subject: patient.Patient):
    """
    Generates an image for the given patient using OpenCV.
    Images are saved to IMAGES_DIR and named by subject_id.
    """
    # Create 3-channel image
    img = np.zeros((common.N_ROWS, common.N_COLS, 3), dtype=int)

    # Populate it with patient timeline, duplicated in all 3 channels
    img[:, :, 0] = subject.img
    img[:, :, 1] = subject.img
    img[:, :, 2] = subject.img

    cv2.imwrite(os.path.join(os.getenv('IMAGES_DIR'), f"{subject.subject_id}{OUT_IMG_SUFFIX}.png"), img)

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