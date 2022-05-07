import numpy as np
import common
import os
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import time
from sklearn.metrics import accuracy_score, roc_auc_score

class StandardCNN( nn.Module ):
    def __init__( self ):
        # Layer architecture taken from S2 Table in the paper
        super( StandardCNN, self ).__init__()
        self.conv1    = nn.Conv2d( in_channels=1,  out_channels=32, kernel_size=(120,1) )
        self.conv2    = nn.Conv2d( in_channels=32, out_channels=32, kernel_size=(1,1) )
        self.pool     = nn.MaxPool2d( kernel_size=(1, 3) )
        self.dropout1 = nn.Dropout(p=0.25)
        self.fc1      = nn.Linear( in_features=512, out_features=2 )
        self.dropout2 = nn.Dropout( 0.5 )

    def forward( self, x ):
        x = F.relu( self.conv1(x) )
        x = F.relu( self.conv2(x) )       
        x = self.pool(x)
        x = self.dropout1(x)
        x = torch.flatten(x, 1)    # flatten all dimensions except batch
        x = self.fc1(x)
        x = self.dropout2(x)
        x = F.softmax( x, dim=1 )
        return x

def main(n_epoch=common.N_EPOCH):
    """
    Main function.
    Creates a model, trains it, and evaluates it against test set and val set.
    """
    print(f"Running on CUDA device: {common.device}")

    # Load images and labels for each split
    train_loader, test_loader, val_loader = common.load_data()

    # Create and train the model
    model = StandardCNN().to(common.device)
    model = train_cnn(model, train_loader, n_epoch)

    # Evaluate the model's predictions against the ground truth
    y_score_test, y_pred_test, y_test = eval_model(model, test_loader)
    y_score_val, y_pred_val, y_val = eval_model(model, val_loader)

    # Evaluate the scores' predictions against the ground truth
    print("\nScores from test split:")
    common.evaluate_predictions(y_test, y_pred_test, score=y_score_test)
    print("\nScores from val split:")
    common.evaluate_predictions(y_val, y_pred_val, score=y_score_val)

    common.dump_outputs(y_pred_val, y_val)

def eval_model(model, dataloader):
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
        data = data.to(common.device)
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

def train_cnn(model, train_dataloader, n_epoch=common.N_EPOCH):
    """
    :param model: A CNN model
    :param train_dataloader: the DataLoader of the training data
    :param n_epoch: number of epochs to train
    :return:
        model: trained model
    """
    # Assign class weights and create 2-class criterion
    # class_weight_ratio = common.CLASS_WEIGHT_RATIO if common.FORCE_CLASS_WEIGHT else 13.78
    class_weight_ratio = common.CLASS_WEIGHT_RATIO if common.FORCE_CLASS_WEIGHT else 30.0
    print(f"Class weight ratio: {class_weight_ratio}")
    weights = [1.0/class_weight_ratio, 1.0-(1.0/class_weight_ratio)]
    class_weights = torch.FloatTensor(weights).to(common.device)
    criterion = torch.nn.modules.loss.CrossEntropyLoss(weight=class_weights)

    # Assign LR=1e-3 taken from the paper
    optimizer = torch.optim.RMSprop(model.parameters(), lr=1e-3)

    model.train() # prep model for training

    train_start_time = time.time()
    for epoch in range(n_epoch):
        print(f"##### EPOCH {epoch} START #####")
        curr_epoch_loss = []
        epoch_start_time = time.time()
        i = 0
        for data, target in train_dataloader:
            # Transfer tensors to GPU
            data, target = data.to(common.device), target.to(common.device)

            # zero the parameter gradients
            optimizer.zero_grad()

            # forward + backward + optimize
            outputs = model(data)
            loss = criterion(outputs, target)
            loss.backward()
            optimizer.step()

            curr_epoch_loss.append(loss.cpu().data.numpy())

            # Print progress indicator
            if (i % 10) == 0:
                print('.', end='', flush=True)
            i = i + 1

        print(f"\nEpoch {epoch}: curr_epoch_loss={np.mean(curr_epoch_loss)}")
        print("Epoch took {:.2f} sec".format(time.time() - epoch_start_time))

        # Optionally make predictions and evaluate between every epoch.
        # Adds a lot of time, but is worth it to get intermediate readouts when training epochs are very slow
        if(common.EVAL_EVERY_EPOCH):
            with torch.no_grad():
                # Put model in eval mode temporarily
                model.eval()

                # Get entire dataloader
                _, test_loader, val_loader = common.load_data()
                # Evaluate the model's predictions against the ground truth
                y_score_test, y_pred_test, y_test = eval_model(model, test_loader)
                y_score_val, y_pred_val, y_val = eval_model(model, val_loader)

                # Evaluate the scores' predictions against the ground truth
                print("\nScores from test split:")
                common.evaluate_predictions(y_test, y_pred_test, score=y_score_test)
                print("\nScores from val split:")
                common.evaluate_predictions(y_val, y_pred_val, score=y_score_val)
            # Put model back in training mode
            model.train()
        print(f"##### EPOCH {epoch} END #######\n\n")

    print("Training took {:.2f} sec".format(time.time() - train_start_time))

    return model

if __name__ == "__main__":
    """
    Main section for when this file is invoked directly.
    """
    main()