from os import stat
import numpy as np
import common
import torch
from scipy.interpolate import UnivariateSpline


def compute_all(stats):
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

def compute_mews(dataloader, stats):
    """
    Computes sofa based on https://www.dascena.com/articles/sirs-sofa-qsofa-and-mews-the-alphabet-soup
    Directly uses the image rows for PaO2, FIO2, Platelets, Bilirubin, Hypotension, GCS, and Creatinine.
    Image rows manually generated from MIMIC-III database.

    Returns all predicted values as Y_pred and corresponding ground truth as Y_true
    """
    Y_pred = []
    Y_true = []
    for data, target in dataloader:
        # Respiratory rate
        feature_id = 9
        bounds = [
            stats[feature_id, common.Stats_col.VAL_MIN],
            8, 9, 15, 21, 30,
            stats[feature_id, common.Stats_col.VAL_MAX],
        ]
        scores = mews_compute_row(data, stats, feature_id, bounds)

        # Heart rate
        feature_id = 8
        bounds = [
            stats[feature_id, common.Stats_col.VAL_MIN],
            40, 51, 101, 111, 129,
            stats[feature_id, common.Stats_col.VAL_MAX],
        ]
        scores = scores + mews_compute_row(data, stats, feature_id, bounds)

        # Systolic Blood Pressure
        feature_id = 10
        bounds = [
            70, 81, 101, 200, 201, 
            stats[feature_id, common.Stats_col.VAL_MAX],
            stats[feature_id, common.Stats_col.VAL_MAX],
        ]
        scores = scores + mews_compute_row(data, stats, feature_id, bounds)

        # AVPU
        # TODO: Set bounds based on mapping of this variable
        # feature_id = 14
        # bounds = [
        #     stats[feature_id, common.Stats_col.VAL_MIN],
        #     35.0, 36.1, 38.1, 38.6,
        #     stats[feature_id, common.Stats_col.VAL_MAX],
        #     stats[feature_id, common.Stats_col.VAL_MAX],
        # ]
        # scores = scores + mews_compute_row(data, stats, feature_id, bounds)

        # Temperature (C)
        feature_id = 7
        bounds = [
            stats[feature_id, common.Stats_col.VAL_MIN],
            35.0, 36.1, 38.1, 38.6,
            stats[feature_id, common.Stats_col.VAL_MAX],
            stats[feature_id, common.Stats_col.VAL_MAX],
        ]
        scores = scores + mews_compute_row(data, stats, feature_id, bounds)

        # Hourly Urine
        # TODO: Set bounds based on mapping of this variable
        # feature_id = 115
        # bounds = [
        #     stats[feature_id, common.Stats_col.VAL_MIN],
        #     35.0, 36.1, 38.1, 38.6,
        #     stats[feature_id, common.Stats_col.VAL_MAX],
        #     stats[feature_id, common.Stats_col.VAL_MAX],
        # ]
        # scores = scores + mews_compute_row(data, stats, feature_id, bounds)

        # MEWS predicts true for mortality if score >= 4
        predictions = torch.gt(scores, 3).int()

        Y_pred.append(predictions)
        Y_true.append(target)

    Y_pred = np.concatenate(Y_pred, axis=0)
    Y_true = np.concatenate(Y_true, axis=0)

    return Y_pred, Y_true

def mews_compute_row(data, stats, feature_id, bounds):
    """
    Computes MEWS scores for each sample in data,
    for the row specified by feature_id.
    Directly uses the image rows for Respiratory Rate.
    Returns the score as an int
    """
    # Get the normalized data from the rows we want directly from the image
    norm = data[:,:,feature_id,:]

    # Create single-order splines so we can extrapolate 
    # these values back to their original ranges
    spl = get_spl_x_y(feature_id, stats)

    # Do the extrapolation
    reconst = spl(norm)

    return mews_get_score_from_bounds(reconst, stats, feature_id, bounds)

def mews_get_score_from_bounds(data, stats, feature_id, bounds):
    """
    Computes the MEWS score for each row of data given the provided bounds.
    Data has shape [batch, 1, n_hours]
    Returns the score as an int
    """
    rubric = [3, 2, 1, 0, 1, 2, 3]

    scores = []
    for sample in range(data.shape[0]):
        max_score = 0
        for hour in range(data.shape[2]):
            score = 0
            for i in range(len(bounds)):
                if data[sample, 0, hour] == stats[feature_id, common.Stats_col.VAL_MIN]:
                    # This was a zeroed-out pixel, so we can't assign a score for it
                    continue

                if data[sample, 0, hour] < bounds[i]:
                    score = rubric[i]
                    if score > max_score:
                        max_score = score
                    break
        scores.append(max_score)

    return torch.LongTensor(scores)


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
    compute_all()