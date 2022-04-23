/****************************************************************************
 * MIMIC-IV data extraction script for combining timelines to predict patient mortality
 * 
 * This script aggregates the necessary data comprising the clinical variables used in the timelines.
 * In many cases, the data must be converted to a different format (normalized to [0...1], for example).
 *
 * Not all clinical variables have significant representation, or are located in easy to access places.
 * Best guesses and compromises were employed when necessary.
 * 
 * For variables with many idiomatic representations, or requiring lots of special case code to handle,
 * data is dumped verbatim and left for the parser to figure out as other languages
 * may be more suited to the task.
 * 
 * Author: Matthew Lind
 * Date: April 23, 2022
 ****************************************************************************/
-- set schema
set search_path to mimic_iv;

with val_defaults as (

	/*****************************************************************
	 * default values and reference ranges for clinical variables
	 *****************************************************************/
	--
	-- Patient characteristics --
	-- 
	(
		-- age
		select 0 pid, 0 rid, 0 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 91 val_max, 0 ref_min, 91 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- sex/gender
		select 0 pid, 1 rid, 1 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- ethnicity
		select 0 pid, 2 rid, 2 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- previous cardiac arrest
		select 0 pid, 3 rid, 3 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- prior admission to hospital within previous 90 days.
		select 0 pid, 4 rid, 4 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- hour of day
		select 0 pid, 5 rid, 5 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 23 val_max, 0 ref_min, 23 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- patient health severity (was patient location)
		select 0 pid, 6 rid, 6 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 9 val_max, 0 ref_min, 9 ref_max, 0 val_default, 0 hospital_expire_flag
	--
	-- vital signs (mimic_icu.chartevents)	
	--	
	) union (
		-- temperature C
		select 0 pid, 7 rid, 223762 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 27 val_min, 42 val_max, 36.1 ref_min, 37.2 ref_max, 37 val_default, 0 hospital_expire_flag
	) union (
		-- temperature F
		select 0 pid, 7 rid, 223761 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 90 val_min, 106 val_max, 97 ref_min, 99 ref_max, 98.6 val_default, 0 hospital_expire_flag
	) union (
		-- heart rate
		select 0 pid, 8 rid, 220045 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 25 val_min, 230 val_max, 60 ref_min, 100 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- respiratory rate
		select 0 pid, 9 rid, 220210 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 100 val_max, 12 ref_min, 20 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- blood pressure, systolic 1
		select 0 pid, 10 rid, 220179 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- blood pressure, systolic 2
		select 0 pid, 10 rid, 220050 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- blood pressure, diastolic 1
		select 0 pid, 11 rid, 220180 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- blood pressure, diastolic 2
		select 0 pid, 11 rid, 220051 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- O2 saturation 1
		select 0 pid, 12 rid, 220277 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- O2 saturation 2
		select 0 pid, 12 rid, 228232 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Fraction of inspired Oxygen (Fi02)
		select 0 pid, 13 rid, 223835 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Conscious level (AVPU)
		select 0 pid, 14 rid, 226104 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 20 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag

	--
	-- Laboratory cultures/ blood tests (mimic_hosp.labevents)
	--

	-- Blood metabolic panel --
	) union (
		-- Sodium
		select 0 pid, 15 rid, 50983 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Potassium
		select 0 pid, 16 rid, 50971 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Bicarbonate (CO2)
		select 0 pid, 17 rid, 50882 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Anion Gap
		select 0 pid, 18 rid, 50868 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Glucose 1
		select 0 pid, 19 rid, 50931 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Glucose 2
		select 0 pid, 19 rid, 50809 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Calcium
		select 0 pid, 20 rid, 50893 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Blood Urea Nitrogen (BUN) 1
		select 0 pid, 21 rid, 51006 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Blood Urea Nitrogen (BUN) 2
		select 0 pid, 21 rid, 52647 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Serium Creatinine (SCr)
		select 0 pid, 22 rid, 50912 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- BUN / SCr ratio
		select 0 pid, 23 rid, 111111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Phosphate
		select 0 pid, 24 rid, 50970 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	--
	-- LiverFunction Test -- (mimic_hosp.labevents)
	--
	) union (
		-- Total Protein
		select 0 pid, 25 rid, 50976 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Albumin
		select 0 pid, 26 rid, 50862 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Total Bilirubin
		select 0 pid, 27 rid, 50885 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- AST (SGOT)
		select 0 pid, 28 rid, 50878 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Alkaline Phosphatase
		select 0 pid, 29 rid, 50863 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag

	-- Complete Blood Count (CBC) --- (mimic_hosp.labevents)
	) union (
		-- White blood Cells (WBC) 1
		select 0 pid, 30 rid, 51300 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- White blood Cells (WBC) 2
		select 0 pid, 30 rid, 51301 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Hemoglobin 1
		select 0 pid, 31 rid, 51222 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Hemoglobin 2
		select 0 pid, 31 rid, 50811 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Platelet Count
		select 0 pid, 32 rid, 51265 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	
	-- Other Labs -- (mimic_hosp.labevents)
	) union (
		-- Lactate 
		select 0 pid, 33 rid, 50813 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Troponin I
		select 0 pid, 34 rid, 51002 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Troponin T
		select 0 pid, 34 rid, 51003 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- pH 
		select 0 pid, 35 rid, 50820 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Ketones 
		select 0 pid, 36 rid, 51984 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Chloride 
		select 0 pid, 37 rid, 50902 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- International Normalized Ration (INR)  1
		select 0 pid, 38 rid, 51237 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- International Normalized Ration (INR)  2
		select 0 pid, 38 rid, 51675 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Lipase
		select 0 pid, 39 rid, 50956 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Mean Corpuscular Volume (MCV)
		select 0 pid, 40 rid, 51250 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Partial pressure carbon dioxide (PaCO2)
		select 0 pid, 41 rid, 50818 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Partial pressure Oxygen (PaO2)
		select 0 pid, 42 rid, 50821 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Partial Thromboplastin Time (PTT)
		select 0 pid, 43 rid, 51275 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Red Cell Distribution Width (RDW)
		select 0 pid, 44 rid, 51277 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 200 val_max, 115 ref_min, 120 ref_max, 0 val_default, 0 hospital_expire_flag

	-- 
	-- Interventions --
	--
		
	) union (
		-- Dialysis
		select 0 pid, 45 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- IV Bolus 0.9% Sodium Chloride / Normal Saline
		select 0 pid, 46 rid, 225828 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- IV Bolus - Lactated Ringers
		select 0 pid, 46 rid, 225158 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Albumin 5%
		select 0 pid, 47 rid, 220864 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Albumin 25%
		select 0 pid, 47 rid, 220862 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Using Ventilator
		select 0 pid, 48 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Using BiPAP (EPAP)
		select 0 pid, 49 rid, 227579 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Using BiPAP (IPAP)
		select 0 pid, 49 rid, 227580 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Using BiPAP (bipap bpm (S/T backup)
		select 0 pid, 49 rid, 227581 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Using BiPAP (O2 flow)
		select 0 pid, 49 rid, 227582 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Using CPAP (constant positive air pressure)
		select 0 pid, 50 rid, 227583 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Using HFNC (High Flow Nasal Cannula)
		select 0 pid, 51 rid, 227287 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Using Suction
		select 0 pid, 52 rid, 226169 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag

	-- Transfusions
	) union (
		-- Red Blood Cells (RBC) transfusion
		select 0 pid, 53 rid, 225168 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Fresh Frozen Plasma (FFP) transfusion
		select 0 pid, 54 rid, 220970 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Platelet transfusion
		select 0 pid, 55 rid, 225170 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Cryoprecipitate transfusion
		select 0 pid, 56 rid, 225171 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	--
	-- Medications --
	-- 
	) union (
		-- Nebulizer Treatments
		select 0 pid, 57 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- IV/SC Hypoglycemics
		select 0 pid, 58 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- PO Hypoglycemics
		select 0 pid, 59 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Drip Hypoglycemics
		select 0 pid, 60 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Lactulose
		select 0 pid, 61 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- IV AV Nodal Blockers
		select 0 pid, 62 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- PO AV Nodal Blockers
		select 0 pid, 63 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- IV Antiarrhythmic
		select 0 pid, 64 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- PO Antiarrhythmic
		select 0 pid, 65 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Anti Seizures
		select 0 pid, 66 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- IV Anticoagulants
		select 0 pid, 67 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- IV Steroids
		select 0 pid, 68 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- PO Steroid
		select 0 pid, 69 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- IV Immunotherapy
		select 0 pid, 70 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- PO Immunotherapy
		select 0 pid, 71 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- IV AntiPsychotics
		select 0 pid, 72 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- PO AntiPsychotics
		select 0 pid, 73 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Sedative Drips
		select 0 pid, 74 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- IV Benzodiazepine
		select 0 pid, 75 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- PO Benzodiazepine
		select 0 pid, 76 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Vasopressors
		select 0 pid, 77 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Inotropes
		select 0 pid, 78 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- IV Diuretics
		select 0 pid, 79 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- PO Diuretics
		select 0 pid, 80 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Antibiotics
		select 0 pid, 81 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag

	-- 
	-- Examinations --
	--
	) union (
		-- Cardiac Paced
		select 0 pid, 82 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Atrial Fibrillation
		select 0 pid, 83 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Atrial Flutter
		select 0 pid, 84 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Using? (not sure what this is)
		select 0 pid, 85 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Superventricular SVT
		select 0 pid, 86 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- VT
		select 0 pid, 87 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- VF
		select 0 pid, 88 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Asystole
		select 0 pid, 89 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Heart Block
		select 0 pid, 90 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Junctional Rhythm
		select 0 pid, 91 rid, 11111 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default, 0 hospital_expire_flag

	-- 
	-- Braden scores
	--
	) union (
		-- Braden Sensory Perception
		select 0 pid, 92 rid, 224054 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 4 val_max, 3 ref_min, 4 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Braden Moisture
		select 0 pid, 93 rid, 224055 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 4 val_max, 3 ref_min, 4 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Braden Activity
		select 0 pid, 94 rid, 224056 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 4 val_max, 3 ref_min, 4 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Braden Mobility
		select 0 pid, 95 rid, 224057 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 4 val_max, 3 ref_min, 4 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Braden Nutrition
		select 0 pid, 96 rid, 224058 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 4 val_max, 3 ref_min, 4 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Braden Friction/Shear
		select 0 pid, 97 rid, 224059 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 3 val_max, 2 ref_min, 3 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Braden Cumulative Total
		select 0 pid, 98 rid, 8 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 23 val_max, 18 ref_min, 23 ref_max, 0 val_default, 0 hospital_expire_flag
		
	--
	--	Morse Fall risk scale
	--
	) union (
		-- Morse, patient has history of falling?
		select 0 pid, 99 rid, 227341 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 25 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Morse, patient has secondary diagnosis?
		select 0 pid, 100 rid, 227342 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 15 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Morse, patient use ambulatory aid?
		select 0 pid, 101 rid, 227343 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 30 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Morse, patient receiving IV therapy or Heparin Lock?
		select 0 pid, 102 rid, 227344 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 20 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Morse, how is patient's gait?
		select 0 pid, 103 rid, 227345 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 20 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Morse, what is patient's mental status?
		select 0 pid, 104 rid, 227346 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 15 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Morse, is patient low risk?
		select 0 pid, 105 rid, 227348 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Morse, is patient high risk?
		select 0 pid, 106 rid, 227349 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Morse, cumulative score
		select 0 pid, 107 rid, 9 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 2 var_type, 0 val_num, 0 val_min, 125 val_max, 0 ref_min, 25 ref_max, 0 val_default, 0 hospital_expire_flag

	--
	-- Diagnostics / Urinary
	--
	) union (
		-- EKG
		select 0 pid, 108 rid, 225402 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- TTE
		select 0 pid, 109 rid, 225432 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Chest X-ray
		select 0 pid, 110 rid, 225459 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Chest X-ray (portable)
		select 0 pid, 110 rid, 229581 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Abdomen X-ray
		select 0 pid, 111 rid, 225457 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- CT Scan (head, neck, chest, and abdomen)
		select 0 pid, 112 rid, 221214 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- CT Scan (head, neck, chest, and abdomen - portable
		select 0 pid, 112 rid, 229582 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Ultrasound
		select 0 pid, 113 rid, 221217 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Blood Culture Order
		select 0 pid, 114 rid, 225401 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Urine, OR Urine
		select 0 pid, 115 rid, 226627 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Urine, PACU Urine
		select 0 pid, 115 rid, 226631 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Urine, U Irrigant/Urine Volume Out
		select 0 pid, 115 rid, 227489 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Foley Catheter Placed
		select 0 pid, 116 rid, 229351 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	) union (
		-- Foley Catheter output
		select 0 pid, 116 rid, 226559 itemid, '1000-01-01 00:00:00.000' checkin, '1000-01-01 00:00:00.000' charted, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, 0 hospital_expire_flag
	)
	
), patient_ids as (

	/***********************************
	 * Patients - find all patients admitted to hospital who stayed at least 48 hours.
	 ***********************************/
	select subject_id
	from mimic_core.admissions a
	where extract( epoch from age( a.dischtime, a.admittime ) ) >= 172800
--	and subject_id between 10000000 and 10100000
	
), patient_chars as (

	/**************************************
	 * Patient characteristics - age, sex, race, ...
	 **********************************************/
	(
		-- age (normalized to range 0...100)
		select p.subject_id, a.hadm_id, 0 as itemid, a.admittime, a.admittime as charttime, 2 as "var_type", p.anchor_age as val_num, 0 as val_min, 100 as val_max, 0 as ref_min, 91 as ref_max, 0 as val_default, a.hospital_expire_flag
		from mimic_core.admissions a join mimic_core.patients p 
		on a.subject_id = p.subject_id 
		where a.hadm_id is not null
		and p.subject_id in (
			select *
			from patient_ids
		)
		
	) union (
		-- sex/gender (0=male, 1=female/other)
		select p.subject_id, a.hadm_id, 1 as itemid, a.admittime, a.admittime as charttime, 0 as "var_type", (case when p.gender = 'M' then 0 else 1 end) as val_num, 0 as val_min, 1 as val_max, 0 as ref_min, 1 as ref_max, 0 as val_default, a.hospital_expire_flag
		from mimic_core.admissions a join mimic_core.patients p 
		on a.subject_id = p.subject_id 
		where a.hadm_id is not null
		and p.subject_id in (
			select *
			from patient_ids
		)
		
	) union (
		-- race (0=black/african american, 1=other)
		select p.subject_id, a.hadm_id, 2 as itemid, a.admittime, a.admittime as charttime, 0 as "var_type", (case when a.ethnicity = 'BLACK/AFRICAN AMERICAN' then 0 else 1 end) as val_num, 0 as val_min, 1 as val_max, 0 as ref_min, 1 as ref_max, 0 as val_default, a.hospital_expire_flag
		from mimic_core.admissions a join mimic_core.patients p 
		on a.subject_id = p.subject_id 
		where a.hadm_id is not null
		and p.subject_id in (
			select *
			from patient_ids
		)
		
	) union (
	
		-- prior history of cardiace arrest (experienced in ICU)
		select a.subject_id, a.hadm_id, 3 as itemid, a.admittime, p.starttime, 0 as var_type, (case when p.value is null or p.value <> 1 then 0 else 1 end) as val_num, 0 as val_min, 1 as val_max, 0 as ref_min, 0 as ref_max, 0 as val_default, a.hospital_expire_flag 
		from mimic_core.admissions a join mimic_icu.procedureevents p 
		on a.subject_id = p.subject_id 
		where a.hadm_id is not null 
		and p.itemid = 225466 
		and p.subject_id in (
			select *
			from patient_ids
		)		
		and extract( epoch from age( a.admittime, p.starttime )) >= 0
		
	) union (
		-- prior hospital admissions within past 90 days (this could certainly be optimized)
	
		with tmp as (
		
			-- get patient data from admissions table. Convert admittime to epoch time for easier math
			select a.subject_id, a.hadm_id, a.admittime, extract( epoch from a.admittime ) as time, a.hospital_expire_flag 
			from mimic_core.admissions a 
			where a.subject_id in (
				select *
				from patient_ids
			)
			order by a.admittime asc
			
		), time_diff as (
		
			-- compute difference between current admission and previous admission, for same patient
			select t.subject_id, t.hadm_id, t.admittime, t.time,
				lag( t.time )
					over ( partition by t.subject_id order by t.time ) as prev_time,
				-- NOTE: subtracting 90 here so downstream comparisons only need to check > 0.
				floor( (t.time - lag( t.time ) over ( partition by t.subject_id order by t.time )) / 86400) - 90 as diff,
				t.hospital_expire_flag
			from tmp t
			order by t.time asc
		)
		-- assess results and flag all prior admissions within 90 days
		select t.subject_id, t.hadm_id, 4 as itemid, t.admittime, t.admittime as charttime, 0 as var_type, (case when t.diff is null or t.diff > 0 then 0 else 1 end) as val_num, 0 as val_min, 1 as val_max, 0 as ref_min, 0 as ref_max, 0 as val_default, t.hospital_expire_flag
		from time_diff t
--		order by t.subject_id asc, t.admittime asc
	
	) union (
		-- hour of day.  compute hour of day in military time upon admission to hospital.  This must be incremented hourly for first 48 hours of the visit.
		select p.subject_id, a.hadm_id, 5 as itemid, a.admittime, a.admittime as charttime, 2 as "var_type", (extract( hour from a.admittime)) as val_num, 0 as val_min, 23 as val_max, 0 as ref_min, 23 as ref_max, 0 as val_default, a.hospital_expire_flag
		from mimic_core.admissions a join mimic_core.patients p 
		on a.subject_id = p.subject_id 
		where a.hadm_id is not null
		and p.subject_id in (
			select *
			from patient_ids
		)
	) union (
		-- patient admission type (degree of severity/urgency).  Mimic's concept of location is not the same as university of chicago, and therefore not useful.
		select p.subject_id, a.hadm_id, 6 as itemid, a.admittime, a.admittime as charttime, 2 as "var_type", 
		(case 
			when a.admission_type = 'ELECTIVE' then 1
			when a.admission_type = 'OBSERVATION ADMIT' then 2
			when a.admission_type = 'DIRECT OBSERVATION' then 3
			when a.admission_type = 'AMBULATORY OBSERVATION' then 4
			when a.admission_type = 'EU OBSERVATION' then 5
			when a.admission_type = 'SURGICAL SAME DAY ADMISSION' then 6
			when a.admission_type = 'URGENT' then 7
			when a.admission_type = 'DIRECT EMER.' then 8
			when a.admission_type = 'EW EMER.' then 9
			else 0 end
		) as val_num, 0 as val_min, 9 as val_max, 1 as ref_min, 9 as ref_max, 0 as val_default, a.hospital_expire_flag
		from mimic_core.admissions a join mimic_core.patients p 
		on a.subject_id = p.subject_id 
		where a.hadm_id is not null
		and p.subject_id in (
			select *
			from patient_ids
		)
	)

), chart_events as (

	/******************************************
	 * Vital signs and interventions - ICU charted events
	 *******************************************/
	( 
		-- consider adding 'warning' field
		select c.subject_id, c.hadm_id, c.itemid, a.admittime, c.charttime, 0 as "var_type", 1 as val_num, 0 as val_min, 1 as val_max, 0 as ref_min, 0 as ref_max, 0 as val_default, a.hospital_expire_flag
		from mimic_core.admissions a join mimic_icu.chartevents c
		on a.subject_id = c.subject_id 
		where c.hadm_id is not null
		and c.valuenum is not null
		and c.itemid in (
			-- ventilation (convert to binary)
			227579, 227580, 227581, 227582,	-- using BiPAP [numeric] 227579=EPAP, 227580=IPAP, 227581=BiPap bpm (S/T -Back up), 227582=O2 flow, 
			227583, 						-- using CPAP (Constant Positive Airway Pressure).  values="On|Off"
			227287,							-- using HFNC.  O2 Flow (additional cannula). values=numeric
			226169							-- using suction (clear the airways?).  values = 0|1
	
		) and c.subject_id in (
			-- ids of patients admitted to hospital and stayed for at least 48 hours.
			select *
			from patient_ids
		) and extract( epoch from age( c.charttime, a.admittime )) between 0 and 172800
		
	) union (
		-- consider adding 'warning' field
		select c.subject_id, c.hadm_id, c.itemid, a.admittime, c.charttime, 1 as "var_type", c.valuenum as val_num, 0 as val_min, 999999 as val_max, 0 as ref_min, 999 as ref_max, 0 as val_default, a.hospital_expire_flag
		from mimic_core.admissions a join mimic_icu.chartevents c
		on a.subject_id = c.subject_id 
		where c.hadm_id is not null
		and c.valuenum is not null
		and c.itemid in (
		
			-- vital signs (continuous)
			223835, 					-- FiO2. 223835=Fraction of Inspired O2.  
			220045, 					-- Heart rate
			223762,						-- Temperature C
			223761,						-- Temperature F.
			220210, 					-- Respiratory Rate
			220179, 220050,   			-- Blood pressure, systolic.
			220180, 220051,				-- Blood pressure, diastolic
			220277, 228232,				-- O2 saturation.  228232=PAR-Oxygen saturation (routine vital signs). 220277=O2 saturation pulseoxymetry (SpO2),  223770,223769=SpO2 alarms
			
			-- intervention itemids
			223900,						-- Glasgow Coma "Motor" score
			
			-- morse / braden scores (continuous)
			224054,		-- Braden Sensory Perception
			224055,		-- Braden Moisture
			224056,		-- Braden Activity
			224057,		-- Braden Mobility
			224058,		-- Braden Nutrition
			224059,		-- Braden Friction/Shear
			
			227341,		-- Morse, History of falling (within 3 mnths)
			227342,		-- Morse, Secondary diagnosis
			227343,		-- Morse, Ambulatory aid
			227344,		-- Morse, IV/Saline lock
			227345,		-- Morse, Gait/Transferring
			227346,		-- Morse, Mental status
			227348,		-- Morse score, is Low risk (25-50) interventions
			227349		-- Morse score, is High risk (>51) interventions
	
		) and c.subject_id in (
			-- ids of patients admitted to hospital and stayed for at least 48 hours.
			select *
			from patient_ids
		) and extract( epoch from age( c.charttime, a.admittime )) between 0 and 172800
	) union ( 
		-- Conscuous level score (AVPU).  Must parse separtely because it's values are text, not numeric.
		select c.subject_id, 
			c.hadm_id, 
			c.itemid, 
			a.admittime, 
			c.charttime, 
			1 as "var_type",
			(case 
				when c.value = 'Unresponsive' then 3
				when c.value = 'Arouse to Pain' then 2
				when c.value = 'Arouse to Voice' then 1
				when c.value = 'Alert' then 0
				-- the next 3 are best guesses because they're not part of the standard AVPU scoring
				when c.value = 'Lethargic' then 1
				when c.value = 'Awake/Unresponsive' then 2
				when c.value = 'Arouse to Stimulation' then 2
				end) as val_num, 
			0 as val_min, 
			3 as val_max, 
			0 as ref_min, 
			0 as ref_max, 
			0 as val_default, 
			a.hospital_expire_flag
		from mimic_core.admissions a join mimic_icu.chartevents c
		on a.subject_id = c.subject_id 
		where c.hadm_id is not null
		and c.value is not null
		and c.itemid = 226104		-- Conscious level (AVPU).  227428=SOFA score, 226755=Glasgow Apache 2 score, 226994=Apache IV mortality prediction, 227013=GcsScore_ApacheIV Score	
		and c.subject_id in (
			-- ids of patients admitted to hospital and stayed for at least 48 hours.
			select *
			from patient_ids
		) and extract( epoch from age( c.charttime, a.admittime )) between 0 and 172800
	)
	
), labs as (

	/****************************************************
	 * Labs - recorded events for blood tests, urine, cultures, ...
	 *****************************************************/
	(
		-- special case: 51484=ketones (urine).  Many of the records have NULL valuenum and reference ranges.  Must explicitly cast values to comply with everything else.
		select l.subject_id, l.hadm_id, l.itemid, a.admittime, l.charttime, 2 as "var_type", (case when l.valuenum is null then 0 else l.valuenum end) as val_num, 0 as val_min, 160 as val_max, 0 as ref_min, 0 as ref_max, 0 as val_default, a.hospital_expire_flag
		from mimic_core.admissions a join mimic_hosp.labevents l
		on a.subject_id = l.subject_id 
		where l.hadm_id is not null
		and l.itemid in (
			-- lab clinical variables of interest
			51484			-- Ketones (Urine).
			
		) and l.subject_id in (
			-- ids of patients admitted to hospital and stayed for at least 48 hours.
			select *
			from patient_ids
		) 
		and extract( epoch from age( l.charttime, a.admittime )) between 0 and 172800
		
	) union (
	
		select l.subject_id, l.hadm_id, l.itemid, a.admittime, l.charttime, 2 as "var_type", (case when l.valuenum is null then 0 else l.valuenum end ) as val_num, 0 as val_min, 999 as val_max, l.ref_range_lower as ref_min, l.ref_range_upper as ref_max, ((l.ref_range_lower+l.ref_range_upper)/2.0) as val_default, a.hospital_expire_flag
		from mimic_core.admissions a join mimic_hosp.labevents l
		on a.subject_id = l.subject_id 
		where l.hadm_id is not null
		and l.itemid in (
		
			-- lab clinical variables of interest
			50862,					-- Albumin
			50863,					-- Alkaline Phosphatase
			50868,					-- Anion Gap
			50878,					-- AST (SGOT) (aka Asparate Aminotransferase)
			50882,					-- Bicarbonate.  50803=Calculated Bicarbonate, Whole Blood, 50804=Calculated Total CO2, 
			51006, 52647,			-- Blood Urea Nitrogen (BUN)
			50893,					-- Calcium, Total
			50902,					-- Chloride
			50931, 50809,			-- Glucose, 50809=Glucose (blood gas)
			51222, 50811,			-- Hemoglobin.  51222=Hemoglobin (hematology). 50811=Hemoglobin	(Blood Gas)
			51237, 51675,			-- International Normalized Ration (INR), 51237=INR (chemistry, 51675=INR (hematology)
			51984,					-- Ketones (Urine).
			50813,					-- Lactate.  
			50956,					-- Lipase
			51250,					-- Mean Corpuscular Volume (MCV). 51691=MCV (chemistry) <-- none found, 51250=MCV (hematology)
			50818,					-- partial pressure Carbone Dioxide (PaCO2)
			50821,					-- partial pressure Oxygen (PaO2)
			51275,					-- partial Thromboplastin Time (PTT)
			50820,					-- pH. 51491=pH (hematology), 50820=pH (blood)
			50970,					-- Phosphate.  51095=Phosphate (Urine)
			51265,					-- Platelet Count. 51704=Platelet Count (chemistry). 51265=Platelet Count (Hematology)
			50971, 					-- Potassium.
			51277, 					-- Red Cell Distribution Width (RDW)
			50983,					-- Sodium
			50885,					-- Bilirubin, Total
			50976,					-- Protein, Total.  51492=Protein, Urine (Hematology)
			51002, 51003, 			-- Troponin. 51002=Troponin I (none found).  51003=Troponin T (hematology), 52642=Troponin I. 
			51300, 51301			-- White Blood Cells (WBC).  51301=White blood Cells (hematology).  51300=WBC Count (blood)
			
		) and l.subject_id in (
			-- ids of patients admitted to hospital and stayed for at least 48 hours.
			select *
			from patient_ids
		) 
		and extract( epoch from age( l.charttime, a.admittime )) between 0 and 172800
	)
	
--), medications as (

	/****************************************************
	 * Medications - find medications given to the patient
	 *****************************************************/
/*
	select d.subject_id, d.hadm_id, e.itemid, d.admittime, e.charttime, e.value, e.valuenum, e.valueuom, d.hospital_expire_flag
	from mimic_core.admissions d join mimic_hosp.emar e
	on d.subject_id = l.subject_id 
	where d.hadm_id is not null
	and e.valuenum is not null
	and e.itemid in (
		-- medications

	)
	and l.subject_id in (
		-- ids of patients admitted to hospital and stayed for at least 48 hours.
		select *
		from patient_ids
	)
	and extract( epoch from age( l.charttime, d.admittime )) between 0 and 172800
*/
), input_events as (

	/*****************************************************
	 * Input events - events for fluids, medications and other substances administered to patient in the ICU
	 * 
	 * NOTE: amount may be <= 0 (but rare)
	 *****************************************************/
	-- consider adding: rate, rate uom fields
	select i.subject_id, i.hadm_id, i.itemid, a.admittime, i.starttime as charttime, 0 as "var_type", (case when i.amount is null or i.amount <= 0 then 0 else 1 end) as val_num, 0 as val_min, 1 as val_max, 0 as ref_min, 0 as ref_max, 0 as val_default, a.hospital_expire_flag
	from mimic_core.admissions a join mimic_icu.inputevents i 
	on a.subject_id = i.subject_id
	where i.hadm_id is not null
--	and i.amount is not null and i.amount > 0
	and i.itemid in (
	
		-- interventions (convert to binary)
							-- Dialysis
		225828, 225158,		-- IV bolus.  225158=0.9% NaCl (aka Normal Saline),  225828=Lactated Ringers
		220864, 			-- Albumin 5%
		220862,				-- Albumin 25%
		226367, 227072,		-- Fresh Frozen Plasma (FFP). returns small number of records.  Must convert to binary variable where non-zero = 1	
		
		-- transfusions (convert to binary)
		225168,				-- Red Blood Cell (RBC) transfusion.  225168=Packed Red Blood Cells, 227807=catheter changed (0|1)
		220970,				-- Fresh Frozen Plasma Transfusion (FFP)
		225170,				-- Platelet transfusion.
		225171				-- CryoPrecipitate.
	) 
	and a.subject_id in (
		select *
		from patient_ids 
	)
	and extract( epoch from age( i.starttime, a.admittime )) between 0 and 172800

), output_events as (

	/***********************
	 * Output events - events for collection of samples output from the patient.
	 * 
	 * NOTE: numeric values may be <= 0 (but rare).
	 **********************/
	select o.subject_id, o.hadm_id, o.itemid, a.admittime, o.charttime, 0 as "var_type", (case when o.value is null or o.value <= 0 then 0 else 1 end) as val_num, 0 as val_min, 1 as val_max, 0 as ref_min, 0 as ref_max, 0 as val_default, a.hospital_expire_flag
	from mimic_core.admissions a join mimic_icu.outputevents o 
	on a.subject_id = o.subject_id 
	where o.hadm_id is not null
	and o.itemid in (

		-- Urine output (convert to binary)
--		226566,		-- Urine and GU Irrigant out.  [No records found in mimic_iv]
		226627,		-- OR Urine
		226631,		-- PACU Urine
		227489,		-- U Irrigant/Urine Volume Out
		
		226559 		-- Foley catheter (output)	

		-- Mimic III Urine output (convert to binary)
--		226560, -- "Void"
--		227510, -- "TF Residual"
--		226561, -- "Condom Cath"
--		226584, -- "Ileoconduit"
--		226563, -- "Suprapubic"
--		226564, -- "R Nephrostomy"
--		226565, -- "L Nephrostomy"
--		226567, --	Straight Cath
--		226557, -- "R Ureteral Stent"
--		226558  -- "L Ureteral Stent"
		
	) and o.subject_id in (
		-- ids of patients admitted to hospital and stayed for at least 48 hours.
		select *
		from patient_ids
	) and extract( epoch from age( o.charttime, a.admittime )) between 0 and 172800

), procedure_events as (

	/***********************
	 * Procedure events - events for procedures administered to the patient (e.g. ventilation, X-rays, ...)
	 * 
	 * NOTE: numeric values observed are >= 0.
	 **********************/
	select p.subject_id, p.hadm_id, p.itemid, a.admittime, p.starttime as charttime, 0 as "var_type", (case when p.value is null or p.value <= 0 then 0 else 1 end) as val_num, 0 as val_min, 1 as val_max, 0 as ref_min, 0 as ref_max, 0 as val_default, a.hospital_expire_flag
	from mimic_core.admissions a join mimic_icu.procedureevents p
	on a.subject_id = p.subject_id 
	where p.hadm_id is not null
	and p.itemid in (
		
		-- interventions (convert to binary)
		225792,	225794,		-- using Ventilation (units/time)
		
		-- Foley Catheter (convert to binary)
		229351,				-- Foley Catheter (units/time)	
		
		-- diagnostics (binary). almost always value=1
		225402,				-- EKG (ElectroCardiogram).
		225432,				-- TTE (Transthoracic EchoCardiogram)
		225459, 229581,		-- Chest X-ray.  225459=Chest X-ray.  229581=Portable Chest X-ray. 221216=X-Ray
		225457, 			-- Abdominal X-ray
		221214, 229582,		-- CT Scan (head, neck, chest, and abdomen).  221214=CT Scan, 229582=Portable CT Scan
		221217,				-- UltraSound.
		225401				-- Blood Culture order 
		
	) and p.subject_id in (
		-- ids of patients admitted to hospital and stayed for at least 48 hours.
		select *
		from patient_ids
	) and extract( epoch from age( p.starttime, a.admittime )) between 0 and 172800

), results as (
	/*********************************
	 * MERGE subquery results
	 *********************************/
	(
		select pid as subject_id, vid as hadm_id, itemid, checkin as admittime, charted as charttime, var_type, val_num, val_min, val_max, ref_min, ref_max, val_default, hospital_expire_flag
		from val_defaults
	) union (
		select *
		from patient_chars
	) union (
		select *
		from labs
--	) union (
--		select *
--		from medications
	) union (
		select *
		from input_events
	) union (
		select *
		from output_events
	) union (
		select *
		from procedure_events
	) union (
		-- merge chartevents last because it's the largest set
		select *
		from chart_events
	)
)
select r.subject_id as patient_id, 
	r.hadm_id  as visit_id, 
	r.itemid   as event_id, 
	cast( (extract( epoch from age( r.charttime, r.admittime )) /  3600) as INT ) as "hour",
	r.var_type as var_type,
	r.val_num  as val_num,
	r.val_min  as val_min,
	r.val_max  as val_max,
	r.ref_min  as ref_min,
	r.ref_max  as ref_max,
	r.val_default as val_default,
	r.hospital_expire_flag as died
from results r
order by subject_id asc, charttime asc, hadm_id asc;


