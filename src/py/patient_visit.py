from datetime import datetime
import numpy as np
import common

class Patient_visit:
    def __init__(self, patient_id: int, visit_id: int, hospital_expire_flag: int, stats: np.ndarray, item2feature: np.ndarray):
        self.patient_id = patient_id
        self.visit_id = visit_id
        self.hospital_expire_flag = hospital_expire_flag
        self.img = self.init_img(stats)
        self.braden = self.init_braden(stats, item2feature)
        self.morse = self.init_braden(stats, item2feature)

    def init_img(self, stats: np.ndarray):
        """
        Initialize default values per row in img
        """
        img = np.zeros((common.N_ROWS, common.N_COLS), dtype=int)
        for row in range(common.N_ROWS):
            # Normalize the default val within the range specified for the given row.
            # Pulls some args directly from stats, which is okay here. Other calls to normalize,
            # especially when var_type==2, need to provide these args from the input csv row
            val_default_normalized = common.normalize(
                stats,
                stats[row, common.Stats_col.VAL_DEFAULT],
                stats[row, common.Stats_col.VAL_MIN],
                stats[row, common.Stats_col.VAL_MAX],
                row,
                stats[row, common.Stats_col.VAR_TYPE],
                common.NORM_METHOD
            )
            # Assign normalized default value to entire row
            img[row, :] = val_default_normalized
        return img

    def init_braden(self, stats, item2feature):
        """
        Initialize default values per row in braden score component records
        """
        braden = np.zeros((len(common.braden_item2row), common.N_HOURS), dtype=np.float64)
        for itemid in common.braden_item2row:
            featureid = item2feature[itemid]
            val_default_normalized = common.normalize(
                stats,
                stats[featureid, common.Stats_col.VAL_DEFAULT],
                stats[featureid, common.Stats_col.REF_MIN],
                stats[featureid, common.Stats_col.REF_MAX],
                featureid,
                stats[featureid, common.Stats_col.VAR_TYPE],
                common.NORM_METHOD
            )
            braden[common.braden_item2row[itemid], :] = val_default_normalized
        return braden

    def init_morse(self, stats, item2feature):
        """
        Initialize default values per row in morse score component records
        """
        morse = np.zeros((len(common.morse_item2row), common.N_HOURS), dtype=np.float64)
        for itemid in common.morse_item2row:
            featureid = item2feature[itemid]
            val_default_normalized = common.normalize(
                stats,
                stats[featureid, common.Stats_col.VAL_DEFAULT],
                stats[featureid, common.Stats_col.REF_MIN],
                stats[featureid, common.Stats_col.REF_MAX],
                featureid,
                stats[featureid, common.Stats_col.VAR_TYPE],
                common.NORM_METHOD
            )
            morse[common.morse_item2row[itemid], :] = val_default_normalized
        return morse
