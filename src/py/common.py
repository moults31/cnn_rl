# Use this file to store common constants and classes to be used throughout this repo.

from enum import Enum, IntEnum
from pickle import TRUE
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
device = torch.device( "cuda:0" if (torch.cuda.is_available() and not FORCE_CPU) else "cpu" )

# Global switch to force all models to use GLOBAL_CLASS_WEIGHT_RATIO instead of their tuned one
FORCE_CLASS_WEIGHT = False
CLASS_WEIGHT_RATIO = 30.0

# Default number of epochs. Can be overriden in calls to train_<model>
N_EPOCH = 20

# Option to evaluate and print metrics on every training epoch (takes longer but gives more info)
EVAL_EVERY_EPOCH = True

# Special patient ID where we hide the itemid to rowid mappings
MAPPING_PATIENT_ID = 0

# Optional forced seed for split generation
USE_SPLITS_SEED = True
SPLITS_SEED = 0

# Option to do early stopping during training
# Note: requires EVAL_EVERY_EPOCH == True, ignored otherwise
DO_EARLY_STOPPING = False

# Target AUCs to trigger early stopping for each model
TARGET_AUC_CNN = 0.87
TARGET_AUC_RNN = 0.89
TARGET_AUC_INCEPTION = 0.90
TARGET_AUC_CNN_RL = 0.91

# Batch size for number of input csv rows to parse before dumping images and deleting runtime image representations
CSV_PARSER_BATCH_SIZE = 10000000

# Set range of patients to process images for. Set CSV_PARSER_PATIENTID_DO_LIMIT to False to uncap limit.
CSV_PARSER_PATIENTID_DO_LIMIT = True
CSV_PARSER_PATIENTID_MIN      = 10000019
CSV_PARSER_PATIENTID_MAX      = 19999987

# Prediction thresholds for clinical scores
MEWS_THRESHOLD = 2.9
SOFA_SCORE_THRESHOLD = 5.2
SOFA_EST_THRESHOLD = 10.0

# Data split percentages (train will take up remainder)
TEST_SPLIT_PCT = 0.2
VAL_SPLIT_PCT  = 0.3

# Constants as specified in the paper
N_HOURS = 48
N_COLS  = N_HOURS
N_ROWS  = 120

# Normalization output range. Selected as [0,255] for openCV compatibility
NORM_OUT_MIN = 0
NORM_OUT_MAX = 255

# Annotiations file name
ANNOTATIONS_FILE_NAME = 'labels.csv'

# Clinical scores file names
CS_MEWS_PREDS_FILE_NAME = 'mews_preds.csv'
CS_SOFA_PREDS_FILE_NAME = 'sofa_preds.csv'

# Use to select Normalization Method globally
class Norm_method( Enum ):
    MINMAX = 1
    CUSTOM = 2
    REFMINMAX = 3
NORM_METHOD = Norm_method.MINMAX

# Used for indexing braden items in patient_visit
braden_item2row = {
    224054: 0,     # Braden Sensory Perception
    224055: 1,     # Braden Moisture
    224056: 2,     # Braden Activity
    224057: 3,     # Braden Mobility
    224058: 4,     # Braden Nutrition
    224059: 5,     # Braden Friction/Shear
}
BRADEN_ROWID = 98

# Used for indexing morse items in patient_visit
morse_item2row = {
    227341: 0,     # Morse, History of falling (within 3 mnths)
    227342: 1,     # Morse, Secondary diagnosis
    227343: 2,     # Morse, Ambulatory aid
    227344: 3,     # Morse, IV/Saline lock
    227345: 4,     # Morse, Gait/Transferring
    227346: 5,     # Morse, Mental status
}
MORSE_ROWID = 107

# Used for indexing columns by name in stats
class Special_itemids(IntEnum):
    ADMIT_HOUR  = 0   # hour of day, continuous.  NOTE: Needs special handling as the hour 
                      # represents the hour of day in military time at time of admission.  
                      # This value must be incremented across the entire timeline by the hour, 
                      # and rewind to 0 if hour = 24.  range = [0...23] but must be normalized to [0...1].

# Header info for MEWS csv
class MEWS_rows(IntEnum):
    PATIENT_ID      = 0
    VISIT_ID        = 1
    MEWS_SCORE      = 2
    MEWS_WARNING    = 3
    DIED            = 4

class SOFA_rows(IntEnum):
    PATIENT_ID      = 0
    VISIT_ID        = 1
    SOFA_SCORE      = 2
    EST_MORTALITY   = 3
    DIED            = 4

