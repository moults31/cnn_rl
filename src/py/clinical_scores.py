import os
import numpy as np
import common
import torch
from csv import writer, reader
from scipy.interpolate import UnivariateSpline

MEWS_BOUNDS = None
SOFA_BOUNDS = None

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

def compute_evaluate_mews_from_images(stats):
    """
    Computes MEWS from generated images (as opposed to raw inputs).
    """
    print(f"Running on CUDA device: {common.device}")

    # Load images and labels for each split
    _, test_loader, val_loader = common.load_data()

    # Compute the scores
    mews_pred_test, mews_true_test = compute_mews_from_images(test_loader, stats)
    mews_pred_val, mews_true_val = compute_mews_from_images(val_loader, stats)

    # Evaluate the scores' predictions against the ground truth
    print("\nScores from test split:")
    common.evaluate_predictions(mews_true_test, mews_pred_test, score=mews_pred_test)
    print("\nScores from val split:")
    common.evaluate_predictions(mews_true_val, mews_pred_val, score=mews_pred_val)

    # Dump val split truth/preds for manual inspection
    common.dump_outputs(mews_pred_val, mews_true_val)

def compute_mews_from_images(dataloader, stats):
    """
    Computes sofa based on https://www.dascena.com/articles/sirs-sofa-qsofa-and-mews-the-alphabet-soup
    Directly uses the image rows for PaO2, FIO2, Platelets, Bilirubin, Hypotension, GCS, and Creatinine.
    Image rows manually generated from MIMIC-III database.

    Returns all predicted values as Y_pred and corresponding ground truth as Y_true
    """
    Y_pred = []
    Y_true = []
    for data, target in dataloader:
        mews_components = [
            common.MEWS_rows.RESPIRATORY_RATE,
            common.MEWS_rows.HEART_RATE,
            common.MEWS_rows.SYSTOLIC,
            # common.MEWS_rows.AVPU, # Skip until bounds are set properly
            common.MEWS_rows.TEMPERATURE,
            # common.MEWS_rows.HOURLY_URINE, # Skip until bounds are set properly
        ]

        # Compute MEWS score for this patient
        scores = torch.zeros((data.shape[0], common.N_HOURS))
        for component in mews_components:
            feature_id = common.mews_featureids[component]
            bounds = mews_get_bounds_for_feature(feature_id, stats)
            scores = scores + mews_get_score_from_images(data, stats, feature_id, bounds)

        # print(scores)
        scores = scores.max(axis=1).values
        # print(scores)

        predictions = torch.gt(scores, 3).int()

        Y_pred.append(predictions)
        Y_true.append(target)

    Y_pred = np.concatenate(Y_pred, axis=0)
    Y_true = np.concatenate(Y_true, axis=0)

    return Y_pred, Y_true

def compute_mews(patient_visits, stats):
    """
    Computes sofa based on https://www.dascena.com/articles/sirs-sofa-qsofa-and-mews-the-alphabet-soup
    Directly uses the image rows for PaO2, FIO2, Platelets, Bilirubin, Hypotension, GCS, and Creatinine.
    Image rows manually generated from MIMIC-III database.

    Returns all predicted values as Y_pred and corresponding ground truth as Y_true
    """
    i = 0
    for visit_id in patient_visits:
        visit = patient_visits[visit_id]

        mews_components = [
            common.MEWS_rows.RESPIRATORY_RATE,
            common.MEWS_rows.HEART_RATE,
            common.MEWS_rows.SYSTOLIC,
            # common.MEWS_rows.AVPU, # Skip until bounds are set properly
            common.MEWS_rows.TEMPERATURE,
            # common.MEWS_rows.HOURLY_URINE, # Skip until bounds are set properly
        ]

        # Compute MEWS score for this patient
        scores = np.zeros((common.N_HOURS))
        for component in mews_components:
            feature_id = common.mews_featureids[component]
            bounds = mews_get_bounds_for_feature(feature_id, stats)
            scores = scores + mews_get_score_from_bounds(visit.mews[component], stats, feature_id, bounds)

        scores = scores.max()

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

