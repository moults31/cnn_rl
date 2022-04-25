from datetime import datetime
import numpy as np
import common

class Patient_visit:
    def __init__(self, patient_id: int, visit_id: int, hospital_expire_flag: int):
        self.patient_id = patient_id
        self.visit_id = visit_id
        self.hospital_expire_flag = hospital_expire_flag
        self.img = np.zeros((common.N_ROWS, common.N_COLS), dtype=int)
