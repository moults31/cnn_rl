import numpy as np
import common
import os
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import time
import argparse
from sklearn.metrics import accuracy_score, roc_auc_score


class StandardRNN( nn.Module ):
    def __init__( self ):
        # Layer architecture taken from S2 Table in the paper
        super( StandardRNN, self ).__init__()
        self.lstm1    = nn.GRU(input_size=48, hidden_size=128, batch_first=True)
        self.dropout1 = nn.Dropout( p=0.2 )
        self.lstm2    = nn.GRU(input_size=128, hidden_size=128, batch_first=True)
        self.dropout2 = nn.Dropout( p=0.1 )
        self.fc1      = nn.Linear( in_features=15360, out_features=2 )
        self.dropout3 = nn.Dropout( p=0.2 )

    def forward( self, x ):
        x, _ = self.lstm1(x)
        x    = self.dropout1(x)
        x, _ = self.lstm2(x)
        x    = F.relu(x)
        x    = self.dropout2(x)
        # Todo: The paper says don't flatten here, but we have shape
        # [batch, n_rows, hidden_dim], so how else can we feed it to a linear layer?
        x    = torch.flatten(x, 1) # flatten all dimensions except batch
        x    = self.fc1(x)
        x    = self.dropout3(x)
        x    = F.softmax( x, dim=1 )
        return x

def main( data_path, n_epoch=common.N_EPOCH, class_weight=common.CLASS_WEIGHT_RATIO, learning_rate=1e-4 ):
    """
    Main function.
    Creates a model, trains it, and evaluates it against test set and val set.
    """
    print( f"\nRunning RNN on CUDA device: {common.device}"    )
    print( f"            Cohort: {os.path.basename(data_path)}")

    # Load images and labels for each split
    train_loader, test_loader, val_loader = common.load_data(data_path=data_path)

    # Create and train the model
    model = StandardRNN().to( common.device )
    model = train_rnn( model, train_loader, data_path, n_epoch, class_weight, learning_rate )

    # Evaluate the model's predictions against the ground truth
    y_score_test, y_pred_test, y_test = eval_model( model, test_loader )
    y_score_val,  y_pred_val,  y_val  = eval_model( model, val_loader  )

    # Evaluate the scores' predictions against the ground truth
    auc, acc, p, r, f = common.evaluate_predictions( y_test, y_pred_test, score=y_score_test )
    common.print_scores( "test", acc, auc, p, r, f )   

    auc, acc, p, r, f = common.evaluate_predictions( y_val, y_pred_val, score=y_score_val )
    common.print_scores( "val", acc, auc, p, r, f )

    common.dump_outputs( y_pred_val, y_val )

def eval_model( model, dataloader ):
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
    Y_pred  = []
    Y_true  = []
    
    for data, target in dataloader:
        data           = data.to( common.device ).squeeze(1)
        outputs        = model( data )
        _, predictions = torch.max( outputs, 1 )
        predictions    = predictions.to( 'cpu' )
        y_hat          = outputs[:,1]

        Y_score = np.concatenate( (Y_score, y_hat.to('cpu').detach().numpy() ), axis=0 )
        Y_pred.append( predictions )
        Y_true.append( target )

    Y_pred = np.concatenate( Y_pred, axis=0 )
    Y_true = np.concatenate( Y_true, axis=0 )

    return Y_score, Y_pred, Y_true

def train_rnn( model, train_dataloader, data_path, n_epoch=common.N_EPOCH, class_weight=common.CLASS_WEIGHT_RATIO, learn_rate=1e-4 ):
    """
    :param model: A RNN model
    :param train_dataloader: the DataLoader of the training data
    :param n_epoch: number of epochs to train
    :return:
        model: trained model
    """
    # Assign class weights and create 2-class criterion
    class_weight_ratio = common.CLASS_WEIGHT_RATIO if common.FORCE_CLASS_WEIGHT else class_weight
    weights            = [1.0 / class_weight_ratio, 1.0 - (1.0 / class_weight_ratio) ]
    class_weights      = torch.FloatTensor( weights ).to( common.device )
    criterion          = torch.nn.modules.loss.CrossEntropyLoss( weight=class_weights )
    print( f"     Number epochs: {n_epoch}"    )  
    print( f"     Learning rate: {learn_rate}" )   
    print( f"Class weight ratio: {class_weight_ratio}" )
    common.print_output_header()

    # Assign LR=1e-3 taken from the paper
    optimizer = torch.optim.Adam( model.parameters(), lr=learn_rate, weight_decay=1e-6 )

    model.train() # prep model for training

    train_start_time = time.time()
    
    for epoch in range(n_epoch):

        curr_epoch_loss  = []
        epoch_start_time = time.time()
        i                = 0
        
        for data, target in train_dataloader:
            # Transfer tensors to GPU
            data, target = data.to( common.device ), target.to( common.device )
            data         = data.squeeze(1)

            # zero the parameter gradients
            optimizer.zero_grad()

            # forward + backward + optimize
            outputs = model( data )
            loss    = criterion( outputs, target )
            loss.backward()
            optimizer.step()

            curr_epoch_loss.append( loss.cpu().data.numpy() )

            # Print progress indicator
            if (i % 10) == 0:
                print('.', end='', flush=True)
            i = i + 1

        epoch_time      = time.time() - epoch_start_time
        curr_epoch_loss = np.mean( curr_epoch_loss )

        # Optionally make predictions and evaluate between every epoch.
        # Adds a lot of time, but is worth it to get intermediate readouts when training epochs are very slow
        if ( common.EVAL_EVERY_EPOCH ):
            with torch.no_grad():
                # Put model in eval mode temporarily
                model.eval()

                # Get entire dataloader
                _, test_loader, val_loader = common.load_data(data_path=data_path)
                # Evaluate the model's predictions against the ground truth
                y_score_test, y_pred_test, y_test = eval_model( model, test_loader )
                y_score_val,  y_pred_val,  y_val  = eval_model( model, val_loader  )

                # Evaluate the scores' predictions against the ground truth
                auc,  acc,  p,  r,  f  = common.evaluate_predictions( y_test, y_pred_test, score=y_score_test )
                auc2, acc2, p2, r2, f2 = common.evaluate_predictions( y_val,  y_pred_val,  score=y_score_val  )
                
                common.print_epoch_output( epoch+1, epoch_time, curr_epoch_loss, acc, auc, p, r, f, acc2, auc2, p2, r2, f2 )

                # Stop early if we hit our target
                if common.DO_EARLY_STOPPING and auc >= common.TARGET_AUC_RNN:
                    break

            # Put model back in training mode
            model.train()

    print( "Training took {:.2f} sec".format( time.time() - train_start_time ) )

    return model

if __name__ == "__main__":
    """
    Main section for when this file is invoked directly.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--cohort', type=str, nargs=1,
                        help='Path to shuffled cohort, relative to IMAGES_DIR')
    parser.add_argument('-n', '--n_epochs', type=int, nargs=1,
                        help='Number of training epochs')
    parser.add_argument('-w', '--class_weight', type=float, nargs=1,
                        help='Class weight ratio to use for training')
    parser.add_argument('-l', '--learning_rate', type=float, nargs=1,
                        help='Learning rate to use for training')
    args = parser.parse_args()

    cohort_path = os.path.join(os.getenv('IMAGES_DIR'), args.cohort[0])

    n_epochs = common.N_EPOCH
    if args.n_epochs is not None:
        n_epochs = args.n_epochs[0]

    main(cohort_path, n_epochs, args.class_weight[0], args.learning_rate[0])
