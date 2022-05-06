import os
import sys
import common
from csv import writer, reader

def evaluate_sofa(csv_file_path):
    """
    Evaluates SOFA prediction metrics. Reads SOFA predictions
    and ground truth from sofa_preds.csv
    """
    Y_pred_thresh = []
    Y_pred_est = []
    Y_true = []

    # Read SOFA prediction and ground truth from csv
    i = 0
    with open(csv_file_path, 'r') as f:
        for row in reader(f):
            if i == 0:
                i = i + 1
                continue
            Y_pred_thresh.append(int(int(row[common.SOFA_rows.SOFA_SCORE]) > common.SOFA_SCORE_THRESHOLD))
            Y_pred_est.append(int(float(row[common.SOFA_rows.EST_MORTALITY]) > common.SOFA_EST_THRESHOLD))
            Y_true.append(int(row[common.SOFA_rows.DIED]))
            i = i + 1

    # Evaluate the scores' predictions against the ground truth
    print(f"\nSOFA Scores Thresholded at {common.SOFA_SCORE_THRESHOLD}:")
    common.evaluate_predictions(Y_true, Y_pred_thresh, score=Y_pred_thresh)
    print(f"\n\nSOFA Est Mort Thresholded at {common.SOFA_EST_THRESHOLD}:")
    common.evaluate_predictions(Y_true, Y_pred_est, score=Y_pred_est)

if __name__ == "__main__":
    """
    Main section for when this file is invoked directly.
    """
    try:
        csv_file = sys.argv[1]
    except:
        print("Usage: python sofa.py <csv_file>")
        raise

    # Store output image name suffix if supplied, but carry on if not
    try:
        OUT_IMG_SUFFIX = sys.argv[2]
    except:
        pass

    path = os.path.join( os.getenv('DATA_DIR'), csv_file)

    evaluate_sofa(path)