def mews_get_bounds_for_feature(feature_id, stats):
    global MEWS_BOUNDS
    if MEWS_BOUNDS is None:
        # MEWS_BOUNDS doesn't exist, let's build it now
        # Note that runtime building is required since we need access to stats
        MEWS_BOUNDS = [
            [
                stats[common.mews_featureids[common.MEWS_rows.RESPIRATORY_RATE], common.Stats_col.VAL_MIN],
                8, 9, 15, 21, 30,
                stats[common.mews_featureids[common.MEWS_rows.RESPIRATORY_RATE], common.Stats_col.VAL_MAX],
            ],
            [
                stats[common.mews_featureids[common.MEWS_rows.HEART_RATE], common.Stats_col.VAL_MIN],
                40, 51, 101, 111, 129,
                stats[common.mews_featureids[common.MEWS_rows.HEART_RATE], common.Stats_col.VAL_MAX],
            ],
            [
                70, 81, 101, 200, 201, 
                stats[common.mews_featureids[common.MEWS_rows.SYSTOLIC], common.Stats_col.VAL_MAX],
                stats[common.mews_featureids[common.MEWS_rows.SYSTOLIC], common.Stats_col.VAL_MAX],
            ],
            [   # TODO: Set bounds appropriately
                stats[common.mews_featureids[common.MEWS_rows.AVPU], common.Stats_col.VAL_MIN],
                35.0, 36.1, 38.1, 38.6,
                stats[common.mews_featureids[common.MEWS_rows.AVPU], common.Stats_col.VAL_MAX],
                stats[common.mews_featureids[common.MEWS_rows.AVPU], common.Stats_col.VAL_MAX],
            ],
            [
                stats[common.mews_featureids[common.MEWS_rows.TEMPERATURE], common.Stats_col.VAL_MIN],
                35.0, 36.1, 38.1, 38.6,
                stats[common.mews_featureids[common.MEWS_rows.TEMPERATURE], common.Stats_col.VAL_MAX],
                stats[common.mews_featureids[common.MEWS_rows.TEMPERATURE], common.Stats_col.VAL_MAX],
            ],
            [   # TODO: Set bounds appropriately
                stats[common.mews_featureids[common.MEWS_rows.HOURLY_URINE], common.Stats_col.VAL_MIN],
                35.0, 36.1, 38.1, 38.6,
                stats[common.mews_featureids[common.MEWS_rows.HOURLY_URINE], common.Stats_col.VAL_MAX],
                stats[common.mews_featureids[common.MEWS_rows.HOURLY_URINE], common.Stats_col.VAL_MAX],
            ],
        ]

    # MEWS_BOUNDS exists, so look up the requested bounds row
    # TODO: Redesign to avoid this slow for-loop lookup
    for i in range(common.MEWS_rows.N_ROWS):
        if feature_id == common.mews_featureids[i]:
            return MEWS_BOUNDS[i]

def mews_get_score_from_bounds(data, stats, feature_id, bounds):
    """
    Computes the MEWS score for each row of data given the provided bounds.
    Data has shape [batch, 1, n_hours]
    Returns the score as an int
    """
    rubric = [3, 2, 1, 0, 1, 2, 3]

    scores = np.zeros_like(data)

    for hour in range(data.shape[0]):
        if data[hour] == stats[feature_id, common.Stats_col.VAL_DEFAULT]:
            # This was a default value, so leave it at score 0
            continue
        for i in range(len(bounds)):


            if data[hour] < bounds[i]:
                scores[hour] = rubric[i]
                break
    return scores

def evaluate_mews():
    """
    Evaluates MEWS prediction metrics. Reads MEWS predictions
    and ground truth from mews_preds.csv
    """
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

def mews_get_score_from_images(data, stats, feature_id, bounds):
    """
    Computes MEWS scores for each sample in data,
    for the row specified by feature_id.
    Returns the score as an int
    """
    # Get the normalized data from the rows we want directly from the image
    norm = data[:,:,feature_id,:]

    # Create single-order splines so we can extrapolate 
    # these values back to their original ranges
    spl = get_spl_x_y(feature_id, stats)

    # Do the extrapolation
    reconst = spl(norm)

    scores = np.zeros((reconst.shape[0], common.N_HOURS))
    for sample in range(reconst.shape[0]):
        scores[sample] = mews_get_score_from_bounds(reconst[sample, 0, :], stats, feature_id, bounds)

    return scores

def compute_sofa(patient_visits, stats):
    """
    Computes sofa based on https://www.dascena.com/articles/sirs-sofa-qsofa-and-mews-the-alphabet-soup
    Directly uses the image rows for PaO2, FIO2, Platelets, Bilirubin, Hypotension, GCS, and Creatinine.
    Image rows manually generated from MIMIC-III database.

    Returns all predicted values as Y_pred and corresponding ground truth as Y_true
    """
    """
    Computes sofa based on https://www.dascena.com/articles/sirs-sofa-qsofa-and-mews-the-alphabet-soup
    Directly uses the image rows for PaO2, FIO2, Platelets, Bilirubin, Hypotension, GCS, and Creatinine.
    Image rows manually generated from MIMIC-III database.

    Returns all predicted values as Y_pred and corresponding ground truth as Y_true
    """
    i = 0
    for visit_id in patient_visits:
        visit = patient_visits[visit_id]

        sofa_components = [
            common.SOFA_processed_rows.RESPIRATION,
            common.SOFA_processed_rows.COAGULATION,
            common.SOFA_processed_rows.LIVER,
            # common.SOFA_processed_rows.CARDIOVASCULAR, # Skip until data is available
            # common.SOFA_processed_rows.CNS, # Skip until data is available
            common.SOFA_processed_rows.RENAL,
        ]

        # Compute SOFA score for this patient
        scores = np.zeros((common.N_HOURS))
        for component in sofa_components:
            bounds = sofa_get_bounds_for_component(component, stats)
            row = sofa_translate_row(visit, component)
            scores = scores + sofa_get_score_from_bounds(row, stats, bounds)

        scores = scores.max()

        # SOFA predicts true for mortality if score >= 4
        prediction = int(scores >= 2)

        # Build up path, placing file in appropriate split
        preds_path = os.getenv('CLINICAL_SCORES_DIR')
        split = common.get_split_as_string(i, len(patient_visits))
        preds_path = os.path.join(preds_path, split)

        # Todo: Come up with a way to open in 'w' mode the first time we touch a file in a given run
        with open(os.path.join(preds_path, common.CS_SOFA_PREDS_FILE_NAME), 'a', newline='') as f:
            sofa_writer = writer(f, delimiter=',')

            # Write this line of 'prediction', 'truth' to the appropriate file
            line = [c.strip() for c in f"{prediction}, {visit.hospital_expire_flag}".strip(', ').split(',')]
            sofa_writer.writerow(line)

        i = i + 1

