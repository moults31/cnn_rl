# cnn_rl

## Overview
This repo contains the source code for the UIUC CS598 project authored by Matthew Lind and Zachary Moulton. Objective: Reproduce __Combining patient visual timelines with deep
learning to predict mortality__ by Mayampurath et. al. which can be found at https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0220640

The results generated by this implementation in attempting to reproduce the paper using the MIMIC-IV dataset is shown in the following table.

| Model        | AUC  | 95% CI- | 95% CI+ |
|--------------|------|---------|---------|
| SOFA         | 0.67 |         |         |
| MEWS         | 0.68 |         |         |
| Standard-CNN | 0.87 | 0.86    | 0.88    |
| RNN          | 0.88 | 0.88    | 0.89    |
| Deep-CNN     | 0.90 |         |         |
| CNN-RL       | 0.75 | 0.57    | 0.93    |

## Usage and Dependencies
### Setup
Note that this repo is only tested on Ubuntu 20.04 or newer. CUDA toolkit version is GPU-specific so please install the appropriate one for your hardware.
This also applies to Pytorch version which relies on you having installed the one that supports YOUR CUDA version.
For more info: https://developer.nvidia.com/cuda-downloads

#### One-time setup:

```
sudo apt install nvidia-cuda-toolkit

conda create --name dl4h_22sp python=3.8.12
conda activate dl4h_22sp

pip3 install torch==1.10.2+cu113 torchvision torchaudio torchtext

export TORCH=1.10.0
export CUDA=cu113

pip install torch-scatter -f https://data.pyg.org/whl/torch-${TORCH}+${CUDA}.html
pip install torch-sparse -f https://data.pyg.org/whl/torch-${TORCH}+${CUDA}.html
pip install torch-geometric
pip install torch-cluster -f https://data.pyg.org/whl/torch-${TORCH}+${CUDA}.html
pip install torch-spline-conv -f https://data.pyg.org/whl/torch-${TORCH}+${CUDA}.html

pip install notebook nltk matplotlib gensim umap-learn opencv-python scikit-learn

cd <path/to/cnn_rl>
mkdir images
mkdir data
```

##### Required data download links:
Note that these links require physionet access approval:
https://physionet.org/content/mimiciv/0.4/
https://physionet.org/content/mimic-iv-ed/1.0/

Please follow this tutorial to install the MIMIC-IV database once it is downloaded:
https://mimic.mit.edu/docs/iv/

#### Environment loading on every new run:
```
cd path/to/cnn_rl
conda activate dl4h_22sp
source ./env.sh
```

### Running
#### End-to-End Run
Step 1: Generate patient data from MIMIC-IV SQL database as CSV. Open a SQL-compatible GUI with a connection to your MIMIC-IV database. Then, run `set_cohort_icu_ed.sql` followed by `export_patient_data.sql`. Finally, use the GUI to export the result as a CSV and place it in `<path/to/cnn_rl>/data`

Step 2: Generate MEWS/SOFA data from MIMIC-IV SQL database as CSV. In the same GUI as Step 1, run `mews_score.sql` and export the result as CSV and place it in `<path/to/cnn_rl>/data`. Then, repeat with `sofa_score.sql`.

Step 3: Compute MEWS and SOFA scores
```
cd src/py
python ./mews.py ../../data/<exported_mews_data>.csv
python ./sofa.py ../../data/<exported_sofa_data>.csv
```

Step 4: Parse patient data CSV to images
```
python ./csv_to_images.py ../../data/<exported_data>.csv <arbitrary_cohort_name>
```

Step 5: Shuffle cohort and create train, test, val splits (optionally limiting cohort size)
```
python ./shuffle.py <arbitrary_cohort_name> <shuffled_cohort_name> <random_shuffle_seed> <optional_size_limit>
```

Step 6: Train and evaluate models! Pick any or all of the following:
```
# Train and evaluate all models with the given parameters
python ./model_runner.py -c <arbitrary_cohort_name>/<shuffled_cohort_name> -w <class_weight_ratio> -l <learning_rate> -n <n_epochs>

# Train and evaluate specific models with the given parameters
python ./cnn.py -c <arbitrary_cohort_name>/<shuffled_cohort_name> -w <class_weight_ratio> -l <learning_rate> -n <n_epochs>
python ./rnn.py -c <arbitrary_cohort_name>/<shuffled_cohort_name> -w <class_weight_ratio> -l <learning_rate> -n <n_epochs>
python ./inceptionv3.py -c <arbitrary_cohort_name>/<shuffled_cohort_name> -w <class_weight_ratio> -l <learning_rate> -n <n_epochs>
python ./cnn_rl.py -c <arbitrary_cohort_name>/<shuffled_cohort_name> -w <class_weight_ratio> -l <learning_rate> -n <n_epochs>
```

#### Deep learning Run
Once Step 5 is complete, you can repeat Step 6 as many times as you want on that shuffle without needing to redo any earlier steps.

#### Creating new shuffles
It can be helpful to repeat step 5 multiple times from the same original <arbitrary_cohort_name> to many <shuffled_cohort_name>s in order to
get different permutations of the cohort using different random seeds, as well as different cohort sizes. Shuffled cohorts are stored as
child directories of the original cohort, so you can create as many as you like and they will persist.

#### Generating new image sets
In general, once you have completed Step 4 and created <arbitrary cohort name> you don't need to do it again. An exception to that rule is
when updates are made to any of the SQL scripts. In that event, you can run all steps again starting with Step 1, coming up with a new <alternate_arbitrary_cohort_name>.
