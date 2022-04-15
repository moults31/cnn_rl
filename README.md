# cnn_rl

## Overview
This repo contains the source code for the UIUC CS598 project authored by Matthew Lind and Zachary Moulton. Objective: Reproduce __Combining patient visual timelines with deep
learning to predict mortality__ by Mayampurath et. al.

## Usage
### Setup
```
conda create --name dl4h_22sp python=3.8.12
conda activate dl4h_22sp

pip3 install torch==1.10.0 torchvision==0.11.1 torchaudio==0.10.0 torchtext==0.11.0

export TORCH=1.10.0
export CUDA=cpu

pip install torch-scatter -f https://data.pyg.org/whl/torch-${TORCH}+${CUDA}.html
pip install torch-sparse -f https://data.pyg.org/whl/torch-${TORCH}+${CUDA}.html
pip install torch-geometric
pip install torch-cluster -f https://data.pyg.org/whl/torch-${TORCH}+${CUDA}.html
pip install torch-spline-conv -f https://data.pyg.org/whl/torch-${TORCH}+${CUDA}.html

pip install notebook nltk matplotlib gensim umap-learn

python -m ipykernel install --user --name dl4h_22sp --display-name "dl4h_22sp"
```