# Used for indexing columns by name in stats
class Stats_col( IntEnum ):
    VAR_TYPE    = 0
    VAL_NUM     = 1
    VAL_MIN     = 2
    VAL_MAX     = 3
    REF_MIN     = 4
    REF_MAX     = 5
    VAL_DEFAULT = 6
    N_COLS      = 7

class Input_event_col( IntEnum ):
    PATIENT_ID  = 0
    VISIT_ID    = 1
    EVENT_ID    = 2
    HOUR        = 3
    VAR_TYPE    = 4
    VAL_NUM     = 5
    VAL_MIN     = 6
    VAL_MAX     = 7
    REF_MIN     = 8
    REF_MAX     = 9
    VAL_DEFAULT = 10
    DIED        = 11
    N_COLS      = 12

class Var_type( IntEnum ):
    BINARY               = 0
    CONTINUOUS           = 1
    CONTINUOUS_WITH_REF  = 2
    CONTINUOUS_INCREMENT = 3
    BINARY_POINT         = 4

# Class that defines image dataset. Adapted from https://pytorch.org/tutorials/beginner/basics/data_tutorial.html
class CustomImageDataset( Dataset ):
    def __init__( self, annotations_file, img_dir, transform=None, target_transform=None ):
        self.img_labels       = pd.read_csv(annotations_file)
        self.img_dir          = img_dir
        self.transform        = transform
        self.target_transform = target_transform

    def __len__( self ):
        return len( self.img_labels )

    def __getitem__( self, idx ):
        img_path = os.path.join( self.img_dir, self.img_labels.iloc[idx, 0] )
        image    = read_image( img_path ).float()[0].unsqueeze(0) / 255.0
        label    = self.img_labels.iloc[idx, 1]
        if self.transform:
            image = self.transform( image )
        if self.target_transform:
            label = self.target_transform( label )
        return image, label

def load_data( batch_size = 128, data_path: str = os.getenv('IMAGES_DIR') ):
    '''
    input
        folder: str, 'train', 'val', or 'test'
    output
           number_normal: number of normal samples in the given folder
        number_pneumonia: number of pneumonia samples in the given folder
    '''
    trainDataset = CustomImageDataset( os.path.join( data_path, os.path.join( data_path, 'train', ANNOTATIONS_FILE_NAME ) ), os.path.join( data_path, 'train' ) )
    testDataset  = CustomImageDataset( os.path.join( data_path, os.path.join( data_path, 'test',  ANNOTATIONS_FILE_NAME ) ), os.path.join( data_path, 'test'  ) )
    valDataset   = CustomImageDataset( os.path.join( data_path, os.path.join( data_path, 'val',   ANNOTATIONS_FILE_NAME ) ), os.path.join( data_path, 'val'   ) )

    train_loader = torch.utils.data.DataLoader( trainDataset, batch_size=batch_size, shuffle=False )
    test_loader  = torch.utils.data.DataLoader( testDataset,  batch_size=batch_size, shuffle=False )
    val_loader   = torch.utils.data.DataLoader( valDataset,   batch_size=batch_size, shuffle=False )

    return train_loader, test_loader, val_loader

