# Use this file to store common constants and classes to be used throughout this repo.

from enum import Enum, IntEnum
import numpy as np
import pandas as pd
import os
import datetime
import torch
from torch.utils.data import Dataset
from torchvision.io import read_image
from csv import writer
from sklearn.metrics import accuracy_score, roc_auc_score, precision_recall_fscore_support

# Globally define device as CUDA or CPU. Flip FORCE_CPU to True if you want precision over speed.
FORCE_CPU = False
device = torch.device("cuda:0" if (torch.cuda.is_available() and not FORCE_CPU) else "cpu")

# Global switch to force all models to use GLOBAL_CLASS_WEIGHT_RATIO instead of their tuned one
FORCE_CLASS_WEIGHT = False
CLASS_WEIGHT_RATIO = 30.0

# Default number of epochs. Can be overriden in calls to train_<model>
N_EPOCH = 20

# Special patient ID where we hide the itemid to rowid mappings
MAPPING_PATIENT_ID = 0

# Batch size for number of input csv rows to parse before dumping images and deleting runtime image representations
CSV_PARSER_BATCH_SIZE = 10000000

# Constants as specified in the paper
N_HOURS = 48
N_COLS = N_HOURS
N_ROWS = 150

# Normalization output range. Selected as [0,255] for openCV compatibility
NORM_OUT_MIN = 0
NORM_OUT_MAX = 255

# Annotiations file name
ANNOTATIONS_FILE_NAME = 'labels.csv'

# Use to select Normalization Method globally
class Norm_method(Enum):
    MINMAX = 1
    CUSTOM = 3
NORM_METHOD = Norm_method.MINMAX

# Used for indexing columns by name in stats
class Stats_col(IntEnum):
    VAR_TYPE = 0
    VAL_NUM = 1
    VAL_MIN = 2
    VAL_MAX = 3
    VAL_DEFAULT = 4
    N_COLS = 5

class Input_event_col(IntEnum):
    PATIENT_ID = 0
    VISIT_ID = 1
    EVENT_ID = 2
    HOUR = 3
    VAR_TYPE = 4
    VAL_NUM = 5
    VAL_MIN = 6
    VAL_MAX = 7
    REF_MIN = 8
    REF_MAX = 9
    VAL_DEFAULT = 10
    DIED = 11
    N_COLS = 12

class Var_type(IntEnum):
    BINARY = 0
    CONTINUOUS = 1
    CONTINUOUS_WITH_REF = 2

# Class that defines image dataset. Adapted from https://pytorch.org/tutorials/beginner/basics/data_tutorial.html
class CustomImageDataset(Dataset):
    def __init__(self, annotations_file, img_dir, transform=None, target_transform=None):
        self.img_labels = pd.read_csv(annotations_file)
        self.img_dir = img_dir
        self.transform = transform
        self.target_transform = target_transform

    def __len__(self):
        return len(self.img_labels)

    def __getitem__(self, idx):
        img_path = os.path.join(self.img_dir, self.img_labels.iloc[idx, 0])
        image = read_image(img_path).float()[0].unsqueeze(0) / 255.0
        label = self.img_labels.iloc[idx, 1]
        if self.transform:
            image = self.transform(image)
        if self.target_transform:
            label = self.target_transform(label)
        return image, label

def load_data(batch_size = 128, data_path: str = os.getenv('IMAGES_DIR')):
    '''
    input
     folder: str, 'train', 'val', or 'test'
    output
     number_normal: number of normal samples in the given folder
     number_pneumonia: number of pneumonia samples in the given folder
    '''
    trainDataset = CustomImageDataset(os.path.join(data_path, os.path.join(data_path, 'train', ANNOTATIONS_FILE_NAME)), os.path.join(data_path, 'train'))
    testDataset = CustomImageDataset(os.path.join(data_path, os.path.join(data_path, 'test', ANNOTATIONS_FILE_NAME)), os.path.join(data_path, 'test'))
    valDataset = CustomImageDataset(os.path.join(data_path, os.path.join(data_path, 'val', ANNOTATIONS_FILE_NAME)), os.path.join(data_path, 'val'))

    train_loader = torch.utils.data.DataLoader(trainDataset, batch_size=batch_size, shuffle=False)
    test_loader = torch.utils.data.DataLoader(testDataset, batch_size=batch_size, shuffle=False)
    val_loader = torch.utils.data.DataLoader(valDataset, batch_size=batch_size, shuffle=False)

    return train_loader, test_loader, val_loader

