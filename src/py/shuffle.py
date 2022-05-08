from csv import reader, writer
import os
import sys
import common
import numpy as np
import shutil

def shuffle_images(orig_name, shuffled_name, seed):
    """
    Shuffles an existing cohort of images into splits.
    Pre:
        Folder structure must be <repo>/images/<orig_cohort_name>/master/<all_the_images>
    Post:
        Folder structure will be <repo>/images/<orig_cohort_name>/<shuffled_cohort_name>/test,train,val/<all_the_images>
    """

    # Determine number of images in master path
    img_path = os.getenv( 'IMAGES_DIR' )
    master_img_path = os.path.join( img_path, orig_name, 'master' )
    master_imgs = os.listdir(master_img_path)
    n = len(master_imgs)

    # Create output directories for shuffled splits
    train_path = os.path.join( img_path, orig_name, shuffled_cohort_name, 'train' )
    test_path = os.path.join( img_path, orig_name, shuffled_cohort_name, 'test' )
    val_path = os.path.join( img_path, orig_name, shuffled_cohort_name, 'val' )
    os.makedirs(train_path)
    os.makedirs(test_path)
    os.makedirs(val_path)

    for i in range(n):
        # Determine which split this patient will fall into and set the path accordingly.
        # Todo: Add a feature for shuffling splits
        split    = common.get_split_as_string( i, n, seed )
        shuffled_img_path = os.path.join( img_path, orig_name, shuffled_cohort_name, split )

        # Get the ground truth from the last character of the filename
        died = master_imgs[i][master_imgs[i].find('.') - 1]

        # Copy image to the correct split
        src = os.path.join(master_img_path, master_imgs[i])
        dst = os.path.join(shuffled_img_path, master_imgs[i])
        shutil.copyfile(src, dst)

        # Write label for this patient into labels.csv
        with open( os.path.join( shuffled_img_path, common.ANNOTATIONS_FILE_NAME), 'a', newline='' ) as f:
            label_writer = writer( f, delimiter=',' )

            line = [c.strip() for c in f"{master_imgs[i]}, {died}".strip(', ').split(',')]
            label_writer.writerow(line)


if __name__ == "__main__":
    """
    Main section for when this file is invoked directly. Should only
    be used for debugging csv parsing down to image generation.
    """
    # Store csv_filename, and fail if not supplied
    try:
        orig_cohort_name = sys.argv[1]
    except:
        print("Usage: python csv_to_images.py <csv_file> <cohort_name> <seed>")
        raise

    # Store output image name suffix if supplied, but carry on if not
    try:
        shuffled_cohort_name = sys.argv[2]
    except:
        print("Usage: python csv_to_images.py <csv_file> <cohort_name> <seed>")
        raise

    # Store output image name suffix if supplied, but carry on if not
    try:
        seed = sys.argv[3]
    except:
        print("Usage: python csv_to_images.py <csv_file> <cohort_name> <seed>")
        raise

    shuffle_images(orig_cohort_name, shuffled_cohort_name, seed)