def normalize(
        stats: np.ndarray, valuenum: float, ref_min: float, ref_max: float, feature_id: int, var_type: int, method: Norm_method, item_id = None
    ) -> float:
    """
    Normalizes valuenum using the specified normalization method.
    MINMAX linearly interpolates the value within NORM_OUT_MIN and NORM_OUT_MAX.
    CUSTOM uses medical knowledge to assign a value 
    between NORM_OUT_MIN and NORM_OUT_MAX where higher is healthier.
    For more info see the paper.
    """
    assert method in Norm_method

    val_normalized = None

    min = stats[feature_id][Stats_col.VAL_MIN]
    max = stats[feature_id][Stats_col.VAL_MAX]

    # Handle common variable types
    if var_type == Var_type.BINARY:
        val_normalized = np.interp(valuenum, [0.0, 1.0], [NORM_OUT_MIN, NORM_OUT_MAX])

    elif var_type == Var_type.CONTINUOUS_INCREMENT:
        val_normalized = np.interp( valuenum, [min, max], [NORM_OUT_MIN, NORM_OUT_MAX] )
            
    elif var_type == Var_type.BINARY_POINT:
        val_normalized = np.interp( valuenum, [0.0, 1.0], [NORM_OUT_MIN, NORM_OUT_MAX] )
    else:
        assert ((var_type == Var_type.CONTINUOUS) or (var_type == Var_type.CONTINUOUS_WITH_REF))

    # Handle scheme-specific variable types
    if ( method == Norm_method.CUSTOM ):
        if var_type == Var_type.CONTINUOUS:
            val_normalized = np.interp(valuenum, [min, max], [NORM_OUT_MIN, NORM_OUT_MAX])
        elif var_type == Var_type.CONTINUOUS_WITH_REF:
            if valuenum < ref_min:
                val_normalized = np.interp(valuenum, [min, ref_min], [NORM_OUT_MAX, NORM_OUT_MIN])
            elif valuenum > ref_max:
                val_normalized = np.interp(valuenum, [ref_max, max], [NORM_OUT_MIN, NORM_OUT_MAX])
            else:
                val_normalized = NORM_OUT_MIN
    elif ( method == Norm_method.MINMAX ):
        if (var_type == Var_type.CONTINUOUS) or (var_type == Var_type.CONTINUOUS_WITH_REF):
            val_normalized = np.interp(valuenum, [min, max], [NORM_OUT_MIN, NORM_OUT_MAX])
    elif ( method == Norm_method.REFMINMAX ):
        if (var_type == Var_type.CONTINUOUS) or (var_type == Var_type.CONTINUOUS_WITH_REF):
            val_normalized = np.interp(valuenum, [ref_min, ref_max], [NORM_OUT_MIN, NORM_OUT_MAX])

    else:
        raise NotImplementedError

    return val_normalized


def dump_outputs(y_pred, y_true):
    """
    Generates a csv for quick viewing of predictions vs ground truth.
    """
    datetime_str = datetime.datetime.now().strftime( "%Y%m%d%H%M" )
    with open( os.path.join( os.getenv('DATA_DIR'), f'output_{datetime_str}.csv'), 'a', newline='') as f:
        out_writer = writer( f, delimiter=',' )

        for i in range( y_pred.shape[0] ):
            line = [c.strip() for c in f"{y_pred[i]}, {y_true[i]}".strip(', ').split(',')]
            out_writer.writerow(line)

def evaluate_predictions( truth, preds, score=None, average='binary' ):

    # Evaluate the scores' predictions against the ground truth
    acc        = accuracy_score( truth, preds )
    p, r, f, _ = precision_recall_fscore_support( truth, preds, average=average )

    if score is not None:
        auc = roc_auc_score( truth, score )

    """
    print( ("Accuracy: " + str(acc)) )
    if score is not None:
        print( ("AUC: " + str(auc)) )
    print( f"Precision {p}")
    print( f"Recall {r}"   )
    print( f"FScore {f}"   )
    """

    if score is not None:
        return auc, acc, p, r, f
    else:
        return 0.0, acc, p, r, f
        
def print_output_header():

    print( "\nepoch  Time  loss             Accuracy    AUC         Precision   Recall      F1-Score       Accuracy    AUC         Precision   Recall      F1-Score" )
        
def print_epoch_output( epoch, etime, loss, acc, auc, p, r, f, acc2, auc2, p2, r2, f2 ):

    print( "\rep %02d: %.02f %.12f   %.9f %.9f %.9f %.9f %.9f    %.9f %.9f %.9f %.9f %.9f" % ( epoch, etime, loss, acc, auc, p, r, f, acc2, auc2, p2, r2, f2 ) )
    #output = "\rep_{0}: {11:.2f} {12:.12f} | {1:.12f} {2:.12f} {3:.12f} {4:.12f} {5:.12f} | {6:.12f} {7:.12f} {8:.12f} {9:.12f} {10:.12f}"   
    #print( output.format( epoch, acc, auc, p, r, f, acc2, auc2, p2, r2, f2, epoch_time, curr_epoch_loss ) )

def print_scores( label, acc, auc, p, r, f ):

    print( "%8s %-18s %-18s %-18s %-18s %-18s" % ( " ", "Accuracy", "AUC", "Precision", "Recall", "F1-Score" ) )
    print( "%7s: %.16f %.16f %.16f %.16f %.16f" % ( label, acc, auc, p, r, f ) )

def get_split_as_string(i, n):
    test_start_idx = n * ( 1 - VAL_SPLIT_PCT ) * ( 1 - TEST_SPLIT_PCT )
    val_start_idx  = n * ( 1 - VAL_SPLIT_PCT )

    if i >= test_start_idx and i < val_start_idx:
        return 'test'
    elif i >= val_start_idx:
        return 'val'
    else:
        return 'train'