def normalize(
    stats: np.ndarray, valuenum: float, ref_min: float, ref_max: float, 
    feature_id: int, var_type: int, method: Norm_method, item_id = None
    ) -> float:
    """
    Normalizes valuenum using the specified normalization method.
    MINMAX linearly interpolates the value within NORM_OUT_MIN and NORM_OUT_MAX.
    CUSTOM uses medical knowledge to assign a value 
    between NORM_OUT_MIN and NORM_OUT_MAX where higher is healthier.
    For more info see the paper.
    """
    assert method in Norm_method

    if item_id is not None:
        valuenum = apply_specific_transforms(valuenum, item_id)

    val_normalized = None

    if (method == Norm_method.MINMAX):
        min = stats[feature_id][Stats_col.VAL_MIN]
        max = stats[feature_id][Stats_col.VAL_MAX]

        if var_type == Var_type.BINARY:
            val_normalized = valuenum
        elif var_type == Var_type.CONTINUOUS:
            val_normalized = np.interp(valuenum, [min, max], [NORM_OUT_MIN, NORM_OUT_MAX])
        elif var_type == Var_type.CONTINUOUS_WITH_REF:
            if valuenum < ref_min:
                val_normalized = np.interp(valuenum, [min, ref_min], [NORM_OUT_MIN, NORM_OUT_MAX])
            elif valuenum > ref_max:
                val_normalized = np.interp(valuenum, [ref_max, max], [NORM_OUT_MAX, NORM_OUT_MIN])
            else:
                val_normalized = NORM_OUT_MAX

        return val_normalized

    elif method == Norm_method.CUSTOM:
        raise NotImplementedError

def apply_specific_transforms(valuenum: float, itemid: int) -> float:
    """
    Applies specific transforms based on medical data associated 
    with given itemids. Configured based on clinical_variables.ods.
    """
    # TODO: Handle any of these that need it
    # 0 = patient age, continuous
    # 1 = sex, binary (0=male, 1=female/other)
    # 2 = race/ethnicity, binary (0=black, 1=other)
    # 3 = prior cardiac arrest history, binary.  Currently only showing cardiac arrest experienced in the ICU.  Cardiac arrest from prior visits or in the main hospital is a huge task to track down.
    # 4 = prior admissions in past 90 days, binary
    # 5 = hour of day, continuous.  NOTE: this one needs special handling as the hour represents the hour of day in military time at time of admission.  This value must be incremented across the entire timeline by the hour, and rewind to 0 if hour = 24.  range = [0...23] but must be normalized to [0...1].
    # 6 = location within hospital, continuous with ref range.  In the paper, this variable indicates where the patient was located within the hospital (ICU vs. Emergency room, vs. ...).  However, the hospital location in the mimic data doesn't carry the same meaning as all the labels I could find more or less mixed/matched location with purpose for admission to the hospital making this task nearly impossible.  Therefore, I converted this variable to a health care urgency rating with 0 meaning normal and 9 meaning dire emergency.  The ratings are pulled directly from the admissions table. 

    return valuenum


def dump_outputs(y_pred, y_true):
    """
    Generates a csv for quick viewing of predictions vs ground truth.
    """
    datetime_str = datetime.datetime.now().strftime("%Y%m%d%H%M")
    with open(os.path.join(os.getenv('DATA_DIR'), f'output_{datetime_str}.csv'), 'a', newline='') as f:
        out_writer = writer(f, delimiter=',')

        for i in range(y_pred.shape[0]):
            line = [c.strip() for c in f"{y_pred[i]}, {y_true[i]}".strip(', ').split(',')]
            out_writer.writerow(line)

def evaluate_predictions(truth, preds, score=None, average='binary'):
    # Evaluate the scores' predictions against the ground truth
    acc = accuracy_score(truth, preds)
    p, r, f, _ = precision_recall_fscore_support(truth, preds, average=average)

    if score is not None:
        auc = roc_auc_score(truth, score)

    print(("Accuracy: " + str(acc)))
    if score is not None:
        print(("AUC: " + str(auc)))
    print(f"Precision {p}")
    print(f"Recall {r}")
    print(f"FScore {f}")
