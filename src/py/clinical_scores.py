import os
import numpy as np
import common
import torch
from csv import writer, reader
from scipy.interpolate import UnivariateSpline

def compute_all(stats, patient_visits):
    """
    Main function. Computes SOFA and MEWS and evaluates them.
    """
    print(f"Running on CUDA device: {common.device}")

    # Load images and labels for each split
    _, test_loader, val_loader = common.load_data()

    # Compute the scores
    mews_pred_test, mews_true_test = compute_mews(test_loader, stats)
    mews_pred_val, mews_true_val = compute_mews(val_loader, stats)

    # Evaluate the scores' predictions against the ground truth
    print("\nScores from test split:")
    common.evaluate_predictions(mews_true_test, mews_pred_test, score=mews_pred_test)
    print("\nScores from val split:")
    common.evaluate_predictions(mews_true_val, mews_pred_val, score=mews_pred_val)

    # Dump val split truth/preds for manual inspection
    common.dump_outputs(mews_pred_val, mews_true_val)

def compute_mews(stats, patient_visits):
    """
    Computes sofa based on https://www.dascena.com/articles/sirs-sofa-qsofa-and-mews-the-alphabet-soup
    Directly uses the image rows for PaO2, FIO2, Platelets, Bilirubin, Hypotension, GCS, and Creatinine.
    Image rows manually generated from MIMIC-III database.

    Returns all predicted values as Y_pred and corresponding ground truth as Y_true
    """
    Y_pred = []
    Y_true = []
    i = 0
    for visit_id in patient_visits:
        visit = patient_visits[visit_id]

        # Respiratory rate
        feature_id = common.mews_featureids[common.MEWS_rows.RESPIRATORY_RATE]
        bounds = [
            stats[feature_id, common.Stats_col.VAL_MIN],
            8, 9, 15, 21, 30,
            stats[feature_id, common.Stats_col.VAL_MAX],
        ]
        scores = mews_get_score_from_bounds(visit.mews[common.MEWS_rows.RESPIRATORY_RATE], stats, feature_id, bounds)

        # Heart rate
        feature_id = common.mews_featureids[common.MEWS_rows.HEART_RATE]
        bounds = [
            stats[feature_id, common.Stats_col.VAL_MIN],
            40, 51, 101, 111, 129,
            stats[feature_id, common.Stats_col.VAL_MAX],
        ]
        scores = scores + mews_get_score_from_bounds(visit.mews[common.MEWS_rows.HEART_RATE], stats, feature_id, bounds)

        # Systolic Blood Pressure
        feature_id = common.mews_featureids[common.MEWS_rows.SYSTOLIC]
        bounds = [
            70, 81, 101, 200, 201, 
            stats[feature_id, common.Stats_col.VAL_MAX],
            stats[feature_id, common.Stats_col.VAL_MAX],
        ]
        scores = scores + mews_get_score_from_bounds(visit.mews[common.MEWS_rows.SYSTOLIC], stats, feature_id, bounds)

        # AVPU
        # TODO: Set bounds based on mapping of this variable
        # feature_id = common.mews_featureids[common.MEWS_rows.AVPU]
        # bounds = [
        #     stats[feature_id, common.Stats_col.VAL_MIN],
        #     35.0, 36.1, 38.1, 38.6,
        #     stats[feature_id, common.Stats_col.VAL_MAX],
        #     stats[feature_id, common.Stats_col.VAL_MAX],
        # ]
        # scores = scores + mews_get_score_from_bounds(visit.mews[common.MEWS_rows.AVPU], stats, feature_id, bounds)

        # Temperature (C)
        feature_id = common.mews_featureids[common.MEWS_rows.TEMPERATURE]
        bounds = [
            stats[feature_id, common.Stats_col.VAL_MIN],
            35.0, 36.1, 38.1, 38.6,
            stats[feature_id, common.Stats_col.VAL_MAX],
            stats[feature_id, common.Stats_col.VAL_MAX],
        ]
        scores = scores + mews_get_score_from_bounds(visit.mews[common.MEWS_rows.TEMPERATURE], stats, feature_id, bounds)

        # Hourly Urine
        # TODO: Set bounds based on mapping of this variable
        # feature_id = common.mews_featureids[common.MEWS_rows.HOURLY_URINE]
        # bounds = [
        #     stats[feature_id, common.Stats_col.VAL_MIN],
        #     35.0, 36.1, 38.1, 38.6,
        #     stats[feature_id, common.Stats_col.VAL_MAX],
        #     stats[feature_id, common.Stats_col.VAL_MAX],
        # ]
        # scores = scores + mews_get_score_from_bounds(visit.mews[common.MEWS_rows.HOURLY_URINE], stats, feature_id, bounds)

        # MEWS predicts true for mortality if score >= 4
        prediction = int(scores > 3)

        # Build up path, placing file in appropriate split
        preds_path = os.getenv('CLINICAL_SCORES_DIR')
        split = common.get_split_as_string(i, len(patient_visits))
        preds_path = os.path.join(preds_path, split)

        # Todo: Come up with a way to open in 'w' mode the first time we touch a file in a given run
        with open(os.path.join(preds_path, common.CS_MEWS_PREDS_FILE_NAME), 'a', newline='') as f:
            mews_writer = writer(f, delimiter=',')

            # Write this line of 'prediction', 'truth' to the appropriate file
            line = [c.strip() for c in f"{prediction}, {visit.hospital_expire_flag}".strip(', ').split(',')]
            mews_writer.writerow(line)

        i = i + 1

