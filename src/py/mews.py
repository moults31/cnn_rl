import os
import sys
import common
from csv import writer, reader

def evaluate_mews(csv_file_path):
    """
    Evaluates MEWS prediction metrics. Reads MEWS predictions
    and ground truth from mews_preds.csv
    """
    Y_pred_thresh = []
    Y_pred_warning = []
    Y_true = []

    # Read MEWS prediction and ground truth from csv
    i = 0
    with open(csv_file_path, 'r') as f:
        for row in reader(f):
            if i == 0:
                i = i + 1
                continue
            Y_pred_thresh.append(int(int(row[common.MEWS_rows.MEWS_SCORE]) > common.MEWS_THRESHOLD))
            Y_pred_warning.append(int(row[common.MEWS_rows.MEWS_WARNING]))
            Y_true.append(int(row[common.MEWS_rows.DIED]))
            i = i + 1

    # Evaluate the scores' predictions against the ground truth
    print(f"\nMEWS Scores Thresholded at {common.MEWS_THRESHOLD}:")
    common.evaluate_predictions(Y_true, Y_pred_thresh, score=Y_pred_thresh)
    print(f"\n\nMEWS Scores as predicted by MEWS Warning Score:")
    common.evaluate_predictions(Y_true, Y_pred_warning, score=Y_pred_warning)


if __name__ == "__main__":
    """
    Main section for when this file is invoked directly.
    """
    try:
        csv_file = sys.argv[1]
    except:
        print("Usage: python mews.py <csv_file>")
        raise

    # Store output image name suffix if supplied, but carry on if not
    try:
        OUT_IMG_SUFFIX = sys.argv[2]
    except:
        pass

    path = os.path.join( os.getenv('DATA_DIR'), csv_file)

    evaluate_mews(path)