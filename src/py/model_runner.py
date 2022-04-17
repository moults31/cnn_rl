from xml.etree.ElementInclude import include
import clinical_scores
import cnn
import cnn_rl
import rnn
import inceptionv3

def main():
    """
    Main function.
    Runs all models with default settings.
    """
    print("###############################")
    print("Running MEWS/SOFA")
    clinical_scores.main()
    print("###############################\n")

    print("###############################")
    print("Running CNN")
    cnn.main()
    print("###############################\n")

    print("###############################")
    print("\nRunning RNN")
    rnn.main()
    print("###############################\n")

    print("###############################")
    print("\nRunning CNN-RL")
    cnn_rl.main()
    print("###############################\n")

    print("###############################")
    print("\n Running InceptionV3")
    inceptionv3.main(n_epoch=0)
    print("###############################\n")


if __name__ == "__main__":
    """
    Main section for when this file is invoked directly.
    """
    main()