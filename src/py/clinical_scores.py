from os import stat
import numpy as np
import common
import torch
from sklearn.metrics import accuracy_score, roc_auc_score
from scipy.interpolate import UnivariateSpline


def main():
    """
    Main function. Computes SOFA and MEWS and evaluates them.
    """
    print(f"Running on CUDA device: {common.device}")

    # Load images and labels for each split
    _, test_loader, val_loader = common.load_data()

    # Compute the scores
    mews_pred_test, mews_true_test = compute_mews(test_loader)
    mews_pred_val, mews_true_val = compute_mews(val_loader)

    # Evaluate the scores' predictions against the ground truth
    acc_test = accuracy_score(mews_true_test, mews_pred_test)
    acc_val = accuracy_score(mews_pred_val, mews_true_val)
    auc_test = roc_auc_score(mews_true_test, mews_pred_test)
    auc_val = roc_auc_score(mews_true_val, mews_pred_val)

    print(("Test Accuracy: " + str(acc_test)))
    print(("Validation Accuracy: " + str(acc_val)))
    print(("Test AUC: " + str(auc_test)))
    print(("Validation AUC: " + str(auc_val)))

    common.dump_outputs(mews_pred_val, mews_true_val)

def compute_mews(dataloader):
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
        scores = mews_compute_respiratory_rate(data)
        scores = scores + mews_compute_heart_rate(data)

        predictions = torch.gt(scores, 3)

        Y_pred.append(predictions)
        Y_true.append(target)

    Y_pred = np.concatenate(Y_pred, axis=0)
    Y_true = np.concatenate(Y_true, axis=0)

    return Y_pred, Y_true

def mews_compute_respiratory_rate(data) -> int:
    """
    Computes the "Respiration" row of MEWS
    Directly uses the image rows for Respiratory Rate.
    Returns the score as an int
    """
    # Get the normalized data from the rows we want directly from the image
    resp = data[:,:,8,:]

    # Create single-order splines so we can extrapolate 
    # these values back to their original ranges
    spl_resp = get_spl_x_y(8)

    # Do the extrapolation
    resp_reconst = spl_resp(resp)

    # Assign bounds for scores
    bounds = [
        common.stats[8, common.Stats_col.SOFTMIN],
        8, 9, 15, 21, 30,
        common.stats[8, common.Stats_col.SOFTMAX],
    ]

    return mews_get_score_from_bounds(resp_reconst, bounds)

def mews_compute_heart_rate(data) -> int:
    """
    Computes the "Heart Rate" row of MEWS
    Directly uses the image rows for Respiratory Rate.
    Returns the score as an int
    """
    # Get the normalized data from the rows we want directly from the image
    norm = data[:,:,7,:]

    # Create single-order splines so we can extrapolate 
    # these values back to their original ranges
    spl = get_spl_x_y(7)

    # Do the extrapolation
    reconst = spl(norm)

    # Assign bounds for scores
    bounds = [
        common.stats[7, common.Stats_col.SOFTMIN],
        40, 51, 101, 111, 129,
        common.stats[7, common.Stats_col.SOFTMAX],
    ]

    return mews_get_score_from_bounds(reconst, bounds)

def mews_get_score_from_bounds(data, bounds):
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
                if data[sample, 0, hour] == bounds[0]:
                    # This was a zeroed-out pixel, so we can't assign a score for it
                    continue

                if data[sample, 0, hour] < bounds[i]:
                    # print(f"{data[sample, 0, hour]=}")
                    # print(f"{bounds[i]=}")
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

def get_spl_x_y(feature_id: int):
    """
    Helper function for 1d linear extrapolating the 
    normalized values for a given feature back to their original bounds 
    """
    if common.NORM_METHOD == common.Norm_method.MINMAX:
        x = [0.0, 1.0]
        y = [common.stats[feature_id, common.Stats_col.SOFTMIN], common.stats[feature_id, common.Stats_col.SOFTMAX]]
        spl = UnivariateSpline(x, y, k=1)
    else:
        raise NotImplementedError
    return spl


def eval_score(model, dataloader):
    """
    :return:
        Y_pred_test: prediction of model on the test dataloder.
            Should be an 2D numpy float array where the second dimension has length 2.
        Y_pred_val: prediction of model on the validation dataloder.
            Should be an 2D numpy float array where the second dimension has length 2.
        Y_test: truth labels for the test set. Should be an numpy array of ints
        Y_val: truth labels for the val set. Should be an numpy array of ints
    """
    model.eval()
    Y_score = torch.FloatTensor()
    Y_pred = []
    Y_true = []
    for data, target in dataloader:
        data = data.to(common.device).squeeze(1)
        outputs = model(data)
        _, predictions = torch.max(outputs, 1)
        predictions = predictions.to('cpu')
        y_hat = outputs[:,1]

        Y_score = np.concatenate((Y_score, y_hat.to('cpu').detach().numpy()), axis=0)
        Y_pred.append(predictions)
        Y_true.append(target)

    Y_pred = np.concatenate(Y_pred, axis=0)
    Y_true = np.concatenate(Y_true, axis=0)

    return Y_score, Y_pred, Y_true

if __name__ == "__main__":
    """
    Main section for when this file is invoked directly.
    """
    main()