def sofa_translate_row(visit, component):
    if component == common.SOFA_processed_rows.RESPIRATION:
        return visit.sofa[common.SOFA_raw_rows.PAO2] / visit.sofa[common.SOFA_raw_rows.FIO2]
    elif component == common.SOFA_processed_rows.COAGULATION:
        return visit.sofa[common.SOFA_raw_rows.PLATELETS]
    elif component == common.SOFA_processed_rows.LIVER:
        return visit.sofa[common.SOFA_raw_rows.BILIRUBIN]
    elif component == common.SOFA_processed_rows.CARDIOVASCULAR:
        # Skip until data is available
        raise NotImplementedError
    elif component == common.SOFA_processed_rows.CNS:
        # Skip until data is available
        raise NotImplementedError
    elif component == common.SOFA_processed_rows.RENAL:
        return visit.sofa[common.SOFA_raw_rows.CREATININE]
    else:
        raise Exception

def sofa_get_bounds_for_component(component, stats):
    global SOFA_BOUNDS
    if SOFA_BOUNDS is None:
        # SOFA_BOUNDS doesn't exist, let's build it now
        # Note that runtime building is required since we need access to stats
        SOFA_BOUNDS = [
            [   # Respiration
                399, 300, 200, 100,
            ],
            [   # Coagulation
                149, 100, 50, 20
            ],
            [   # Liver
                1.26, 2.0, 6.0, 12.0
            ],
            [   # Cardiovascular - TODO: Set bounds appropriately
                0, 0, 0, 0
            ],
            [   # CNS - TODO: Set bounds appropriately
                14, 12, 9, 5
            ],
            [   # Renal
                1.2, 2.0, 3.5, 5.0
            ],
        ]

    # SOFA_BOUNDS exists, so look up the requested bounds row
    return SOFA_BOUNDS[component]

def sofa_get_score_from_bounds(data, stats, bounds):
    """
    Computes the MEWS score for each row of data given the provided bounds.
    Data has shape [batch, 1, n_hours]
    Returns the score as an int
    """
    rubric = range(4)

    increasing = True if (bounds[1] > bounds[0]) else False

    scores = np.zeros_like(data)

    for hour in range(data.shape[0]):
        scores[hour] = 0

        for i in range(len(bounds)):
            if (increasing and (data[hour] < bounds[i])) or \
                ((not increasing) and (data[hour] > bounds[i])):
                scores[hour] = rubric[i]
                break

    return scores

def evaluate_sofa():
    """
    Evaluates SOFA prediction metrics. Reads SOFA predictions
    and ground truth from sofa_preds.csv
    """
    Y_train_pred = []
    Y_train_true = []
    Y_test_pred = []
    Y_test_true = []
    Y_val_pred = []
    Y_val_true = []

    # Read SOFA prediction and ground truth for all 3 splits
    preds_train_path = os.path.join(os.getenv('CLINICAL_SCORES_DIR'), 'train', common.CS_SOFA_PREDS_FILE_NAME)
    preds_test_path = os.path.join(os.getenv('CLINICAL_SCORES_DIR'), 'test', common.CS_SOFA_PREDS_FILE_NAME)
    preds_val_path = os.path.join(os.getenv('CLINICAL_SCORES_DIR'), 'val', common.CS_SOFA_PREDS_FILE_NAME)

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
    print("\nSOFA Scores from train split:")
    common.evaluate_predictions(Y_train_true, Y_train_pred, score=Y_train_pred)
    print("\nSOFA Scores from test split:")
    common.evaluate_predictions(Y_test_true, Y_test_pred, score=Y_test_pred)
    print("\nSOFA Scores from val split:")
    common.evaluate_predictions(Y_val_true, Y_val_pred, score=Y_val_pred)

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
    evaluate_sofa()