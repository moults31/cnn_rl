# cnn_rl

## Overview
This repo contains the source code for the UIUC CS598 project authored by Matthew Lind and Zachary Moulton. Objective: Reproduce __Combining patient visual timelines with deep
learning to predict mortality__ by Mayampurath et. al.

## Usage
### Setup
Note that this repo is only tested on Ubuntu 20.04 or newer. For the CUDA environment variable, run `nvcc -V` to get the CUDA version that you have installed, and modify `cu113` to match your version.
#### One-time setup:

```
sudo apt install nvidia-cuda-toolkit

conda create --name dl4h_22sp python=3.8.12
conda activate dl4h_22sp

pip3 install torch==1.10.0 torchvision==0.11.1 torchaudio==0.10.0 torchtext==0.11.0

export TORCH=1.10.0
export CUDA=cu113

pip install torch-scatter -f https://data.pyg.org/whl/torch-${TORCH}+${CUDA}.html
pip install torch-sparse -f https://data.pyg.org/whl/torch-${TORCH}+${CUDA}.html
pip install torch-geometric
pip install torch-cluster -f https://data.pyg.org/whl/torch-${TORCH}+${CUDA}.html
pip install torch-spline-conv -f https://data.pyg.org/whl/torch-${TORCH}+${CUDA}.html

pip install notebook nltk matplotlib gensim umap-learn opencv-python scikit-learn
```
#### When running in a new terminal:
```
cd path/to/cnn_rl
conda activate dl4h_22sp
source ./env.sh
```

### Running
#### End-to-End Run
TODO


#### Debug runs
##### csv_to_images.py
`python csv_to_images.py <csv_file>`

##### extract_patients.sql
Paste script into a PostgreSQL compatible GUI client, and then run each numbered section one-at-a-time.
* On subsequent runs, skip the `drop` lines at the top
* To use a subset of the population for faster debug runs, modify the body of the `l.subject_id in (` block.

##### cnn.py
Make sure that you have images generated, and then:
`python cnn.py`
