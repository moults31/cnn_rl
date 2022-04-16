import numpy as np
import common
import os
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from sklearn.metrics import accuracy_score

class StandardCNN(nn.Module):
    def __init__(self):
        # Layer architecture taken from S2 Table in the paper
        super(StandardCNN, self).__init__()
        self.conv1 = nn.Conv2d(3, 32, 4)
        self.conv2 = nn.Conv2d(32, 64, 6)
        self.pool = nn.MaxPool2d(2, 2)
        self.dropout1 = nn.Dropout(0.25)
        self.fc1 = nn.Linear(90880, 2)
        self.dropout2 = nn.Dropout(0.5)

    def forward(self, x):
        x = F.relu(self.conv1(x))
        x = F.relu(self.conv2(x))
        x = self.pool(x)
        x = self.dropout1(x)
        x = torch.flatten(x, 1) # flatten all dimensions except batch
        x = self.fc1(x)
        x = self.dropout2(x)
        x = F.softmax(x)
        return x

def main():
    """
    Main function.
    Creates a model, trains it, and evaluates it against test set and val set.
    """
    train_loader, test_loader, val_loader = load_data()
    model = StandardCNN()
    model = train_cnn(model, train_loader)

    y_pred_test, y_pred_val, y_test, y_val = eval_model(model, test_loader, val_loader)
    acc_test = accuracy_score(y_test, y_pred_test)
    acc_val = accuracy_score(y_val, y_pred_val)
    print(("Test Accuracy: " + str(acc_test)))
    print(("Validation Accuracy: " + str(acc_val)))

def eval_model(model, test_loader, val_loader):
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
    Y_pred_test = []
    Y_pred_val = []
    Y_test = []
    Y_val = []
    for data, target in test_loader:
        outputs = model(data)
        _, predictions = torch.max(outputs, 1)

        Y_pred_test.append(predictions)
        Y_test.append(target)

    for data, target in val_loader:
        outputs = model(data)
        _, predictions = torch.max(outputs, 1)

        Y_pred_val.append(predictions)
        Y_val.append(target)

    Y_pred_test = np.concatenate(Y_pred_test, axis=0)
    Y_pred_val = np.concatenate(Y_pred_val, axis=0)
    Y_test = np.concatenate(Y_test, axis=0)
    Y_val = np.concatenate(Y_val, axis=0)

    return Y_pred_test, Y_pred_val, Y_test, Y_val

def train_cnn(model, train_dataloader, n_epoch=2):
    """
    :param model: A CNN model
    :param train_dataloader: the DataLoader of the training data
    :param n_epoch: number of epochs to train
    :return:
        model: trained model
    """
    # Todo: Update these to match the paper
    criterion = torch.nn.modules.loss.CrossEntropyLoss()
    optimizer = torch.optim.SGD(model.parameters(), lr=1e-4)
    model.train() # prep model for training

    for epoch in range(n_epoch):
        curr_epoch_loss = []
        for data, target in train_dataloader:
            # zero the parameter gradients
            optimizer.zero_grad()
            
            # forward + backward + optimize
            outputs = model(data)
            loss = criterion(outputs, target)
            loss.backward()
            optimizer.step()

            curr_epoch_loss.append(loss.cpu().data.numpy())
        print(f"Epoch {epoch}: curr_epoch_loss={np.mean(curr_epoch_loss)}")
    return model

def load_data(data_path: str = os.getenv('IMAGES_DIR')):
    '''
    input
     folder: str, 'train', 'val', or 'test'
    output
     number_normal: number of normal samples in the given folder
     number_pneumonia: number of pneumonia samples in the given folder
    '''
    trainDataset = common.CustomImageDataset(os.path.join(data_path, os.path.join(data_path, 'train', common.ANNOTATIONS_FILE_NAME)), os.path.join(data_path, 'train'))
    testDataset = common.CustomImageDataset(os.path.join(data_path, os.path.join(data_path, 'test', common.ANNOTATIONS_FILE_NAME)), os.path.join(data_path, 'test'))
    valDataset = common.CustomImageDataset(os.path.join(data_path, os.path.join(data_path, 'val', common.ANNOTATIONS_FILE_NAME)), os.path.join(data_path, 'val'))

    train_loader = torch.utils.data.DataLoader(trainDataset, batch_size=128, shuffle=False)
    test_loader = torch.utils.data.DataLoader(testDataset, batch_size=128, shuffle=False)
    val_loader = torch.utils.data.DataLoader(valDataset, batch_size=128, shuffle=False)

    return train_loader, test_loader, val_loader

if __name__ == "__main__":
    """
    Main section for when this file is invoked directly.
    """
    main()