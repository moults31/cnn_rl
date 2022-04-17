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

# Globally define device as CUDA or CPU. Flip FORCE_CPU to True if you want precision over speed.
FORCE_CPU = False
device = torch.device("cuda:0" if (torch.cuda.is_available() and not FORCE_CPU) else "cpu")

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
    SOFTMINMAX = 2
    CUSTOM = 3
NORM_METHOD = Norm_method.SOFTMINMAX

# Used for indexing columns by name in stats
class Stats_col(IntEnum):
    MIN = 0
    MAX = 1
    SOFTMIN = 2
    SOFTMAX = 3
    NORMLOW = 4
    NORMHI = 5
    MEAN = 6
    STDDEV = 7
    MEDIAN = 8
    N = 9
    N_COLS = 10

# Macro to use either true min/max or soft min/max globally, based on norm_method
STATSCOL_MAYBESOFTMIN = Stats_col.SOFTMIN if (NORM_METHOD == Norm_method.SOFTMINMAX) else Stats_col.MIN
STATSCOL_MAYBESOFTMAX = Stats_col.SOFTMAX if (NORM_METHOD == Norm_method.SOFTMINMAX) else Stats_col.MAX

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

def normalize(valuenum: float, feature_id: int, method: Norm_method, item_id = None) -> float:
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

    if (method == Norm_method.MINMAX) or (method == Norm_method.SOFTMINMAX):
        min = stats[feature_id][STATSCOL_MAYBESOFTMIN]
        max = stats[feature_id][STATSCOL_MAYBESOFTMAX]
        return np.interp(valuenum, [min, max], [NORM_OUT_MIN, NORM_OUT_MAX])
    elif method == Norm_method.CUSTOM:
        raise NotImplementedError

def apply_specific_transforms(valuenum: float, itemid: str) -> float:
    """
    Applies specific transforms based on medical data associated 
    with given itemids. Configured based on clinical_variables.ods.
    """
    if itemid in [678,679,223761]:
        # F to C
        valuenum = (valuenum - 32) / 1.8

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

# Mapping from itemid to unique feature id.
# itemids come from MIMIC-III. Feature ids are used to amalgamate
# itemids with same practical meaning. Feature id is used directly as row index in output image.
item2feature = {
    50862: 25,
    50863: 28,
    50868: 17,
    50878: 27,
    50882: 16,
    51006: 20,
    -1: 21,
    50893: 19,
    50902: 36,
    50809: 18,
    51222: 30,
    51237: 37,
    51484: 35,
    50813: 32,
    50956: 38,
    51250: 39,
    50818: 40,
    50821: 41,
    51275: 42,
    50820: 34,
    50970: 23,
    51265: 31,
    50971: 15,
    51277: 43,
    50983: 14,
    50885: 26,
    50976: 24,
    51002: 33,
    51003: 33,
    51301: 29,
    676: 6,
    677: 6,
    8537: 6,
    223762: 6,
    678: 6,
    679: 6,
    223761: 6,
    3420: 12,
    3421: 12,
    3422: 12,
    211: 7,
    220045: 7,
    618: 8,
    619: 8,
    220210: 8,
    224688: 8,
    224689: 8,
    224690: 8,
    51: 9,
    442: 9,
    455: 9,
    6701: 9,
    224167: 9,
    225309: 9,
    8368: 10,
    8440: 10,
    8441: 10,
    8555: 10,
    224643: 10,
    225310: 10,
    220277: 11,
}

# Autogenerated by parse_clinical_variables.py
stats = np.array([
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [-3.0,376.5,25.0,42.0,36.1,37.2,34.8954,4.4653,36.4444,1943452.0,],
    [-88.0,9999999.0,25.0,230.0,60.0,100.0,102.6625,3548.7627,92.0,7941588.0,],
    [-1.0,2355555.0,5.0,50.0,12.0,20.0,19.7383,863.6341,19.0,7439791.0,],
    [0.0,6918.0,60.0,200.0,115.0,120.0,121.1339,25.5172,119.0,3770216.0,],
    [-13.0,58196.0,30.0,140.0,75.0,80.0,59.1164,33.7926,58.0,3767658.0,],
    [0.0,6363333.0,60.0,100.0,95.0,100.0,100.9225,4435.5406,97.0,2671816.0,],
    [11.0,100.0,0.0,50.0,20.0,22.0,39.9684,28.8031,26.0,1144119.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [35.0,189.0,125.0,160.0,135.0,145.0,138.5551,4.9481,139.0,808328.0,],
    [0.8,27.5,2.5,6.0,3.5,5.3,4.1544,0.6562,4.1,845365.0,],
    [2.0,90.0,2.0,90.0,20.0,29.0,25.4115,4.8942,25.0,780439.0,],
    [-21.0,118.0,0.0,60.0,12.0,20.0,13.882,3.7675,13.0,769803.0,],
    [-251.0,3070.0,0.0,200.0,65.0,125.0,139.2986,58.1087,129.0,196596.0,],
    [0.0,47.7,0.0,20.0,8.6,10.3,8.5089,0.842,8.5,591896.0,],
    [0.0,290.0,0.0,200.0,7.0,25.0,29.2564,22.9176,22.0,791793.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,58.0,1.0,10.0,2.75,4.5,3.5985,1.32052,3.4,590458.0,],
    [0.2,56.0,0.0,56.0,6.0,8.3,6.5656,1.2108,6.7,11931.0,],
    [0.9,6.9,0.9,6.0,2.2342,3.1651,3.178,0.757,3.15,146652.0,],
    [0.0,82.8,0.0,2.5,0.2,1.2,3.3405,6.1149,0.9,238234.0,],
    [0.0,36400.0,0.0,1750.0,14.0,59.0,151.149,732.108,36.0,219437.0,],
    [0.0,4695.0,0.0,1200.0,45.0,150.0,168.286,197.4186,107.0,207837.0,],
    [0.0,846.7,0.0,40.0,4.0,11.0,10.5041,9.006,9.1,752813.0,],
    [0.0,25.5,0.0,25.5,12.0,18.0,10.56,1.95733,10.3,752277.0,],
    [4.0,4504.0,50.0,1000.0,150.0,425.0,239.31904,150.3102,215.0,778163.0,],
    [0.0,36.0,0.0,7.0,0.5,2.2,2.6028,2.5472,1.8,187025.0,],
    [0.0,575.0,0.0,0.45,0.0,0.04,1.1443,4.3426,0.13,68111.0,],
    [0.0,7.99,6.5,8.0,7.35,7.45,7.3793,0.08711,7.39,530657.0,],
    [4.0,150.0,0.0,60.0,0.0,15.0,45.3794,47.816,15.0,10618.0,],
    [22.0,155.0,60.0,145.0,98.0,110.0,103.4792,6.11369,103.0,795412.0,],
    [0.0,112.3,0.0,5.0,0.8,1.5,1.6621,1.3351,1.3,470853.0,],
    [0.0,1210000.0,0.0,120.0,13.0,60.0,143.02789,4843.0091,37.0,65361.0,],
    [0.0,147.0,60.0,140.0,80.0,100.0,90.2649,6.9878,90.0,747537.0,],
    [0.0,247.0,20.0,70.0,38.0,45.0,42.7367,11.3889,41.0,490504.0,],
    [0.0,1914.0,50.0,150.0,75.0,100.0,136.7356,92.1099,109.0,490522.0,],
    [0.0,193.3,15.0,150.0,60.0,70.0,44.1984,25.7033,34.1,473449.0,],
    [0.0,36.4,10.0,20.0,11.75,16.0,15.7992,2.3561,15.3,746408.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
    [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,],
])