from csv import reader
import sys
import common
import numpy as np

def parse_csv(csv_file: str):
    """
    Top-level function that loads the provided 
    csv and parses it to print out stats and item2feature structures
    """
    m_stats = np.zeros((common.N_ROWS, common.Stats_col.N_COLS), dtype=np.float64)
    m_item2feature = dict()

    with open(csv_file, 'r') as f:
        i = 0
        for row in reader(f):
            if i == 0:
                # Skip header row, we'll parse the columns ourselves
                i = i + 1
                continue

            itemids = row[3].split(';')
            featureid = int(row[2])

            for itemid in itemids:
                m_item2feature[int(itemid)] = featureid

            m_stats[featureid, :] = row[4:]

    print("item2feature = {")
    for key in m_item2feature:
        print(f"    {key}: {m_item2feature[key]},")
    print("}")

    print("\n# Autogenerated by parse_clinical_variables.py")
    print("stats = np.array([")
    for i in range(m_stats.shape[0]):
        print("    [", end='')
        for j in range(m_stats.shape[1]):
            print(f"{m_stats[i, j]},", end='')
        print("],")
    print("])")
    

if __name__ == "__main__":
    # Store csv_filename, and fail if not supplied
    try:
        csv_file = sys.argv[1]
    except:
        print("Usage: python csv_to_images.py <full/path/to/csv_file>")
        raise

    parse_csv(csv_file)