from xml.etree.ElementInclude import include
import cnn
import cnn_rl
import rnn
import inceptionv3
import common
import os
import argparse

def main( data_path, n_epoch, class_weight, learning_rate ):
    """
    Main function.
    Runs all models with default settings.
    """
    print("###############################")
    print("Running CNN")
    cnn.main(data_path, n_epoch, class_weight, learning_rate)
    print("###############################\n")

    print("###############################")
    print("\nRunning RNN")
    rnn.main(data_path, n_epoch, class_weight, learning_rate)
    print("###############################\n")

    print("###############################")
    print("\nRunning CNN-RL")
    cnn_rl.main(data_path, n_epoch, class_weight, learning_rate)
    print("###############################\n")

    print("###############################")
    print("\n Running InceptionV3")
    inceptionv3.main(data_path, n_epoch, class_weight, learning_rate)
    print("###############################\n")


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