def mews_get_score_from_bounds(data, stats, feature_id, bounds):
    """
    Computes the MEWS score for each row of data given the provided bounds.
    Data has shape [batch, 1, n_hours]
    Returns the score as an int
    """
    rubric = [3, 2, 1, 0, 1, 2, 3]

    max_score = 0
    for hour in range(data.shape[0]):
        score = 0
        for i in range(len(bounds)):
            if data[hour] == stats[feature_id, common.Stats_col.VAL_MIN]:
                # This was a zeroed-out pixel, so we can't assign a score for it
                continue

            if data[hour] < bounds[i]:
                score = rubric[i]
                if score > max_score:
                    max_score = score
                break
    return score

def evaluate_mews():
    Y_train_pred = []
    Y_train_true = []
    Y_test_pred = []
    Y_test_true = []
    Y_val_pred = []
    Y_val_true = []

    # Read MEWS prediction and ground truth for all 3 splits
    preds_train_path = os.path.join(os.getenv('CLINICAL_SCORES_DIR'), 'train', common.CS_MEWS_PREDS_FILE_NAME)
    preds_test_path = os.path.join(os.getenv('CLINICAL_SCORES_DIR'), 'test', common.CS_MEWS_PREDS_FILE_NAME)
    preds_val_path = os.path.join(os.getenv('CLINICAL_SCORES_DIR'), 'val', common.CS_MEWS_PREDS_FILE_NAME)

    with open(preds_train_path, 'r') as f:
        for row in reader(f):
            Y_train_pred.append(int(row[0]))
            Y_train_true.append(int(row[1]))
    with open(preds_test_path, 'r') as f:
        for row in reader(f):
            Y_test_pred.append(int(row[0]))
            Y_test_true.append(int(row[1]))
    with open(preds_val_path, 'r') as f:
        for row in reader(f):
            Y_val_pred.append(int(row[0]))
            Y_val_true.append(int(row[1]))

    # Evaluate the scores' predictions against the ground truth
    print("\nMEWS Scores from train split:")
    common.evaluate_predictions(Y_train_true, Y_train_pred, score=Y_train_pred)
    print("\nMEWS Scores from test split:")
    common.evaluate_predictions(Y_test_true, Y_test_pred, score=Y_test_pred)
    print("\nMEWS Scores from val split:")
    common.evaluate_predictions(Y_val_true, Y_val_pred, score=Y_val_pred)

def compute_sofa(dataloader):
    """
    Computes sofa based on https://www.dascena.com/articles/sirs-sofa-qsofa-and-mews-the-alphabet-soup
    Directly uses the image rows for PaO2, FIO2, Platelets, Bilirubin, Hypotension, GCS, and Creatinine.
    Image rows manually generated from MIMIC-III database.

    Returns all predicted values as Y_pred and corresponding ground truth as Y_true
    """
    Y_pred = []
    Y_true = []
    for data, target in dataloader:
        # _, predictions = torch.max(outputs, 1)
        # predictions = predictions.to('cpu')

        predictions = 0
        predictions = predictions + sofa_compute_respiration(data)

        Y_pred.append(predictions)
        Y_true.append(target)

    Y_pred = np.concatenate(Y_pred, axis=0)
    Y_true = np.concatenate(Y_true, axis=0)

    return Y_pred, Y_true

def sofa_compute_respiration(data) -> int:
    """
    Computes the "Respiration" row of sofa based on 
    https://www.dascena.com/articles/sirs-sofa-qsofa-and-mews-the-alphabet-soup
    Directly uses the image rows for PaO2, FIO2.
    Returns the score as an int
    """
    # Get the normalized data from the rows we want directly from the image
    pao2 = data[:,:,41,:]
    fio2 = data[:,:,12,:]

    # Create single-order splines so we can extrapolate 
    # these values back to their original ranges
    spl_pao2 = get_spl_x_y(41)
    spl_fio2 = get_spl_x_y(12)

    # Do the extrapolation
    pao2_reconst = spl_pao2(pao2)
    fio2_reconst = spl_fio2(fio2)

    respiration = np.divide(pao2_reconst, fio2_reconst, where=fio2_reconst!=0)

    bounds = common.normalize(400, 41, common.NORM_METHOD)

    # bounds = [
    #     common.normalize(400, 41, norm_method),
    #     common.normalize(400, itemid, norm_method)
    # ]
    
    return 0

def get_spl_x_y(feature_id: int, stats):
    """
    Helper function for 1d linear extrapolating the 
    normalized values for a given feature back to their original bounds 
    """
    if (common.NORM_METHOD == common.Norm_method.MINMAX) or (common.NORM_METHOD == common.Norm_method.SOFTMINMAX):
        x = [0.0, 1.0]
        y = [stats[feature_id, common.Stats_col.VAL_MIN], stats[feature_id, common.Stats_col.VAL_MAX]]
        spl = UnivariateSpline(x, y, k=1)
    else:
        raise NotImplementedError
    return spl

if __name__ == "__main__":
    """
    Main section for when this file is invoked directly.
    """
    evaluate_mews()