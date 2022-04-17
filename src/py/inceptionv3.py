import numpy as np
import common
import os
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torchvision import transforms, models
import time
from sklearn.metrics import accuracy_score, roc_auc_score

def run_tutorial():
    """
    Inceptionv3 tutorial to sanity check local environment.
    Copied directly from https://pytorch.org/hub/pytorch_vision_inception_v3
    """
    # Create and train the model
    model = torch.hub.load('pytorch/vision:v0.10.0', 'inception_v3', pretrained=True)
    model.eval()

    # Download an example image from the pytorch website
    import urllib
    url, filename = ("https://github.com/pytorch/hub/raw/master/images/dog.jpg", "dog.jpg")
    try: urllib.URLopener().retrieve(url, filename)
    except: urllib.request.urlretrieve(url, filename)

    # sample execution (requires torchvision)
    from PIL import Image
    from torchvision import transforms
    input_image = Image.open(filename)
    preprocess = transforms.Compose([
        transforms.Resize(299),
        transforms.CenterCrop(299),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ])
    input_tensor = preprocess(input_image)
    input_batch = input_tensor.unsqueeze(0) # create a mini-batch as expected by the model

    # move the input and model to GPU for speed if available
    if torch.cuda.is_available():
        input_batch = input_batch.to('cuda')
        model.to('cuda')

    with torch.no_grad():
        output = model(input_batch)
    # Tensor of shape 1000, with confidence scores over Imagenet's 1000 classes
    print(output[0])
    # The output has unnormalized scores. To get probabilities, you can run a softmax on it.
    probabilities = torch.nn.functional.softmax(output[0], dim=0)
    print(probabilities)

    # Download ImageNet labels
    os.system('wget https://raw.githubusercontent.com/pytorch/hub/master/imagenet_classes.txt') 

    # Read the categories
    with open("imagenet_classes.txt", "r") as f:
        categories = [s.strip() for s in f.readlines()]
    # Show top categories per image
    top5_prob, top5_catid = torch.topk(probabilities, 5)
    for i in range(top5_prob.size(0)):
        print(categories[top5_catid[i]], top5_prob[i].item())

def main():
    """
    Main function.
    Creates a model, trains it, and evaluates it against test set and val set.
    Adapted from https://pytorch.org/hub/pytorch_vision_inception_v3
    """
    print(f"Running on CUDA common.device: {common.device}")

    # Load images and labels for each split
    train_loader, test_loader, val_loader = common.load_data(batch_size=16)

    # Create and train the model
    model = models.Inception3(num_classes=2)
    model.to(common.device)

    train_inceptionv3(model, train_loader)

    # Evaluate the model's predictions against the ground truth
    with torch.no_grad():
        y_score_test, y_pred_test, y_test = eval_model(model, test_loader)
        y_score_val, y_pred_val, y_val = eval_model(model, val_loader)
    acc_test = accuracy_score(y_test, y_pred_test)
    acc_val = accuracy_score(y_val, y_pred_val)
    auc_test = roc_auc_score(y_test, y_score_test)
    auc_val = roc_auc_score(y_val, y_score_val)

    print(("Test Accuracy: " + str(acc_test)))
    print(("Validation Accuracy: " + str(acc_val)))
    print(("Test AUC: " + str(auc_test)))
    print(("Validation AUC: " + str(auc_val)))

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
    i = 0
    for data, target in dataloader:
        # Manipulate image to shape [batch, 3, 299, 299] that Inceptionv3 expects
        data = data.expand(data.shape[0], 3, data.shape[2], data.shape[3])
        preprocess = transforms.Compose([
            transforms.Resize(299),
        ])
        data = preprocess(data)
        data = data.to(common.device)
        outputs = model(data)
        _, predictions = torch.max(outputs, 1)
        predictions = predictions.to('cpu')
        y_hat = outputs[:,1]

        Y_score = np.concatenate((Y_score, y_hat.to('cpu').detach().numpy()), axis=0)
        Y_pred.append(predictions)
        Y_true.append(target)

        # Print progress indicator
        if (i % 100) == 0:
            print('.', end='', flush=True)
        i = i + 1

    Y_pred = np.concatenate(Y_pred, axis=0)
    Y_true = np.concatenate(Y_true, axis=0)

    return Y_score, Y_pred, Y_true

def train_inceptionv3(model, train_dataloader, n_epoch=5):
    """
    :param model: An Inceptionv3 model
    :param train_dataloader: the DataLoader of the training data
    :param n_epoch: number of epochs to train
    :return:
        model: trained model
    """
    # Assign class weights and create 2-class criterion
    class_weight_ratio = 20.0 # Nominally 30, but this seems to balance Inceptionv3
    weights = [1.0/class_weight_ratio, 1.0-(1.0/class_weight_ratio)]
    class_weights = torch.FloatTensor(weights).to(common.device)
    criterion = torch.nn.modules.loss.CrossEntropyLoss(weight=class_weights)

    # Assign LR=1e-3 taken from the paper
    optimizer = torch.optim.RMSprop(model.parameters(), lr=5e-2)

    model.train() # prep model for training

    train_start_time = time.time()
    for epoch in range(n_epoch):
        curr_epoch_loss = []
        epoch_start_time = time.time()
        i = 0
        for data, target in train_dataloader:
            # Transfer tensors to GPU
            data, target = data.to(common.device), target.to(common.device)

            # Manipulate image to shape [batch, 3, 299, 299] that Inceptionv3 expects
            data = data.expand(data.shape[0], 3, data.shape[2], data.shape[3])
            preprocess = transforms.Compose([
                transforms.Resize(299),
            ])
            data = preprocess(data)

            # zero the parameter gradients
            optimizer.zero_grad()

            # forward + backward + optimize
            data = data.to(common.device)
            outputs, aux_output = model(data)
            loss = criterion(outputs, target)
            loss.backward()
            optimizer.step()

            curr_epoch_loss.append(loss.cpu().data.numpy())

            # Print progress indicator
            if (i % 100) == 0:
                print('.', end='', flush=True)
            i = i + 1
        print(f"\nEpoch {epoch}: curr_epoch_loss={np.mean(curr_epoch_loss)}")
        print("Epoch took {:.2f} sec".format(time.time() - epoch_start_time))

    print("Training took {:.2f} sec".format(time.time() - train_start_time))

    return model

if __name__ == "__main__":
    """
    Main section for when this file is invoked directly.
    """
    main()