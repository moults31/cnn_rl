from datetime import datetime
import numpy as np
import common

class Patient:
    def __init__(self, subject_id: int, admittime: datetime, dischtime: datetime, hospital_expire_flag: int):
        self.subject_id = subject_id
        self.admittime = admittime
        self.dischtime = dischtime
        self.hospital_expire_flag = hospital_expire_flag
        self.img = np.zeros((common.N_ROWS, common.N_COLS), dtype=int)