/****************************************************************************
 * MIMIC-IV data extraction script for combining timelines to predict patient mortality
 * 
 * This script aggregates the necessary data comprising the clinical variables used in the timelines.
 * In many cases, the data must be converted to a different format (normalized to [0...1], for example).
 *
 * Not all clinical variables have significant representation, or are located in easy to access places within mimic.
 * Best guesses and compromises were employed when necessary.
 * 
 * For variables with many idiomatic representations, or requiring lots of special case code to handle,
 * data is dumped verbatim and left for the parser to figure out as other languages
 * may be more suited to the task than SQL.
 * 
 * Author: Matthew Lind
 * Date: April 23, 2022
 ****************************************************************************/
-- set schema
set search_path to mimic_iv;


with total_visits as (

	-- total number of hospital visits (523,740)
	select count(*)
	from mimic_core.admissions a
	
), visit_ids as (

	-- get all visits in ICU >= 48 hours
	select c.hadm_id 
	from mimic_derived.cohort c
	
), patient_ids as (

	-- get all patients elligible for the study
	select distinct a.subject_id 
	from mimic_derived.cohort a 
	where a.hadm_id in (
		select *
		from visit_ids
	)
	
), edstay_ids as (

	select distinct e.stay_id 
	from mimic_ed.edstays e 
	where e.hadm_id in (
		select *
		from visit_ids
	)
        
), val_defaults as (

	/*****************************************************************
	 * default values and reference ranges for clinical variables
	 * 
	 *         pid = patient id, uniquely identifies the patient.  patient id 0 defines the rules for the timelines.
	 *         rid = row id for pid=0 (e.g. row of image file where data should be written as a timeline.
	 *               For all other pids, rid is the visit_id within the patient's EHR.
	 *      itemid = identifies the clinical variable (e.g. heart rate, white blood cell count, ...)
	 *    var_type = type of data [0=binary, 1=continuous with min/max, 2=continuous with min/max normalized using ref_min, ref_max
	 *               For all other pids, it's the hour (column id) where data should be recorded in the timeline.
	 *     val_num = For pid=0, it's the mean average of the data for this clinical variable. 
	 *               For all other pids it's the value of recorded measurement for the clinical variable.
	 *     val_min = min acceptable value for this variable.  NOTE: there may be smaller values in the data.
	 *     val_max = max acceptable value for this variable.  NOTE: there may be larger values in the data.
	 *     ref_min = min value accepted as being within 'normal' range for the clinical variable.  
	 * 					NOTE: records with the same itemid can have different ref_min values.
	 *     ref_max = max value accepted as being within 'normal' range for the clinical variable.  
	 * 					NOTE: records with the same itemid can have different ref_max values.
	 * val_default = default (baseline) value for the clinical variable when creating the timeline.
	 *               val_default is a hand-picked value based on assessment of the data, medical literature, and intuition.  
	 *               Often it's similar to the mean average, but in cases where the mean average is skewed by outliers,
	 *               val_default compensates to better estimate the true mean average.
	 *****************************************************************/
	-- Patient characteristics --
	(		  select 0 pid, 0 rid, 0 itemid, 2 var_type, 0 val_num, 0 val_min, 91 val_max, 0 ref_min, 0 ref_max, 0 val_default 		-- age
	) union ( select 0 pid, 1 rid, 1 itemid, 0 var_type, 0 val_num, 0 val_min, 1  val_max, 0 ref_min, 0 ref_max, 0 val_default		-- sex/gender
	) union ( select 0 pid, 2 rid, 2 itemid, 0 var_type, 0 val_num, 0 val_min, 1  val_max, 0 ref_min, 0 ref_max, 0 val_default		-- ethnicity
	) union ( select 0 pid, 3 rid, 3 itemid, 0 var_type, 0 val_num, 0 val_min, 1  val_max, 0 ref_min, 0 ref_max, 0 val_default		-- previous cardiac arrest
	) union ( select 0 pid, 4 rid, 4 itemid, 0 var_type, 0 val_num, 0 val_min, 1  val_max, 0 ref_min, 0 ref_max, 0 val_default		-- prior admission to hospital within previous 90 days.
	) union ( select 0 pid, 5 rid, 5 itemid, 3 var_type, 0 val_num, 0 val_min, 23 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- hour of day
	) union ( select 0 pid, 6 rid, 6 itemid, 2 var_type, 0 val_num, 0 val_min, 41 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- patient location (was health severity/priority)
	-- vital signs (mimic_icu.chartevents)	
	) union ( select 0 pid, 7  rid, 223762 itemid, 2 var_type, 37.0  val_num, 27 val_min, 42  val_max, 36.1 ref_min,37.2 ref_max, 37   val_default		-- temperature C
	) union ( select 0 pid, 7  rid, 223761 itemid, 2 var_type, 98.6  val_num, 90 val_min, 110 val_max, 97   ref_min, 99  ref_max, 98.6 val_default		-- temperature F
	) union ( select 0 pid, 8  rid, 220045 itemid, 2 var_type, 86.25 val_num, 25 val_min, 230 val_max, 60   ref_min, 100 ref_max, 80   val_default		-- heart rate
	) union ( select 0 pid, 9  rid, 220210 itemid, 2 var_type, 20    val_num, 0  val_min, 60  val_max, 12   ref_min, 18  ref_max, 15   val_default		-- respiratory rate
	) union ( select 0 pid, 10 rid, 220179 itemid, 2 var_type, 120   val_num, 0  val_min, 180 val_max, 110  ref_min, 130 ref_max, 120  val_default		-- blood pressure, systolic 1
	) union ( select 0 pid, 10 rid, 220050 itemid, 2 var_type, 120   val_num, 0  val_min, 180 val_max, 110  ref_min, 130 ref_max, 120  val_default		-- blood pressure, systolic 2
	) union ( select 0 pid, 11 rid, 220180 itemid, 2 var_type, 70    val_num, 0  val_min, 120 val_max, 70   ref_min, 80  ref_max, 80   val_default		-- blood pressure, diastolic 1
	) union ( select 0 pid, 11 rid, 220051 itemid, 2 var_type, 70    val_num, 0  val_min, 120 val_max, 70   ref_min, 80  ref_max, 80   val_default		-- blood pressure, diastolic 2
	) union ( select 0 pid, 12 rid, 220277 itemid, 2 var_type, 97    val_num, 67 val_min, 100 val_max, 95   ref_min, 100 ref_max, 100  val_default		-- O2 saturation 1
	) union ( select 0 pid, 12 rid, 228232 itemid, 2 var_type, 97    val_num, 67 val_min, 100 val_max, 95   ref_min, 100 ref_max, 100  val_default		-- O2 saturation 2
	) union ( select 0 pid, 13 rid, 223835 itemid, 2 var_type, 49    val_num, 0  val_min, 100 val_max, 35   ref_min, 50  ref_max, 40   val_default		-- Fraction of inspired Oxygen (Fi02) - range and default are a guess
	) union ( select 0 pid, 14 rid, 226104 itemid, 2 var_type, 0     val_num, 0  val_min, 20  val_max, 0    ref_min, 0   ref_max, 0    val_default		-- Conscious level (AVPU)
	-- Laboratory cultures/ blood tests (mimic_hosp.labevents)
	-- Blood metabolic panel --
	) union ( select 0 pid, 15 rid, 50983 itemid, 2 var_type, 138.591 val_num, 67 val_min, 185 val_max, 133 ref_min, 145  ref_max, 140  val_default		-- Sodium
	) union ( select 0 pid, 16 rid, 50971 itemid, 2 var_type, 4.188   val_num, 0  val_min, 26  val_max, 3.3 ref_min, 5.4  ref_max, 4.25 val_default		-- Potassium
	) union ( select 0 pid, 17 rid, 50882 itemid, 2 var_type, 25.510  val_num, 0  val_min, 132 val_max, 22  ref_min, 32   ref_max, 26   val_default		-- Bicarbonate (CO2)
	) union ( select 0 pid, 18 rid, 50868 itemid, 2 var_type, 14.236  val_num, 0  val_min, 91  val_max, 8   ref_min, 20   ref_max, 14   val_default		-- Anion Gap
	) union ( select 0 pid, 19 rid, 50931 itemid, 2 var_type, 127.467 val_num, 0  val_min, 400 val_max, 70  ref_min, 105  ref_max, 111  val_default		-- Glucose 1
	) union ( select 0 pid, 19 rid, 50809 itemid, 2 var_type, 127.467 val_num, 0  val_min, 400 val_max, 70  ref_min, 105  ref_max, 111  val_default		-- Glucose 2
	) union ( select 0 pid, 20 rid, 50893 itemid, 2 var_type, 8.791   val_num, 0  val_min, 132 val_max, 8.4 ref_min, 10.3 ref_max, 9    val_default		-- Calcium
	) union ( select 0 pid, 21 rid, 51006 itemid, 2 var_type, 23.866  val_num, 0  val_min, 200 val_max, 6   ref_min, 20   ref_max, 18   val_default		-- Blood Urea Nitrogen (BUN) 1
	) union ( select 0 pid, 21 rid, 52647 itemid, 2 var_type, 23.866  val_num, 0  val_min, 200 val_max, 6   ref_min, 20   ref_max, 18   val_default		-- Blood Urea Nitrogen (BUN) 2
	) union ( select 0 pid, 22 rid, 50912 itemid, 2 var_type, 1.329   val_num, 0  val_min, 20  val_max, 0.45 ref_min,1.15 ref_max, 0    val_default		-- Serum Creatinine (SCr)
	) union ( select 0 pid, 23 rid, 11111 itemid, 2 var_type, 0       val_num, 0  val_min, 30  val_max, 10  ref_min, 20   ref_max, 0    val_default		-- BUN / SCr ratio
	) union ( select 0 pid, 24 rid, 50970 itemid, 2 var_type, 3.555   val_num, 0  val_min, 50  val_max, 2.7 ref_min, 4.5  ref_max, 3.45 val_default		-- Phosphate
	-- LiverFunction Test -- (mimic_hosp.labevents)
	) union ( select 0 pid, 25 rid, 50976 itemid, 2 var_type, 6.838  val_num, 0 val_min, 19  val_max, 6.4 ref_min, 8.3 ref_max, 6.85 val_default		-- Total Protein
	) union ( select 0 pid, 26 rid, 50862 itemid, 2 var_type, 3.782  val_num, 0 val_min, 36  val_max, 3.5 ref_min, 5.2 ref_max, 3.85 val_default		-- Albumin
	) union ( select 0 pid, 27 rid, 50885 itemid, 2 var_type, 2.022  val_num, 0 val_min, 87  val_max, 0   ref_min, 1.5 ref_max, 1.25 val_default		-- Total Bilirubin
	) union ( select 0 pid, 28 rid, 50878 itemid, 2 var_type, 34.952 val_num, 0 val_min, 150 val_max, 0   ref_min, 40  ref_max, 30.5 val_default		-- AST (SGOT)
	) union ( select 0 pid, 29 rid, 50863 itemid, 2 var_type, 91.136 val_num, 0 val_min, 200 val_max, 40  ref_min, 115 ref_max, 86   val_default		-- Alkaline Phosphatase
	-- Complete Blood Count (CBC) --- (mimic_hosp.labevents)
	) union ( select 0 pid, 30 rid, 51300 itemid, 2 var_type, 8.784   val_num, 0 val_min, 200  val_max, 4    ref_min, 11   ref_max, 8.25 val_default	-- White blood Cells (WBC) 1
	) union ( select 0 pid, 30 rid, 51301 itemid, 2 var_type, 8.784   val_num, 0 val_min, 200  val_max, 4    ref_min, 11   ref_max, 8.25 val_default	-- White blood Cells (WBC) 2
	) union ( select 0 pid, 31 rid, 51222 itemid, 2 var_type, 11.068  val_num, 0 val_min, 98   val_max, 13.7 ref_min, 17.5 ref_max, 11.5 val_default	-- Hemoglobin 1
	) union ( select 0 pid, 31 rid, 50811 itemid, 2 var_type, 11.068  val_num, 0 val_min, 98   val_max, 12   ref_min, 18   ref_max, 11.5 val_default	-- Hemoglobin 2
	) union ( select 0 pid, 32 rid, 51265 itemid, 2 var_type, 232.658 val_num, 0 val_min, 3000 val_max, 150  ref_min, 440  ref_max, 226  val_default	-- Platelet Count
	-- Other Labs -- (mimic_hosp.labevents)
	) union ( select 0 pid, 33 rid, 50813 itemid, 2 var_type, 2.269   val_num, 0 val_min, 132  val_max, 0.5  ref_min, 2    ref_max, 2.05 val_default	-- Lactate 
	) union ( select 0 pid, 34 rid, 51002 itemid, 2 var_type, 0.462   val_num, 0 val_min, 20   val_max, 0    ref_min, 0.01 ref_max, 0.27 val_default	-- Troponin I (no results)
	) union ( select 0 pid, 34 rid, 51003 itemid, 2 var_type, 0.462   val_num, 0 val_min, 20   val_max, 0    ref_min, 0.01 ref_max, 0.27 val_default	-- Troponin T
	) union ( select 0 pid, 35 rid, 50820 itemid, 2 var_type, 7.372   val_num, 0 val_min, 9    val_max, 7.35 ref_min, 7.45 ref_max, 7.4  val_default	-- pH (blood)
	) union ( select 0 pid, 36 rid, 51984 itemid, 2 var_type, 38.43   val_num, 0 val_min, 160  val_max, 0    ref_min, 0    ref_max, 0    val_default	-- Ketones 
	) union ( select 0 pid, 37 rid, 50902 itemid, 2 var_type, 0       val_num, 0 val_min, 200  val_max, 115  ref_min, 120  ref_max, 0    val_default	-- Chloride 
	) union ( select 0 pid, 38 rid, 51237 itemid, 2 var_type, 1.614   val_num, 0 val_min, 27.5 val_max, 0.9  ref_min, 1.1  ref_max, 1.45 val_default	-- International Normalized Ration (INR)  1
	) union ( select 0 pid, 38 rid, 51675 itemid, 2 var_type, 1.614   val_num, 0 val_min, 27.5 val_max, 0.9  ref_min, 1.1  ref_max, 1.45 val_default	-- International Normalized Ration (INR)  2
	) union ( select 0 pid, 39 rid, 50956 itemid, 2 var_type, 48.835  val_num, 0 val_min, 300  val_max, 0    ref_min, 60   ref_max, 38.5 val_default	-- Lipase
	) union ( select 0 pid, 40 rid, 51250 itemid, 2 var_type, 90.945  val_num, 0 val_min, 161  val_max, 80   ref_min, 100  ref_max, 91   val_default	-- Mean Corpuscular Volume (MCV)
	) union ( select 0 pid, 41 rid, 50818 itemid, 2 var_type, 43.335  val_num, 0 val_min, 246  val_max, 35   ref_min, 45   ref_max, 42   val_default	-- Partial pressure carbon dioxide (PaCO2)
	) union ( select 0 pid, 42 rid, 50821 itemid, 2 var_type, 126.086 val_num, 0 val_min, 600  val_max, 85   ref_min, 105  ref_max, 100  val_default	-- Partial pressure Oxygen (PaO2)
	) union ( select 0 pid, 43 rid, 51275 itemid, 2 var_type, 42.579  val_num, 0 val_min, 200  val_max, 25   ref_min, 36.5 ref_max, 36   val_default	-- Partial Thromboplastin Time (PTT)
	) union ( select 0 pid, 44 rid, 51277 itemid, 2 var_type, 15.176  val_num, 0 val_min, 161  val_max, 10.5 ref_min, 15.5 ref_max, 14.8 val_default	-- Red Cell Distribution Width (RDW)
	-- Interventions --
	) union ( select 0 pid, 45 rid, 25955  itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Dialysis (SCUF)
	) union ( select 0 pid, 45 rid, 225802 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Dialysis (CRRT)	
	) union ( select 0 pid, 45 rid, 225803 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Dialysis (CVVHD)
	) union ( select 0 pid, 45 rid, 225805 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Dialysis (Peritoneal Dialysis)
	) union ( select 0 pid, 45 rid, 225809 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Dialysis (CVVHDF)
	) union ( select 0 pid, 45 rid, 225441 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Dialysis (HemoDialysis)
	) union ( select 0 pid, 46 rid, 225828 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- IV Bolus - 0.9% Sodium Chloride / Normal Saline
	) union ( select 0 pid, 46 rid, 225158 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- IV Bolus - Lactated Ringers
	) union ( select 0 pid, 47 rid, 220864 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Albumin 5%
	) union ( select 0 pid, 47 rid, 220862 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Albumin 25%
	) union ( select 0 pid, 48 rid, 225792 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Using Ventilator (Invasive)
	) union ( select 0 pid, 48 rid, 225794 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Using Ventilator (Non-invasive)
	) union ( select 0 pid, 49 rid, 227579 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Using BiPAP (EPAP)
	) union ( select 0 pid, 49 rid, 227580 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Using BiPAP (IPAP)
	) union ( select 0 pid, 49 rid, 227581 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Using BiPAP (bipap bpm (S/T backup)
	) union ( select 0 pid, 49 rid, 227582 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Using BiPAP (O2 flow)
	) union ( select 0 pid, 50 rid, 227583 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Using CPAP (constant positive air pressure)
	) union ( select 0 pid, 51 rid, 227287 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Using HFNC (High Flow Nasal Cannula)
	) union ( select 0 pid, 52 rid, 226169 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Using Suction
	-- Transfusions
	) union ( select 0 pid, 53 rid, 225168 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Red Blood Cells (RBC) transfusion
	) union ( select 0 pid, 54 rid, 220970 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Fresh Frozen Plasma (FFP) transfusion
	) union ( select 0 pid, 55 rid, 225170 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Platelet transfusion
	) union ( select 0 pid, 56 rid, 225171 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Cryoprecipitate transfusion
	-- Medications --
	) union ( select 0 pid, 57 rid, 10001 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Nebulizer Treatments
	) union ( select 0 pid, 58 rid, 10002 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- IV/SC Hypoglycemics
	) union ( select 0 pid, 59 rid, 10003 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- PO Hypoglycemics
	) union ( select 0 pid, 60 rid, 10004 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Drip Hypoglycemics
	) union ( select 0 pid, 61 rid, 10005 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Lactulose
	) union ( select 0 pid, 62 rid, 10006 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- IV AV Nodal Blockers
	) union ( select 0 pid, 63 rid, 10007 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- PO AV Nodal Blockers
	) union ( select 0 pid, 64 rid, 10008 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- IV Antiarrhythmic
	) union ( select 0 pid, 65 rid, 10009 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- PO Antiarrhythmic
	) union ( select 0 pid, 66 rid, 10010 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Anti Seizures
	) union ( select 0 pid, 67 rid, 10011 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- IV Anticoagulants
	) union ( select 0 pid, 68 rid, 10012 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- IV Steroids
	) union ( select 0 pid, 69 rid, 10013 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- PO Steroid
	) union ( select 0 pid, 70 rid, 10014 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- IV Immunotherapy
	) union ( select 0 pid, 71 rid, 10015 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- PO Immunotherapy
	) union ( select 0 pid, 72 rid, 10016 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- IV AntiPsychotics
	) union ( select 0 pid, 73 rid, 10017 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- PO AntiPsychotics
	) union ( select 0 pid, 74 rid, 10018 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Sedative Drips
	) union ( select 0 pid, 75 rid, 10019 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- IV Benzodiazepine
	) union ( select 0 pid, 76 rid, 10020 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- PO Benzodiazepine
	) union ( select 0 pid, 77 rid, 10021 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Vasopressors
	) union ( select 0 pid, 78 rid, 10022 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Inotropes
	) union ( select 0 pid, 79 rid, 10023 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- IV Diuretics
	) union ( select 0 pid, 80 rid, 10024 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- PO Diuretics
	) union ( select 0 pid, 81 rid, 10025 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default		-- Antibiotics
	-- Examinations --
	) union ( select 0 pid, 82 rid, 10026 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default		-- Cardiac Paced
	) union ( select 0 pid, 83 rid, 10027 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default		-- Atrial Fibrillation
	) union ( select 0 pid, 84 rid, 10028 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default		-- Atrial Flutter
	) union ( select 0 pid, 85 rid, 10029 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default		-- Using? (not sure what this is)
	) union ( select 0 pid, 86 rid, 10030 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default		-- Superventricular SVT
	) union ( select 0 pid, 87 rid, 10031 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default		-- VT
	) union ( select 0 pid, 88 rid, 10032 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default		-- VF
	) union ( select 0 pid, 89 rid, 10033 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default		-- Asystole
	) union ( select 0 pid, 90 rid, 10034 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default		-- Heart Block
	) union ( select 0 pid, 91 rid, 10035 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 1 ref_max, 0 val_default		-- Junctional Rhythm
	-- Braden scores
	) union ( select 0 pid, 92 rid, 224054 itemid, 2 var_type, 0 val_num, 0 val_min, 4 val_max, 4 ref_min, 4 ref_max, 4 val_default		-- Braden Sensory Perception
	) union ( select 0 pid, 93 rid, 224055 itemid, 2 var_type, 0 val_num, 0 val_min, 4 val_max, 4 ref_min, 4 ref_max, 4 val_default		-- Braden Moisture
	) union ( select 0 pid, 94 rid, 224056 itemid, 2 var_type, 0 val_num, 0 val_min, 4 val_max, 4 ref_min, 4 ref_max, 4 val_default		-- Braden Activity
	) union ( select 0 pid, 95 rid, 224057 itemid, 2 var_type, 0 val_num, 0 val_min, 4 val_max, 4 ref_min, 4 ref_max, 4 val_default		-- Braden Mobility
	) union ( select 0 pid, 96 rid, 224058 itemid, 2 var_type, 0 val_num, 0 val_min, 4 val_max, 4 ref_min, 4 ref_max, 4 val_default		-- Braden Nutrition
	) union ( select 0 pid, 97 rid, 224059 itemid, 2 var_type, 0 val_num, 0 val_min, 3 val_max, 3 ref_min, 3 ref_max, 3 val_default		-- Braden Friction/Shear
	) union ( select 0 pid, 98 rid, 8      itemid, 2 var_type, 0 val_num, 0 val_min,23 val_max,18 ref_min,23 ref_max, 0 val_default		-- Braden Cumulative Total
	--	Morse Fall risk scale
	) union ( select 0 pid, 99  rid, 227341 itemid, 2 var_type, 0 val_num, 0 val_min, 25  val_max, 0 ref_min, 0  ref_max, 0 val_default	-- Morse, patient has history of falling?
	) union ( select 0 pid, 100 rid, 227342 itemid, 2 var_type, 0 val_num, 0 val_min, 15  val_max, 0 ref_min, 0  ref_max, 0 val_default	-- Morse, patient has secondary diagnosis?
	) union ( select 0 pid, 101 rid, 227343 itemid, 2 var_type, 0 val_num, 0 val_min, 30  val_max, 0 ref_min, 0  ref_max, 0 val_default	-- Morse, patient use ambulatory aid?
	) union ( select 0 pid, 102 rid, 227344 itemid, 2 var_type, 0 val_num, 0 val_min, 20  val_max, 0 ref_min, 0  ref_max, 0 val_default	-- Morse, patient receiving IV therapy or Heparin Lock?
	) union ( select 0 pid, 103 rid, 227345 itemid, 2 var_type, 0 val_num, 0 val_min, 20  val_max, 0 ref_min, 0  ref_max, 0 val_default	-- Morse, how is patient's gait?
	) union ( select 0 pid, 104 rid, 227346 itemid, 2 var_type, 0 val_num, 0 val_min, 15  val_max, 0 ref_min, 0  ref_max, 0 val_default	-- Morse, what is patient's mental status?
	) union ( select 0 pid, 105 rid, 227348 itemid, 0 var_type, 0 val_num, 0 val_min, 1   val_max, 0 ref_min, 0  ref_max, 0 val_default	-- Morse, is patient low risk?  NOTE: not included in cumulative score
	) union ( select 0 pid, 106 rid, 227349 itemid, 0 var_type, 0 val_num, 0 val_min, 1   val_max, 0 ref_min, 0  ref_max, 0 val_default	-- Morse, is patient high risk? NOTE: not included in cumulative score.
	) union ( select 0 pid, 107 rid, 9      itemid, 2 var_type, 0 val_num, 0 val_min, 125 val_max, 0 ref_min, 25 ref_max, 0 val_default	-- Morse, cumulative score
	-- Diagnostics / Urinary
	) union ( select 0 pid, 108 rid, 225402 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- EKG
	) union ( select 0 pid, 109 rid, 225432 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- TTE
	) union ( select 0 pid, 110 rid, 225459 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- Chest X-ray
	) union ( select 0 pid, 110 rid, 229581 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- Chest X-ray (portable)
	) union ( select 0 pid, 111 rid, 225457 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- Abdomen X-ray
	) union ( select 0 pid, 112 rid, 221214 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- CT Scan (head, neck, chest, and abdomen)
	) union ( select 0 pid, 112 rid, 229582 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- CT Scan (head, neck, chest, and abdomen - portable
	) union ( select 0 pid, 113 rid, 221217 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- Ultrasound
	) union ( select 0 pid, 114 rid, 225401 itemid, 4 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- Blood Culture Order
	) union ( select 0 pid, 115 rid, 226627 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- Urine, OR Urine
	) union ( select 0 pid, 115 rid, 226631 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- Urine, PACU Urine
	) union ( select 0 pid, 115 rid, 227489 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- Urine, U Irrigant/Urine Volume Out
	) union ( select 0 pid, 116 rid, 229351 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- Foley Catheter Placed
	) union ( select 0 pid, 116 rid, 226559 itemid, 0 var_type, 0 val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default	-- Foley Catheter output
	)
	
), emar_actions as (

	-- medication event descriptions

	(         select 0 active, ''                                          med_action
	) union ( select 1 active, 'Administered'                              med_action
	) union ( select 1 active, 'Administered Bolus from IV Drip'           med_action
	) union ( select 1 active, 'Administered in Other Location'            med_action
	) union ( select 1 active, 'Applied'                                   med_action
	) union ( select 1 active, 'Applied in Other Location'                 med_action
	) union ( select 1 active, 'Assessed'                                  med_action
	) union ( select 1 active, 'Assessed in Other Location'                med_action
	) union ( select 1 active, 'Confirmed'                                 med_action
	) union ( select 1 active, 'Confirmed in Other Location'               med_action
	) union ( select 0 active, 'Delayed '                                  med_action	/* NOTE: trailing space is part of the label */
	) union ( select 0 active, 'Delayed Administered'                      med_action
	) union ( select 0 active, 'Delayed Applied'                           med_action
	) union ( select 0 active, 'Delayed Assessed'                          med_action
	) union ( select 0 active, 'Delayed Confirmed'                         med_action
	) union ( select 0 active, 'Delayed Flushed'                           med_action
	) union ( select 0 active, 'Delayed Not Applied'                       med_action
	) union ( select 0 active, 'Delayed Not Assessed'                      med_action
	) union ( select 0 active, 'Delayed Not Confirmed'                     med_action
	) union ( select 0 active, 'Delayed Not Flushed'                       med_action
	) union ( select 0 active, 'Delayed Not Removed'                       med_action
	) union ( select 0 active, 'Delayed Not Started'                       med_action
	) union ( select 1 active, 'Delayed Not Stopped'                       med_action
	) union ( select 1 active, 'Delayed Rate Change'                       med_action
	) union ( select 1 active, 'Delayed Removed'                           med_action
	) union ( select 0 active, 'Delayed Restarted'                         med_action
	) union ( select 0 active, 'Delayed Started'                           med_action
	) union ( select 1 active, 'Delayed Stopped'                           med_action
	) union ( select 1 active, 'Delayed Stopped As Directed'               med_action
	) union ( select 0 active, 'Documented in O.R. Holding'                med_action
	) union ( select 1 active, 'Flushed'                                   med_action
	) union ( select 1 active, 'Flushed in Other Location'                 med_action
	) union ( select 0 active, 'Hold Dose'                                 med_action
	) union ( select 0 active, 'Infusion Reconciliation'                   med_action
	) union ( select 0 active, 'Infusion Reconciliation in Other Location' med_action
	) union ( select 0 active, 'Infusion Reconciliation Not Done'          med_action
	) union ( select 1 active, 'in Other Location'                         med_action
	) union ( select 0 active, 'Not Applied'                               med_action
	) union ( select 0 active, 'Not Assessed'                              med_action
	) union ( select 0 active, 'Not Confirmed'                             med_action
	) union ( select 0 active, 'Not Flushed'                               med_action
	) union ( select 0 active, 'Not Given'                                 med_action
	) union ( select 0 active, 'Not Given per Sliding Scale'               med_action
	) union ( select 0 active, 'Not Given per Sliding Scale in Other Location' med_action
	) union ( select 0 active, 'Not Read'                                  med_action
	) union ( select 1 active, 'Not Removed'                               med_action
	) union ( select 0 active, 'Not Started'                               med_action
	) union ( select 0 active, 'Not Started per Sliding Scale'             med_action
	) union ( select 1 active, 'Not Stopped'                               med_action
	) union ( select 1 active, 'Not Stopped per Sliding Scale'             med_action
	) union ( select 1 active, 'Partial '                                  med_action
	) union ( select 1 active, 'Partial Administered'                      med_action
	) union ( select 1 active, 'Rate Change'                               med_action
	) union ( select 1 active, 'Rate Change in Other Location'             med_action
	) union ( select 1 active, 'Read'                                      med_action
	) union ( select 1 active, 'Read in Other Location'                    med_action
	) union ( select 0 active, 'Removed'                                   med_action
	) union ( select 1 active, 'Removed Existing / Applied New'            med_action
	) union ( select 1 active, 'Removed Existing / Applied New in Other Location' med_action
	) union ( select 1 active, 'Removed in Other Location'                 med_action
	) union ( select 0 active, 'Removed - Unscheduled'                     med_action
	) union ( select 1 active, 'Restarted'                                 med_action
	) union ( select 1 active, 'Restarted in Other Location'               med_action
	) union ( select 1 active, 'Started'                                   med_action
	) union ( select 1 active, 'Started in Other Location'                 med_action
	) union ( select 0 active, 'Stopped'                                   med_action
	) union ( select 0 active, 'Stopped As Directed'                       med_action
	) union ( select 0 active, 'Stopped in Other Location'                 med_action
	) union ( select 0 active, 'Stopped - Unscheduled'                     med_action
	) union ( select 0 active, 'Stopped - Unscheduled in Other Location'   med_action
	) union ( select 1 active, 'TPN Rate Not Changed'                      med_action
	)
	
), hosp_location as (

	(         select 0  ward_id, 'Unknown'                                          ward_name
	) union ( select 1  ward_id, 'Cardiac Surgery'                                  ward_name
	) union ( select 2  ward_id, 'Cardiac Vascular Intensive Care Unit (CVICU)'     ward_name
	) union ( select 3  ward_id, 'Cardiology'                                       ward_name
	) union ( select 4  ward_id, 'Cardiology Surgery Intermediate'                  ward_name
	) union ( select 5  ward_id, 'Coronary Care Unit (CCU)'                         ward_name
	) union ( select 6  ward_id, 'Emergency Department'                             ward_name
	) union ( select 7  ward_id, 'Emergency Department Observation'                 ward_name
	) union ( select 8  ward_id, 'Hematology/Oncology'                              ward_name
	) union ( select 9  ward_id, 'Hematology/Oncology Intermediate'                 ward_name
	) union ( select 10 ward_id, 'Labor & Delivery'                                 ward_name
	) union ( select 11 ward_id, 'Medical Intensive Care Unit (MICU)'               ward_name
	) union ( select 12 ward_id, 'Medical/Surgical (Gynecology)'                    ward_name
	) union ( select 13 ward_id, 'Medical/Surgical Intensive Care Unit (MICU/SICU)' ward_name
	) union ( select 14 ward_id, 'Medicine'                                         ward_name
	) union ( select 15 ward_id, 'Medicine/Cardiology'                              ward_name
	) union ( select 16 ward_id, 'Medicine/Cardiology Intermediate'                 ward_name
	) union ( select 17 ward_id, 'Med/Surg'                                         ward_name
	) union ( select 18 ward_id, 'Med/Surg/GYN'                                     ward_name
	) union ( select 19 ward_id, 'Med/Surg/Trauma'                                  ward_name
	) union ( select 20 ward_id, 'Neonatal Intensive Care Unit (NICU)'              ward_name
	) union ( select 21 ward_id, 'Neuro Intermediate'                               ward_name
	) union ( select 22 ward_id, 'Neurology'                                        ward_name
	) union ( select 23 ward_id, 'Neuro Stepdown'                                   ward_name
	) union ( select 24 ward_id, 'Neuro Surgical Intensive Care Unit (Neuro SICU)'  ward_name
	) union ( select 25 ward_id, 'Nursery - Well Babies'                            ward_name
	) union ( select 26 ward_id, 'Observation'                                      ward_name
	) union ( select 27 ward_id, 'Obstetrics Antepartum'                            ward_name
	) union ( select 28 ward_id, 'Obstetrics Postpartum'                            ward_name
	) union ( select 29 ward_id, 'Obstetrics (Postpartum & Antepartum)'             ward_name
	) union ( select 30 ward_id, 'PACU'                                             ward_name
	) union ( select 31 ward_id, 'Psychiatry'                                       ward_name
	) union ( select 32 ward_id, 'Special Care Nursery (SCN)'                       ward_name
	) union ( select 33 ward_id, 'Surgery'                                          ward_name
	) union ( select 34 ward_id, 'Surgery/Pancreatic/Biliary/Bariatric'             ward_name
	) union ( select 35 ward_id, 'Surgery/Trauma'                                   ward_name
	) union ( select 36 ward_id, 'Surgery/Vascular/Intermediate'                    ward_name
	) union ( select 37 ward_id, 'Surgical Intensive Care Unit (SICU)'              ward_name
	) union ( select 38 ward_id, 'Thoracic Surgery'                                 ward_name
	) union ( select 39 ward_id, 'Transplant'                                       ward_name
	) union ( select 40 ward_id, 'Trauma SICU (TSICU)'                              ward_name
	) union ( select 41 ward_id, 'Vascular'                                         ward_name
	)
	
), patient_gender as (

	(         select 'M' gender_name, 0 gender_id
	) union ( select 'F' gender_name, 1 gender_id
	)
	
), patient_ethnicity as ( 

	(         select 'AMERICAN INDIAN/ALASKA NATIVE' ethnicity_name, 0 ethnicity_id	
	) union ( select 'ASIAN'                         ethnicity_name, 0 ethnicity_id 	
	) union ( select 'BLACK/AFRICAN AMERICAN'        ethnicity_name, 1 ethnicity_id 
 	) union ( select 'HISPANIC/LATINO'               ethnicity_name, 0 ethnicity_id 
 	) union ( select 'OTHER'                         ethnicity_name, 0 ethnicity_id 	
	) union ( select 'UNABLE TO OBTAIN'              ethnicity_name, 0 ethnicity_id  
	) union ( select 'UNKNOWN'                       ethnicity_name, 0 ethnicity_id 	
	) union ( select 'WHITE'                         ethnicity_name, 0 ethnicity_id
	)

), patient_chars as (

	/**********************************************
	 * Patient characteristics - age, sex, race, ...
	 **********************************************/
	with patient_history as ( 
		-- 
		select a.subject_id, a.hadm_id, a.admittime, a.admittime as charttime, p.anchor_age, p.gender, (extract( hour from a.admittime)) as "hour", a.ethnicity, a.hospital_expire_flag 
		from mimic_core.patients p join mimic_core.admissions a
		on p.subject_id = a.subject_id 
		where a.hadm_id in ( 
			select *
			from visit_ids
		)
		
	), p_items as (
	
		-- build characteristics
		( 
			-- age 
			select pp.subject_id, pp.hadm_id, 0 as itemid, pp.admittime, pp.charttime, pp.anchor_age as val_num, pp.hospital_expire_flag
			from patient_history pp
		) union ( 
			-- sex/gender
			select pp.subject_id, pp.hadm_id, 1 as itemid, pp.admittime, pp.charttime, g.gender_id as val_num, pp.hospital_expire_flag
			from patient_history pp	join patient_gender g 
			on pp.gender = g.gender_name
			where g.gender_id > 0
		) union (
			-- ethnicity
			select pp.subject_id, pp.hadm_id, 2 as itemid, pp.admittime, pp.charttime, e.ethnicity_id as val_num, pp.hospital_expire_flag
			from patient_history pp	join patient_ethnicity e 
			on pp.ethnicity = e.ethnicity_name
			where e.ethnicity_id > 0
		) union (
			-- prior history of cardiac arrest (experienced in ICU)
			select a.subject_id, a.hadm_id, 3 as itemid, a.admittime, a.admittime as charttime, 1 as val_num, a.hospital_expire_flag 
			from mimic_derived.cohort a join mimic_icu.procedureevents p 
			on a.subject_id = p.subject_id
			where p.value is not null
			and p.itemid = 225466 
			and a.subject_id in (
				-- need to check patient's entire history, not just admissions
				select *
				from patient_ids
			)		
			and extract( epoch from age( a.admittime, p.starttime )) >= 0
		
		) union (
			-- prior hospital admissions within past 90 days (this could certainly be optimized)
		
			with tmp as (
			
				-- get patient data from admissions table. Convert admittime to epoch time for easier math
				select a.subject_id, a.hadm_id, a.admittime, extract( epoch from a.admittime ) as intime, extract( epoch from a.dischtime ) as outtime, a.hospital_expire_flag 
				from mimic_derived.cohort a 
				where a.hadm_id in (
					select *
					from visit_ids
				)
				
			), time_diff as (
			
				-- compute difference between first day of current admission and last day of previous admission, for same patient
				-- time is represented as number of seconds since the epoch.  1 day = 24 hours = 1440 minutes = 86400 seconds.
				select t.subject_id, t.hadm_id, t.admittime,
--					lag( t.outtime ) over ( partition by t.subject_id order by t.outtime ) as prev_time,
					-- NOTE: subtracting 90 here so downstream comparisons only need to check > 0.
					floor( (t.intime - lag( t.outtime ) over ( partition by t.subject_id order by t.intime )) / 86400) - 90 as diff,
					t.hospital_expire_flag
				from tmp t
			)
			-- assess results and flag all prior admissions within 90 days
			select t.subject_id, t.hadm_id, 4 as itemid, t.admittime, t.admittime as charttime, 1 as val_num, t.hospital_expire_flag
			from time_diff t
			where t.diff > 0
			
		) union (
			-- hour of day.  compute hour of day in military time upon admission to hospital.  
			-- This must be incremented hourly for first 48 hours of the visit.
			select p.subject_id, p.hadm_id, 5 as itemid, p.admittime, p.charttime, p.hour as val_num, p.hospital_expire_flag
			from patient_history p
		
		) union (
			-- patient location
			with hosp_transfers as (
				-- join transfers to hosp_location to convert careunit to an numeric value
				select t.subject_id, t.hadm_id, t.intime, h.ward_id
				from mimic_core.transfers t join hosp_location h 
				on t.careunit = h.ward_name
				where t.hadm_id in ( 
					select *
					from visit_ids
				)
				and t.eventtype <> 'discharge'
			)
			select a.subject_id, a.hadm_id, 6 as itemid, a.admittime, ht.intime as charttime, ht.ward_id as val_num, a.hospital_expire_flag 
			from mimic_derived.cohort a join hosp_transfers ht 
			on a.hadm_id = ht.hadm_id
--			where a.hadm_id in ( 
--				select *
--				from visit_ids
--			)
			where extract( epoch from age( ht.intime, a.admittime )) between 0 and a.icu_limit
		)
	)
	-- merge with val_defaults to inherit variable definitions
	select p.subject_id, p.hadm_id, p.itemid, p.admittime, p.charttime, v.var_type, p.val_num, v.val_min, v.val_max, v.ref_min, v.ref_max, v.val_default, p.hospital_expire_flag, p.admittime as time_in, 0 as gap
	from p_items p join val_defaults v 
	on p.itemid = v.itemid
	
		-- patient severity/priority (how serious is the situation based on where they checked into the hospital)
--	) union (
--		-- patient admission reason.  Used in place of patient location.
--		select p.subject_id, a.hadm_id, 6 as itemid, a.admittime, a.admittime as charttime, 2 as var_type, 
--		(case 
--			when a.admission_type = 'ELECTIVE'               then 1
--			when a.admission_type = 'OBSERVATION ADMIT'      then 2
--			when a.admission_type = 'DIRECT OBSERVATION'     then 3
--			when a.admission_type = 'AMBULATORY OBSERVATION' then 4
--			when a.admission_type = 'EU OBSERVATION'         then 5
--			when a.admission_type = 'SURGICAL SAME DAY ADMISSION' then 6
--			when a.admission_type = 'URGENT'                 then 7
--			when a.admission_type = 'DIRECT EMER.'           then 8
--			when a.admission_type = 'EW EMER.'               then 9
--			else 0 end
--		) as val_num, 0 as val_min, 9 as val_max, 1 as ref_min, 9 as ref_max, 0 as val_default, a.hospital_expire_flag
--		from mimic_derived.cohort a join mimic_core.patients p 
--		on a.subject_id = p.subject_id 
--		and a.hadm_id in (
--			select *
--			from visit_ids
--		)
	
), labs as (

	/****************************************************
	 * Labs - recorded events for blood tests, urine, cultures, ...
	 *****************************************************/
	with lab_values as (
	
		(
			-- special case: 51484=ketones (urine).  
			-- Many of the records have NULL valuenum and reference ranges.  
			-- Must explicitly cast to comply with everything else downstream
			select l.subject_id, l.hadm_id, l.itemid, a.admittime, l.charttime, (case when l.valuenum is null then 0 else l.valuenum end) as valuenum, 0 as ref_min, 0 as ref_max, a.hospital_expire_flag, a.time_in, a.gap
			from mimic_derived.cohort a join mimic_hosp.labevents l
			on a.subject_id = l.subject_id 
			where l.hadm_id is not null
			and l.itemid = 51484		-- Ketones (Urine).
			and l.hadm_id in (
				select *
				from visit_ids
			) 
			and extract( epoch from age( l.charttime, a.admittime )) between 0 and a.icu_limit
			
		) union (
		
			select l.subject_id, l.hadm_id, l.itemid, a.admittime, l.charttime, (case when l.valuenum is null then 0 else l.valuenum end) as valuenum, l.ref_range_lower as ref_min, l.ref_range_upper as ref_max, a.hospital_expire_flag, a.time_in, a.gap
			from mimic_derived.cohort a join mimic_hosp.labevents l
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
				
			) and l.hadm_id in (
				select *
				from visit_ids
			) and extract( epoch from age( l.charttime, a.admittime )) between 0 and a.icu_limit
		)
	)
	select v.subject_id, v.hadm_id, v.itemid, v.admittime, v.charttime, d.var_type, v.valuenum as val_num, d.val_min, d.val_max, v.ref_min, v.ref_max, d.val_default, v.hospital_expire_flag, v.time_in, v.gap
	from lab_values v join val_defaults d 
	on v.itemid = d.itemid
	
), medications as (

	/****************************************************
	 * Medications - find medications given to the patient
	 *****************************************************/
	with med_codes as (
		--
		-- Lookup table mapping drug product_code to desired itemid
		-- NOTE: a product_code may map to multiple variations of the medication (generic vs brand, formulation, ...)
		--
		(         select 0 itemid, 'Unknown'         med_code
		-- Nebulizer treatments 
		) union ( select 10001 itemid, 'ALBU3H'      med_code	-- albuterol
		) union ( select 10001 itemid, 'IPAL3H'      med_code
		) union ( select 10001 itemid, 'IPRA2H'      med_code
		) union ( select 10001 itemid, 'BUDE0.5'     med_code
		) union ( select 10001 itemid, 'BUDE0.25'    med_code
		) union ( select 10001 itemid, 'LEVA0.63L'   med_code
		) union ( select 10001 itemid, 'SODI3N'      med_code
		
		-- IV/SC Hypoglycemics
		) union ( select 10002 itemid, 'GLUC1000I'   med_code	-- glucagon
		) union ( select 10002 itemid, 'GLUC1I'      med_code
		) union ( select 10002 itemid, 'DEX50SY'     med_code	-- dextrose
		) union ( select 10002 itemid, 'D5WLV'       med_code
	
		-- PO Hypoglycemics
		) union ( select 10003 itemid, 'GLIP10'      med_code
		) union ( select 10003 itemid, 'GLIP5'       med_code
		) union ( select 10003 itemid, 'GLIP10'      med_code
		) union ( select 10003 itemid, 'GLUC10XL'    med_code
		) union ( select 10003 itemid, 'GLUC2.5XL'   med_code
		) union ( select 10003 itemid, 'GLUC5XL'     med_code
		) union ( select 10003 itemid, 'GLYB1.25'    med_code
		) union ( select 10003 itemid, 'GLIM2'       med_code
		) union ( select 10003 itemid, 'GLYB25'      med_code
		) union ( select 10003 itemid, 'GLYB5'       med_code
		) union ( select 10003 itemid, 'GLIM1'       med_code
		) union ( select 10003 itemid, 'GLYN3'       med_code
		) union ( select 10003 itemid, 'GLIM4'       med_code
		) union ( select 10003 itemid, 'NATE60'      med_code
		) union ( select 10003 itemid, 'REPA0.5'     med_code
		) union ( select 10003 itemid, 'REPA2'       med_code
		) union ( select 10003 itemid, 'PIOG15'      med_code
		) union ( select 10003 itemid, 'PIOG45'      med_code
		) union ( select 10003 itemid, 'ACAR50'      med_code
		) union ( select 10003 itemid, 'METF500'     med_code
		) union ( select 10003 itemid, 'METF500XR'   med_code
		) union ( select 10003 itemid, 'METF750XR'   med_code
		) union ( select 10003 itemid, 'METF850'     med_code
		) union ( select 10003 itemid, 'BROM25'      med_code
		) union ( select 10003 itemid, 'SITA50'      med_code
		
		-- Drip Hypoglycemics
		) union ( select 10004 itemid, '-Drip Hypoglycemic-' med_code
		
		-- Lactulose
		) union ( select 10005 itemid, 'LACT30L'      med_code
		) union ( select 10005 itemid, 'LACT250R'     med_code
		) union ( select 10005 itemid, 'LACT30L'      med_code
		
		-- IV AV Node Blockers
		) union ( select 10006 itemid, 'LABE600/200'  med_code
		) union ( select 10006 itemid, 'LABE100I'     med_code
		) union ( select 10006 itemid, 'DILT500I'     med_code
		) union ( select 10006 itemid, 'DILT25I'      med_code
		) union ( select 10006 itemid, 'DILT12L'      med_code
		) union ( select 10006 itemid, 'DILT125D'     med_code
		) union ( select 10006 itemid, 'DILT5L'       med_code
		) union ( select 10006 itemid, 'LOMO5L'       med_code
		) union ( select 10006 itemid, 'ADEN6I'       med_code
	
		-- PO AV Node Blockers
		) union ( select 10007 itemid, 'TIAZ120'    med_code
		) union ( select 10007 itemid, 'TIAZ180'    med_code
		) union ( select 10007 itemid, 'TIAZ240'    med_code
		) union ( select 10007 itemid, 'TIAZ300'    med_code
		) union ( select 10007 itemid, 'DILT30'     med_code
		) union ( select 10007 itemid, 'DILT60'     med_code
		) union ( select 10007 itemid, 'DILT90'     med_code
		) union ( select 10007 itemid, 'LABE200'    med_code
		) union ( select 10007 itemid, 'LABE100'    med_code
		) union ( select 10007 itemid, 'VERA120'    med_code
		) union ( select 10007 itemid, 'VERA120SR'  med_code
		) union ( select 10007 itemid, 'VERA180SR'  med_code
		) union ( select 10007 itemid, 'VERA240SR'  med_code
		) union ( select 10007 itemid, 'VERA40'     med_code
		) union ( select 10007 itemid, 'VERA80'     med_code
		) union ( select 10007 itemid, 'LOMO'       med_code
		) union ( select 10007 itemid, 'ATEN25'     med_code
		) union ( select 10007 itemid, 'ATEN50'     med_code
		) union ( select 10007 itemid, 'METO1L'     med_code
		) union ( select 10007 itemid, 'METO12.5HT' med_code
		) union ( select 10007 itemid, 'METO25'     med_code
		) union ( select 10007 itemid, 'METO37.5'   med_code
		) union ( select 10007 itemid, 'METO50'     med_code
		) union ( select 10007 itemid, 'NEBI5'      med_code
		) union ( select 10007 itemid, 'PROP10'     med_code
		) union ( select 10007 itemid, 'PROP40'     med_code
		) union ( select 10007 itemid, 'PROP120'    med_code
		) union ( select 10007 itemid, 'PROP60'     med_code
		) union ( select 10007 itemid, 'PROPLA80'   med_code
		) union ( select 10007 itemid, 'PROP4L'     med_code
		) union ( select 10007 itemid, 'NPROP4L'    med_code
		) union ( select 10007 itemid, 'DIGO125'    med_code
		) union ( select 10007 itemid, 'DIGO25'     med_code
		) union ( select 10007 itemid, 'DIGO0.05L'  med_code
	
		-- IV AntiArrythmic
		) union ( select 10008 itemid, 'AMIBOLUS'       med_code
		) union ( select 10008 itemid, 'AMIO600/500D5W' med_code
		) union ( select 10008 itemid, 'AMIO150I'       med_code
		) union ( select 10008 itemid, 'AMIO450/250N'   med_code
		) union ( select 10008 itemid, 'AMIO150DK'		med_code
		) union ( select 10008 itemid, 'DXIG40I'        med_code
		) union ( select 10008 itemid, 'MAG4PM'         med_code
		) union ( select 10008 itemid, 'MAG2PM'         med_code
		) union ( select 10008 itemid, 'MAG2PMPM'       med_code
		) union ( select 10008 itemid, 'MAG2PMLF'       med_code
	
		-- PO AntiArrythmic
		) union ( select 10009 itemid, 'AMID200'     med_code	-- amiodarone
		) union ( select 10009 itemid, 'AMID200M'    med_code
		) union ( select 10009 itemid, 'QUIG324'     med_code
		) union ( select 10009 itemid, 'QUIN200'     med_code
		) union ( select 10009 itemid, 'QUIN300'     med_code
		) union ( select 10009 itemid, 'DISO100'     med_code
		) union ( select 10009 itemid, 'DISO150CR'   med_code
		) union ( select 10009 itemid, 'DISO100CR'   med_code
		) union ( select 10009 itemid, 'DISO150'     med_code
		) union ( select 10009 itemid, 'PHEN50'      med_code
		) union ( select 10009 itemid, 'DILA30'      med_code
		) union ( select 10009 itemid, 'MEXI150'     med_code
		) union ( select 10009 itemid, 'MEXI200'     med_code
		) union ( select 10009 itemid, 'MEXI25'      med_code
		) union ( select 10009 itemid, 'FLEC50'      med_code
		) union ( select 10009 itemid, 'PROP150'     med_code
		) union ( select 10009 itemid, 'PROP225'     med_code
		) union ( select 10009 itemid, 'CARV125'     med_code
		) union ( select 10009 itemid, 'CARV25'      med_code
		) union ( select 10009 itemid, 'CARV3125'    med_code
		) union ( select 10009 itemid, 'CARV625'     med_code
		) union ( select 10009 itemid, 'BISO5'       med_code
		) union ( select 10009 itemid, 'TOPR100'     med_code
		) union ( select 10009 itemid, 'TOPR25'      med_code
		) union ( select 10009 itemid, 'TOPR50'      med_code
		) union ( select 10009 itemid, 'SOTA80'      med_code
		) union ( select 10009 itemid, 'DOFE500'     med_code
		) union ( select 10009 itemid, 'DOFE125'     med_code
		) union ( select 10009 itemid, 'DOFE250'     med_code
		) union ( select 10009 itemid, 'DRON400'     med_code
	
		-- Anti Seizures
		) union ( select 10010 itemid, 'LORA60PB'     med_code
		) union ( select 10010 itemid, 'ACE250'       med_code
		) union ( select 10010 itemid, 'ACE500'       med_code
		) union ( select 10010 itemid, 'ACET250D'     med_code
		) union ( select 10010 itemid, 'ACET500D'     med_code
		) union ( select 10010 itemid, 'CLON0.125ODT' med_code
		) union ( select 10010 itemid, 'CLON1'        med_code
		) union ( select 10010 itemid, 'CLON5'        med_code
		) union ( select 10010 itemid, 'CLOR375'      med_code
		) union ( select 10010 itemid, 'DIAZ10'       med_code
		) union ( select 10010 itemid, 'DIAZ10I'      med_code
		) union ( select 10010 itemid, 'DIAZ2'        med_code
		) union ( select 10010 itemid, 'DIAZ5'        med_code
		) union ( select 10010 itemid, 'DIAZE5L'      med_code
		) union ( select 10010 itemid, 'LAMO100'      med_code
		) union ( select 10010 itemid, 'LAMO100BN'    med_code
		) union ( select 10010 itemid, 'LAMO100S'     med_code
		) union ( select 10010 itemid, 'LAMO100XR'    med_code
		) union ( select 10010 itemid, 'LAMO25'       med_code
		) union ( select 10010 itemid, 'LAMO25BRAND'  med_code
		) union ( select 10010 itemid, 'LAMO25XR'     med_code
		) union ( select 10010 itemid, 'LAMO300S'     med_code
		) union ( select 10010 itemid, 'LAMO5'        med_code
		) union ( select 10010 itemid, 'TOPI100'      med_code
		) union ( select 10010 itemid, 'TOPI25'       med_code
		) union ( select 10010 itemid, 'TOPI6L'       med_code
		) union ( select 10010 itemid, 'VAL250L'      med_code
		) union ( select 10010 itemid, 'VALP250'      med_code
	
		-- IV Anticoagulants (e.g. heparin)
		) union ( select 10011 itemid, 'ACD3/1000I'      med_code
		) union ( select 10011 itemid, 'FENT2.550'       med_code
		) union ( select 10011 itemid, 'FENT2I'          med_code
		) union ( select 10011 itemid, 'BICINEO'         med_code
		) union ( select 10011 itemid, 'TOBR/SODCIT5SYR' med_code
		) union ( select 10011 itemid, 'MAGCITL'         med_code
		) union ( select 10011 itemid, 'HEP10I'          med_code
		) union ( select 10011 itemid, 'HEPA5000LF'      med_code
		) union ( select 10011 itemid, 'HEPPREMIX'       med_code
		) union ( select 10011 itemid, 'HEPA25/250NS'    med_code
		) union ( select 10011 itemid, 'STARTPND10'      med_code
		) union ( select 10011 itemid, 'VANHEPLOCKDIAL'  med_code
		) union ( select 10011 itemid, 'HEPA10MUI'       med_code
		) union ( select 10011 itemid, 'STARTD5HEP'      med_code
		) union ( select 10011 itemid, 'HEPPREMIXP'      med_code
		) union ( select 10011 itemid, 'DAPT10HEP%S'     med_code
		) union ( select 10011 itemid, 'HEPPREMIXNS'     med_code
		) union ( select 10011 itemid, 'HEPA30I'         med_code
		) union ( select 10011 itemid, 'HEPIMP3125'      med_code
		) union ( select 10011 itemid, 'HEPA5I'          med_code
	
		-- IV Steroids (anti-inflammatory)
		) union ( select 10012 itemid, 'DEXA12/50D5W'   med_code
		) union ( select 10012 itemid, 'BUDE0.5'        med_code
		) union ( select 10012 itemid, 'BUDE0.25'       med_code
		) union ( select 10012 itemid, 'DEXA12/50D5W'   med_code
		) union ( select 10012 itemid, 'PRED5L'         med_code
		) union ( select 10012 itemid, 'NEODEXA0.2L'    med_code
		) union ( select 10012 itemid, 'METH1000MBP'    med_code
	
		-- PO Steroids (anti-inflammatory)
		) union ( select 10013 itemid, 'PRED20'     med_code
		) union ( select 10013 itemid, 'DEXA4'      med_code
		) union ( select 10013 itemid, 'PRED10'     med_code
		) union ( select 10013 itemid, 'PRED50'     med_code
		) union ( select 10013 itemid, 'DEXA2'      med_code
		) union ( select 10013 itemid, 'PRED25'     med_code
		) union ( select 10013 itemid, 'PRED5SM'    med_code
		) union ( select 10013 itemid, 'MPRED2'     med_code
		) union ( select 10013 itemid, 'METH8'      med_code
		) union ( select 10013 itemid, 'DEXA5'      med_code
		) union ( select 10013 itemid, 'DEXA15'     med_code
		) union ( select 10013 itemid, 'BUDE3'      med_code
		) union ( select 10013 itemid, 'HC5'        med_code
		) union ( select 10013 itemid, 'PRED1'      med_code
		) union ( select 10013 itemid, 'FLUD100'    med_code
		) union ( select 10013 itemid, 'HC20'       med_code
	
		-- IV Immunotherapy (cancer treatments)
		) union ( select 10014 itemid, 'OXAL1.4'        med_code
		) union ( select 10014 itemid, 'OXAL14'         med_code
		) union ( select 10014 itemid, 'OXAL140'        med_code
		) union ( select 10014 itemid, 'NIVO480/960INV' med_code
		) union ( select 10014 itemid, 'MYCO1PB'        med_code
		) union ( select 10014 itemid, 'MYCO1500PB'     med_code
		) union ( select 10014 itemid, 'MYCO250IV'      med_code
		) union ( select 10014 itemid, 'MYCO500/85'     med_code
		) union ( select 10014 itemid, 'MYCO750'        med_code
	
		-- PO Immunotherapy (cancer treatments)
		) union ( select 10015 itemid, 'GILT40'      med_code
		) union ( select 10015 itemid, 'MIDOS25'     med_code
	
		-- IV AntiPsychotics
		) union ( select 10016 itemid, 'HALO2OS'     med_code
		) union ( select 10016 itemid, 'THOR25I'     med_code
		) union ( select 10016 itemid, 'FLUP5L'      med_code
		) union ( select 10016 itemid, 'FLUP25L'     med_code
		) union ( select 10016 itemid, 'FLUP125I'    med_code
		) union ( select 10016 itemid, 'FLUP2.5I'    med_code
	
		-- PO AntiPsychotics
		) union ( select 10017 itemid, 'LOXA5'      med_code
		) union ( select 10017 itemid, 'ILOP2'      med_code
		) union ( select 10017 itemid, 'TRIF1'      med_code
		) union ( select 10017 itemid, 'THIO10'     med_code
		) union ( select 10017 itemid, 'THIO100'    med_code
		) union ( select 10017 itemid, 'TRIF2'      med_code
		) union ( select 10017 itemid, 'TRIF5'      med_code
		) union ( select 10017 itemid, 'FLUP1'      med_code
		) union ( select 10017 itemid, 'THOR10'     med_code
		) union ( select 10017 itemid, 'THIO25'     med_code
		) union ( select 10017 itemid, 'FLUP10'     med_code
		) union ( select 10017 itemid, 'FLUP25'     med_code
		) union ( select 10017 itemid, 'THOR100'    med_code
		) union ( select 10017 itemid, 'PERP2'      med_code
		) union ( select 10017 itemid, 'PERP8'      med_code
		) union ( select 10017 itemid, 'PROC5'      med_code
		) union ( select 10017 itemid, 'THOR25'     med_code
		) union ( select 10017 itemid, 'PROC10'     med_code
		) union ( select 10017 itemid, 'THIX1'      med_code
		) union ( select 10017 itemid, 'THIX5'      med_code
		) union ( select 10017 itemid, 'HALO2L'     med_code
		) union ( select 10017 itemid, 'HALO1'      med_code
		) union ( select 10017 itemid, 'LOXA25'     med_code
		) union ( select 10017 itemid, 'HALO10'     med_code
		) union ( select 10017 itemid, 'HALO2'      med_code
		) union ( select 10017 itemid, 'HALO05'     med_code
		) union ( select 10017 itemid, 'HALO5'      med_code
	
		-- Sedative Drips
		) union ( select 10018 itemid, 'PROP100IG'    med_code
		) union ( select 10018 itemid, 'PROP200IG'    med_code
		) union ( select 10018 itemid, 'PROP500IG'    med_code
		) union ( select 10018 itemid, 'DEXM400INV'   med_code
		) union ( select 10018 itemid, 'APRA5OS'      med_code
	
		-- IV Benzodiazepine
		) union ( select 10019 itemid, 'LORA2I'      med_code
		) union ( select 10019 itemid, 'LORA60PB'    med_code
		) union ( select 10019 itemid, 'MIDA2I'      med_code
		) union ( select 10019 itemid, 'MIDA5I'      med_code
		) union ( select 10019 itemid, 'MIDA100PC'   med_code
		) union ( select 10019 itemid, 'MIDA500'     med_code
		) union ( select 10019 itemid, 'MIDA250'     med_code
		) union ( select 10019 itemid, 'MIDA100'     med_code
	
		-- PO Benzodiazepine
		) union ( select 10020 itemid, 'LORA5'         med_code
		) union ( select 10020 itemid, 'LORA1'         med_code
		) union ( select 10020 itemid, 'TEMA15'        med_code
		) union ( select 10020 itemid, 'TRIA25'        med_code
		) union ( select 10020 itemid, 'ALPR25'        med_code
		) union ( select 10020 itemid, 'ALPR1'         med_code
		) union ( select 10020 itemid, 'CHLO25'        med_code
		) union ( select 10020 itemid, 'CHLOR5'        med_code
		) union ( select 10020 itemid, 'CLOR375'       med_code
		) union ( select 10020 itemid, 'DIAZ10'        med_code
		) union ( select 10020 itemid, 'DIAZ2'         med_code
		) union ( select 10020 itemid, 'DIAZ5'         med_code
		) union ( select 10020 itemid, 'MIDA1L'        med_code
		) union ( select 10020 itemid, 'OXAZ10'        med_code
		) union ( select 10020 itemid, 'OXAZ15'        med_code
	
		-- Vasopressors (blood vessel constricting)
		) union ( select 10021 itemid, 'PHEN10I'       med_code
		) union ( select 10021 itemid, 'PHEN50I'       med_code
		) union ( select 10021 itemid, 'PHEN50/250PM'  med_code
		) union ( select 10021 itemid, 'PHEN60/250NS'  med_code
		) union ( select 10021 itemid, 'PHEN60/250PM'  med_code
		) union ( select 10021 itemid, 'PHEN60250D'    med_code
		) union ( select 10021 itemid, 'PHEN60DK'      med_code
		) union ( select 10021 itemid, 'CYCL2O'        med_code
		) union ( select 10021 itemid, 'NEONEOIH'      med_code
		) union ( select 10021 itemid, 'PHEN10ES'      med_code
		) union ( select 10021 itemid, 'PHEN2.5O'      med_code
		) union ( select 10021 itemid, 'PHEN25ES'      med_code
		) union ( select 10021 itemid, 'PHEN5N'        med_code
		) union ( select 10021 itemid, 'VASO40DK'      med_code
		) union ( select 10021 itemid, 'VASO20I'       med_code
		) union ( select 10021 itemid, 'VASO40/100'    med_code
		) union ( select 10021 itemid, 'BUPIWE5I'      med_code
		) union ( select 10021 itemid, 'EPI1I'         med_code
		) union ( select 10021 itemid, 'EPI2DK'        med_code
		) union ( select 10021 itemid, 'EPI400SYR'     med_code
		) union ( select 10021 itemid, 'EPIPEN0.3I'    med_code
		) union ( select 10021 itemid, 'EPIS10I'       med_code
		) union ( select 10021 itemid, 'LIDEPF1.530I'  med_code
		) union ( select 10021 itemid, 'LIDO/EPI30'    med_code
		) union ( select 10021 itemid, 'LIEP550I'      med_code
		) union ( select 10021 itemid, 'LIEPI20I'      med_code
		) union ( select 10021 itemid, 'NEONEOIH'      med_code
		) union ( select 10021 itemid, 'NORE8/250'     med_code
		) union ( select 10021 itemid, 'NORE8/250N'    med_code
		) union ( select 10021 itemid, 'NORE8/250NS'   med_code
		) union ( select 10021 itemid, 'PHEN2.5O'      med_code
		) union ( select 10021 itemid, 'RACE0.5H'      med_code	
		) union ( select 10021 itemid, 'RACE0.5HN'     med_code	
	
		-- Inotropes (heart reviving)
		) union ( select 10022 itemid, 'MILR20PM'    med_code
		) union ( select 10022 itemid, 'DIGO.5I'     med_code
		) union ( select 10022 itemid, 'DIGO0.05L'   med_code
		) union ( select 10022 itemid, 'DIGO125'     med_code
		) union ( select 10022 itemid, 'DIGO25'      med_code
		) union ( select 10022 itemid, 'DIGO50L'     med_code
		) union ( select 10022 itemid, 'DOPA400D'    med_code
		) union ( select 10022 itemid, 'DXIG40I'     med_code
	
		-- IV Diuretics (increase water/fluid)
		) union ( select 10023 itemid, 'BUME50D5W'         med_code
		) union ( select 10023 itemid, 'POTA20/250D5'      med_code
		) union ( select 10023 itemid, 'KCL40/100D'        med_code
		) union ( select 10023 itemid, 'KCL40/500D'        med_code
		) union ( select 10023 itemid, 'FURO40ILF'         med_code
		) union ( select 10023 itemid, 'FURO40I'           med_code
		) union ( select 10023 itemid, 'FURO20I'           med_code
		) union ( select 10023 itemid, 'FURO10L'           med_code
		) union ( select 10023 itemid, 'FURO250/50'        med_code
		) union ( select 10023 itemid, 'FURO100PB'         med_code
		) union ( select 10023 itemid, 'FURO40/40'         med_code
		) union ( select 10023 itemid, 'KCL40/500N'        med_code
		) union ( select 10023 itemid, 'POTA20/250NS'      med_code
		) union ( select 10023 itemid, 'KCL40/500D'        med_code
		) union ( select 10023 itemid, 'KCL40/500N'        med_code
		) union ( select 10023 itemid, 'KCL20/1000D51/2NS' med_code
		) union ( select 10023 itemid, 'KCL40/500D'        med_code
		) union ( select 10023 itemid, 'POTA20/250D5'      med_code
		) union ( select 10023 itemid, 'KCL20PM'           med_code
		) union ( select 10023 itemid, 'KCL40/1000D5NS'    med_code
		) union ( select 10023 itemid, 'KCL40/1000NS'      med_code
		) union ( select 10023 itemid, 'KCL10NS100'        med_code
		) union ( select 10023 itemid, 'KCL20/1000D5NS'    med_code
		) union ( select 10023 itemid, 'KCL40/1000D51/2NS' med_code
		) union ( select 10023 itemid, 'KCL10PM'           med_code
		) union ( select 10023 itemid, 'KCL40/100D'        med_code
		) union ( select 10023 itemid, 'KCL20/1000D5LR'    med_code
		) union ( select 10023 itemid, 'KCL20/1000NS'      med_code
		) union ( select 10023 itemid, 'KCL2050NS'         med_code
		) union ( select 10023 itemid, 'BUME25I'           med_code
		) union ( select 10023 itemid, 'CHL500I'           med_code
		) union ( select 10023 itemid, 'ACET250D'          med_code
		) union ( select 10023 itemid, 'MANN20PM'          med_code
		) union ( select 10023 itemid, 'ACET500D'          med_code
		) union ( select 10023 itemid, 'HYDR750L'          med_code
		) union ( select 10023 itemid, 'BUME10/40'         med_code
		) union ( select 10023 itemid, 'BUME1I'            med_code
		) union ( select 10023 itemid, 'SPIR4L'            med_code
	
		-- PO Diuretics
		) union ( select 10024 itemid, 'FURO20'     med_code
		) union ( select 10024 itemid, 'FURO40'     med_code
		) union ( select 10024 itemid, 'FURO80'     med_code
		) union ( select 10024 itemid, 'HYDU500'    med_code
		) union ( select 10024 itemid, 'TRIA50'     med_code
		) union ( select 10024 itemid, 'HYDR200L'   med_code
		) union ( select 10024 itemid, 'HYDR250L'   med_code
		) union ( select 10024 itemid, 'SPIR25'     med_code
		) union ( select 10024 itemid, 'HCTZ12.5'   med_code
		) union ( select 10024 itemid, 'TORS5'      med_code
		) union ( select 10024 itemid, 'TORS100'    med_code
		) union ( select 10024 itemid, 'CHTH25'     med_code
		) union ( select 10024 itemid, 'ACE250'     med_code
		) union ( select 10024 itemid, 'BUME05'     med_code
		) union ( select 10024 itemid, 'EPLE25'     med_code
		) union ( select 10024 itemid, 'ETHA25'     med_code
		) union ( select 10024 itemid, 'EPLE50'     med_code
		) union ( select 10024 itemid, 'BUME2'      med_code
		) union ( select 10024 itemid, 'METL25'     med_code
		) union ( select 10024 itemid, 'HCTZ50'     med_code
		) union ( select 10024 itemid, 'CHLO250'    med_code
		) union ( select 10024 itemid, 'LOZ25'      med_code
		) union ( select 10024 itemid, 'SPIR12.5HT' med_code
		) union ( select 10024 itemid, 'ACE500'     med_code
		) union ( select 10024 itemid, 'DYAZ1'      med_code
		) union ( select 10024 itemid, 'TORS20'     med_code
		) union ( select 10024 itemid, 'METZ50'     med_code
		) union ( select 10024 itemid, 'AMIL5'      med_code
		) union ( select 10024 itemid, 'HCTZ25'     med_code
		) union ( select 10024 itemid, 'METL5'      med_code
		) union ( select 10024 itemid, 'SPIR100'     med_code
	
		-- Antibiotics
		) union ( select 10025 itemid, 'AMOX250'         med_code
		) union ( select 10025 itemid, 'AMPI250'         med_code
		) union ( select 10025 itemid, 'AMPI500'         med_code
		) union ( select 10025 itemid, 'AMPI500L'        med_code
		) union ( select 10025 itemid, 'AUGM875L'        med_code
		) union ( select 10025 itemid, 'AUGM875'         med_code
		) union ( select 10025 itemid, 'AUGM250'         med_code
		) union ( select 10025 itemid, 'AUGM500'         med_code
		) union ( select 10025 itemid, 'AMP1I'           med_code
		) union ( select 10025 itemid, 'AMP2I'           med_code
		) union ( select 10025 itemid, 'AMPDESEN2'       med_code
		) union ( select 10025 itemid, 'AMPDESEN3'       med_code
		) union ( select 10025 itemid, 'AMP1/100N'       med_code
		) union ( select 10025 itemid, 'AMP1/100MBP'     med_code
		) union ( select 10025 itemid, 'AMP2/100N'       med_code
		) union ( select 10025 itemid, 'AMPI2/100MBP'    med_code
		) union ( select 10025 itemid, 'AMPI2/100VMA'    med_code
		) union ( select 10025 itemid, 'AMP500I'         med_code
		) union ( select 10025 itemid, 'UNAS1.5I'        med_code
		) union ( select 10025 itemid, 'UNAS1.5/100N'    med_code
		) union ( select 10025 itemid, 'UNAS1.5/100MBP'  med_code
		) union ( select 10025 itemid, 'UNAS3I'          med_code
		) union ( select 10025 itemid, 'UNAS3/100N'      med_code
		) union ( select 10025 itemid, 'UNAS3/100MBP'    med_code
		) union ( select 10025 itemid, 'DICL250'         med_code
		) union ( select 10025 itemid, 'DICL500'         med_code
		) union ( select 10025 itemid, 'NAFC2I'          med_code
		) union ( select 10025 itemid, 'NAFC1I'          med_code
		) union ( select 10025 itemid, 'NAFC1/100MBP'    med_code
		) union ( select 10025 itemid, 'NAFC2/100MBP'    med_code
		) union ( select 10025 itemid, 'NAFC2F'          med_code
		) union ( select 10025 itemid, 'OXAC1I'          med_code
		) union ( select 10025 itemid, 'PCNGB240I'       med_code
		) union ( select 10025 itemid, 'PENI12I'         med_code
		) union ( select 10025 itemid, 'PENGK5I'         med_code
		) union ( select 10025 itemid, 'PEN3FROZ'        med_code
		) union ( select 10025 itemid, 'PENG5BAG'        med_code
		) union ( select 10025 itemid, 'PENI125L'        med_code
		) union ( select 10025 itemid, 'PENV250'         med_code
		) union ( select 10025 itemid, 'PENV500'         med_code
		) union ( select 10025 itemid, 'ZOSY2.25I'       med_code
		) union ( select 10025 itemid, 'ZOSY4.5MBP'      med_code
		) union ( select 10025 itemid, 'ZOSY4.5NS'       med_code
		) union ( select 10025 itemid, 'ZOSY4FPB'        med_code
		) union ( select 10025 itemid, 'ZOSY4.5FD'       med_code
		) union ( select 10025 itemid, 'ZOSY4.5NS'       med_code
		) union ( select 10025 itemid, 'ZOSY2.25IFD'     med_code
		) union ( select 10025 itemid, 'AZIT500D5W'      med_code
		) union ( select 10025 itemid, 'AZIT500NS'       med_code
		) union ( select 10025 itemid, 'AZIT500I'        med_code
		) union ( select 10025 itemid, 'AZIT500NSE'      med_code
		) union ( select 10025 itemid, 'AZIT250IND'      med_code
		) union ( select 10025 itemid, 'AZIT600'         med_code
		) union ( select 10025 itemid, 'AZIT1O'          med_code
		) union ( select 10025 itemid, 'ZITHR250'        med_code
		) union ( select 10025 itemid, 'CEFA2/20SYR'     med_code
		) union ( select 10025 itemid, 'CEFA1I'          med_code
		) union ( select 10025 itemid, 'CEFA2/100D'      med_code
		) union ( select 10025 itemid, 'CEF2GM'          med_code
		) union ( select 10025 itemid, 'CEFX1F'          med_code
		) union ( select 10025 itemid, 'CEFA1F'          med_code
		) union ( select 10025 itemid, 'CEFA2D100'       med_code
		) union ( select 10025 itemid, 'CEFA2D'          med_code
		) union ( select 10025 itemid, 'CEFT1/50D'       med_code
		) union ( select 10025 itemid, 'CEFT2/50D'       med_code
		) union ( select 10025 itemid, 'CEFT3/100D'      med_code
		) union ( select 10025 itemid, 'CEFE1/100D'      med_code
		) union ( select 10025 itemid, 'CEFDESEN3'       med_code
		) union ( select 10025 itemid, 'CEFE1/100D'      med_code
		) union ( select 10025 itemid, 'CEFE1/100MBP'    med_code
		) union ( select 10025 itemid, 'CEFE1/100N'      med_code
		) union ( select 10025 itemid, 'CEFE1/50D'       med_code
		) union ( select 10025 itemid, 'CEFE1I'          med_code
		) union ( select 10025 itemid, 'CEFE2/100MBP'    med_code
		) union ( select 10025 itemid, 'CEFE2F'          med_code
		) union ( select 10025 itemid, 'CEFE2I'          med_code
		) union ( select 10025 itemid, 'CEFR1I'          med_code
		) union ( select 10025 itemid, 'CEFR250I'        med_code
		) union ( select 10025 itemid, 'CEFR2I'          med_code
		) union ( select 10025 itemid, 'CEFTR1/100MBP'   med_code
		) union ( select 10025 itemid, 'CEFTR1/50D'      med_code
		) union ( select 10025 itemid, 'CEFTR2/100MBP'   med_code
		) union ( select 10025 itemid, 'CEFTR2/100N'     med_code
		) union ( select 10025 itemid, 'CEFTR2/50D	'    med_code
		) union ( select 10025 itemid, 'CILO25ES'        med_code
		) union ( select 10025 itemid, 'CIPR200PM'       med_code
		) union ( select 10025 itemid, 'CIPR250'         med_code
		) union ( select 10025 itemid, 'CIPR400PM'       med_code
		) union ( select 10025 itemid, 'CIPR500'         med_code
		) union ( select 10025 itemid, 'CIPR50L'         med_code
		) union ( select 10025 itemid, 'CIPRODEX'        med_code
		) union ( select 10025 itemid, 'CLIN600PM'       med_code
		) union ( select 10025 itemid, 'CLIN900PM'       med_code
		) union ( select 10025 itemid, 'CLIN150'         med_code
		) union ( select 10025 itemid, 'CLIN150IND'      med_code
		) union ( select 10025 itemid, 'CLIN300L'        med_code
		) union ( select 10025 itemid, 'CLIN450L'        med_code
		) union ( select 10025 itemid, 'CLIN600L'        med_code
		) union ( select 10025 itemid, 'CLIN150L'        med_code
		) union ( select 10025 itemid, 'CLIN600P'        med_code
		) union ( select 10025 itemid, 'CLIN900P'        med_code
		) union ( select 10025 itemid, 'CLIN300PM'       med_code
		) union ( select 10025 itemid, 'CLIN1S'          med_code
		) union ( select 10025 itemid, 'DALB1500/250D5'  med_code
		) union ( select 10025 itemid, 'DALB1500/500D5'  med_code
		) union ( select 10025 itemid, 'LEVO750'         med_code
		) union ( select 10025 itemid, 'LEV250'          med_code
		) union ( select 10025 itemid, 'LEV500'          med_code
		) union ( select 10025 itemid, 'LEVO250PM'       med_code
		) union ( select 10025 itemid, 'LEVO500PM'       med_code
		) union ( select 10025 itemid, 'LEVO750PM'       med_code
		) union ( select 10025 itemid, 'VANC1F'          med_code
		) union ( select 10025 itemid, 'VAN1250D'        med_code
		) union ( select 10025 itemid, 'VANC1500D'       med_code
		) union ( select 10025 itemid, 'VANC500F'        med_code
		) union ( select 10025 itemid, 'VAN500D'         med_code
		) union ( select 10025 itemid, 'VANC750F'        med_code
		) union ( select 10025 itemid, 'VAN750D'         med_code
		) union ( select 10025 itemid, 'VORI200/100D'    med_code
		) union ( select 10025 itemid, 'VORI200'         med_code
		) union ( select 10025 itemid, 'VORI50'          med_code
		) union ( select 10025 itemid, 'VORI200/100N'    med_code
		) union ( select 10025 itemid, 'VORI1OPH'        med_code
		) union ( select 10025 itemid, 'VANC1750NS'      med_code
		) union ( select 10025 itemid, 'VANC2000NS'      med_code
		) union ( select 10025 itemid, 'VANC1000NS'      med_code
		) union ( select 10025 itemid, 'VANHEPLOCKDIAL'  med_code
		) union ( select 10025 itemid, 'VANCO25O'        med_code
		) union ( select 10025 itemid, 'VANCO14O'        med_code
		) union ( select 10025 itemid, 'VANC1FN'         med_code
		) union ( select 10025 itemid, 'VANC1250NS'      med_code
		) union ( select 10025 itemid, 'VANC750N'        med_code
		) union ( select 10025 itemid, 'VANCO25OT'       med_code
		) union ( select 10025 itemid, 'VANC500PR'       med_code
		) union ( select 10025 itemid, 'VANC1500NS'      med_code
		)
	
	), emar_detail_items as (
	
		-- join emar_detail with med_codes to map the medicine to our desired itemid
		select *
		from med_codes d join mimic_hosp.emar_detail ed
		on d.med_code = ed.product_code
	
	), emar_events as (
	
		-- join emar to emar_detail to map medicines to their administration time
		select e.subject_id, e.hadm_id, ed.itemid, e.charttime, e.event_txt
		from emar_detail_items ed  join mimic_hosp.emar e
		on ed.emar_id = e.emar_id 
		where ed.product_code in ( 
			-- drugs to find by product_code
			select mc.med_code
			from med_codes mc
		)
		and e.hadm_id in (
			-- elligible patient visits
			select *
			from visit_ids
		)
		
	), emar_results as (
	
		-- join emar_events to emar_actions to map the medicine administration to the lookup table deciding if it's active
		select ev.subject_id, ev.hadm_id, ev.itemid, ev.charttime, ea.active
		from emar_events ev join emar_actions ea 
		on ev.event_txt = ea.med_action
	)
	-- merge emar_results with mimic_derived.cohort to form final result
	select er.subject_id, er.hadm_id, er.itemid, a.admittime, er.charttime, 0 var_type, er.active as val_num, 0 val_min, 1 val_max, 0 ref_min, 0 ref_max, 0 val_default, a.hospital_expire_flag, a.time_in, a.gap
	from emar_results er join mimic_derived.cohort a 
	on er.hadm_id = a.hadm_id 
	where extract( epoch from age( er.charttime, a.admittime )) <= a.icu_limit

), input_events as (

	/*****************************************************
	 * Input events - events for fluids, medications and other substances administered to patient in the ICU
	 * 
	 * NOTE: amount may be <= 0 (but rare)
	 *****************************************************/
	with i_items as (
		-- consider adding: rate, rate uom fields
		select i.subject_id, i.hadm_id, i.itemid, a.admittime, i.starttime as charttime, (case when i.amount <= 0 then 0 else 1 end) as val_num, a.hospital_expire_flag, a.time_in, a.gap
		from mimic_derived.cohort a join mimic_icu.inputevents i 
		on a.subject_id = i.subject_id
		where i.hadm_id is not null
		and i.itemid in (
			-- interventions (convert to binary)
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
		and i.hadm_id in (
			select *
			from visit_ids 
		)
		and extract( epoch from age( i.starttime, a.admittime )) between 0 and a.icu_limit
	)
	select ii.subject_id, ii.hadm_id, ii.itemid, ii.admittime, ii.charttime, v.var_type, ii.val_num, v.val_min, v.val_max, v.ref_min, v.ref_max, v.val_default, ii.hospital_expire_flag, ii.time_in, ii.gap
	from i_items ii join val_defaults v
	on ii.itemid = v.itemid

), output_events as (

	/***********************
	 * Output events - events for collection of samples output from the patient.
	 * 
	 * NOTE: numeric values may be <= 0 (but rare).
	 **********************/
	with o_items as (
	
		-- NOTE: urine output is normal (0), we flag abnormal (1) when urine is measured and there is no appreciable output (see paper)
		select o.subject_id, o.hadm_id, o.itemid, a.admittime, o.charttime, (case when o.value > 0 then 0 else 1 end) as val_num, a.hospital_expire_flag, a.time_in, a.gap
		from mimic_derived.cohort a join mimic_icu.outputevents o 
		on a.subject_id = o.subject_id 
		where o.hadm_id is not null
		and o.itemid in (
	
			-- Urine output (convert to binary)
	--		226566,		-- Urine and GU Irrigant out.  [No records found in mimic_iv]
			226627,		-- OR Urine
			226631,		-- PACU Urine
			227489,		-- U Irrigant/Urine Volume Out
			226559 		-- Foley catheter (output)	
	
			-- other Urine output (convert to binary)
--			226560, -- "Void"
--			227510, -- "TF Residual"
--			226561, -- "Condom Cath"
--			226584, -- "Ileoconduit"
--			226563, -- "Suprapubic"
--			226564, -- "R Nephrostomy"
--			226565, -- "L Nephrostomy"
--			226567, --	Straight Cath
--			226557, -- "R Ureteral Stent"
--			226558  -- "L Ureteral Stent"
			
		) and o.hadm_id in (
			-- ids of patients admitted to hospital and stayed for at least 48 hours.
			select *
			from visit_ids
		) and extract( epoch from age( o.charttime, a.admittime )) between 0 and a.icu_limit
	)
	select oo.subject_id, oo.hadm_id, oo.itemid, oo.admittime, oo.charttime, v.var_type, oo.val_num, v.val_min, v.val_max, v.ref_min, v.ref_max, v.val_default, oo.hospital_expire_flag, oo.time_in, oo.gap
	from o_items oo join val_defaults v
	on oo.itemid = v.itemid

), procedure_events as (

	/***********************
	 * Procedure events - events for procedures administered to the patient (e.g. ventilation, X-rays, ...)
	 * 
	 * NOTE: numeric values observed are >= 0.
	 **********************/
	with proc_items as (
		-- interventions procedures
		(         select 0 grp, 25955  itemid 	-- Dialysis
		) union ( select 0 grp, 225809 itemid 
		) union ( select 0 grp, 225805 itemid 
		) union ( select 0 grp, 225803 itemid 
		) union ( select 0 grp, 225802 itemid 
		) union ( select 0 grp, 225441 itemid 
		) union ( select 0 grp, 225792 itemid 	-- using Ventilation (units/time)
		) union ( select 0 grp, 225794 itemid 
		) union ( select 0 grp, 229351 itemid 	-- Foley Catheter (units/time)
		-- imaging
		) union ( select 1 grp, 225402 itemid 	-- EKG (ElectroCardiogram).
		) union ( select 1 grp, 225432 itemid 	-- TTE (Transthoracic EchoCardiogram)
		) union ( select 1 grp, 225459 itemid 	-- Chest X-ray.
		) union ( select 1 grp, 229581 itemid 	-- Chest X-ray. Portable Chest X-ray
		) union ( select 1 grp, 225457 itemid 	-- Abdominal X-ray
		) union ( select 1 grp, 221214 itemid 	-- CT Scan (head, neck, chest, and abdomen)
		) union ( select 1 grp, 229582 itemid 	-- CT Scan (head, neck, chest, and abdomen)  Portable
		) union ( select 1 grp, 221217 itemid 	-- UltraSound.
		) union ( select 1 grp, 225401 itemid	-- Blood Culture order 
		)
		
	), results as (

		(
			-- start time
			select p.subject_id, p.hadm_id, p.itemid, a.admittime, p.starttime as charttime, (case when p.value is null or p.value <= 0 then 0 else 1 end) as val_num, a.hospital_expire_flag, a.time_in, a.gap
			from mimic_derived.cohort a join mimic_icu.procedureevents p
			on a.subject_id = p.subject_id 
			where p.hadm_id is not null
			and p.itemid in (
				select itemid
				from proc_items
			)
			and p.hadm_id in (
				-- ids of patients admitted to hospital and stayed for at least 48 hours.
				select *
				from visit_ids
			)
			and extract( epoch from age( p.starttime, a.admittime )) between 0 and a.icu_limit
			
		) union (
			-- end time
			select p.subject_id, p.hadm_id, p.itemid, a.admittime, p.endtime as charttime, 0 as val_num, a.hospital_expire_flag, a.time_in, a.gap
			from mimic_derived.cohort a join mimic_icu.procedureevents p
			on a.subject_id = p.subject_id 
			where p.hadm_id is not null
			and p.itemid in (
				select itemid
				from proc_items
				where grp = 0
			) 
			and p.hadm_id in (
				-- ids of patients admitted to hospital and stayed for at least 48 hours.
				select *
				from visit_ids
			)
			and extract( epoch from age( p.endtime, a.admittime )) between 0 and a.icu_limit
		)
	)
	select r.subject_id, r.hadm_id, r.itemid, r.admittime, r.charttime, v.var_type, r.val_num, v.val_min, v.val_max, v.ref_min, v.ref_max, v.val_default, r.hospital_expire_flag, r.time_in, r.gap
	from results r join val_defaults v 
	on r.itemid = v.itemid

), examinations as (

	-- map ICD code to itemID
	with icd_itemid as (
	
		-- Cardiac Paced (pacemaker)
		(         select 10026 itemid, '99601'  icd_code
		) union ( select 10026 itemid, 'V4501'  icd_code
		) union ( select 10026 itemid, 'V5331'  icd_code
		) union ( select 10026 itemid, 'Z4501'  icd_code
		) union ( select 10026 itemid, 'Z45010' icd_code
		) union ( select 10026 itemid, 'Z45018' icd_code
		) union ( select 10026 itemid, 'Z950'   icd_code
		
		-- atrial fibrillation
		) union ( select 10027 itemid, 'I480'  icd_code
		) union ( select 10027 itemid, 'I481'  icd_code
		) union ( select 10027 itemid, 'I4811' icd_code
		) union ( select 10027 itemid, 'I4819' icd_code
		) union ( select 10027 itemid, 'I482'  icd_code
		) union ( select 10027 itemid, 'I4820' icd_code	
		) union ( select 10027 itemid, 'I4821' icd_code
		) union ( select 10027 itemid, 'I489'  icd_code
		) union ( select 10027 itemid, 'I4891' icd_code
		
		-- Atrial Flutter
		) union ( select 10028 itemid, '42732' icd_code
		) union ( select 10028 itemid, 'I48'   icd_code
		) union ( select 10028 itemid, 'I483'  icd_code
		) union ( select 10028 itemid, 'I484'  icd_code
		) union ( select 10028 itemid, 'I489'  icd_code
		) union ( select 10028 itemid, 'I4892' icd_code
	
		-- Using? (not sure what this is)
		) union ( select 10029 itemid, '' icd_code
		
		-- SupraVentricular TachyCardia (SVT)
		) union ( select 10030 itemid, '4270' icd_code
		) union ( select 10030 itemid, 'I471' icd_code
		
		-- Ventricular TachyCardia (VT)
		) union ( select 10031 itemid, '4271' icd_code
		) union ( select 10031 itemid, 'I472' icd_code
		
		-- Ventricular Failure(?)  (VF)
		) union ( select 10032 itemid, '42741' icd_code
		) union ( select 10032 itemid, 'I490'  icd_code
		) union ( select 10032 itemid, 'I4901' icd_code
		
		-- Asystole (flatline - dead)
		) union ( select 10033 itemid, '4275'  icd_code		-- cardiac arrest
		) union ( select 10033 itemid, '77985' icd_code		-- cardiac arrest of newborn
		
		-- Heart Block
		) union ( select 10034 itemid, '4261'  icd_code
		) union ( select 10034 itemid, '42610' icd_code
		) union ( select 10034 itemid, '42611' icd_code
		) union ( select 10034 itemid, '42612' icd_code
		) union ( select 10034 itemid, '42613' icd_code
		) union ( select 10034 itemid, '4263'  icd_code
		) union ( select 10034 itemid, '4264'  icd_code
		) union ( select 10034 itemid, '42650' icd_code
		) union ( select 10034 itemid, '42651' icd_code
		) union ( select 10034 itemid, '42652' icd_code
		) union ( select 10034 itemid, '42653' icd_code
		) union ( select 10034 itemid, '42654' icd_code
		) union ( select 10034 itemid, '4266'  icd_code
		) union ( select 10034 itemid, '74686' icd_code
		) union ( select 10034 itemid, 'I44'   icd_code
		) union ( select 10034 itemid, 'I440'  icd_code
		) union ( select 10034 itemid, 'I441'  icd_code
		) union ( select 10034 itemid, 'I442'  icd_code
		) union ( select 10034 itemid, 'I443'  icd_code
		) union ( select 10034 itemid, 'I4430' icd_code
		) union ( select 10034 itemid, 'I4439' icd_code
		) union ( select 10034 itemid, 'I444'  icd_code
		) union ( select 10034 itemid, 'I445'  icd_code
		) union ( select 10034 itemid, 'I446'  icd_code
		) union ( select 10034 itemid, 'I4460' icd_code
		) union ( select 10034 itemid, 'I4469' icd_code
		) union ( select 10034 itemid, 'I447'  icd_code
		) union ( select 10034 itemid, 'I450'  icd_code
		) union ( select 10034 itemid, 'I451'  icd_code
		) union ( select 10034 itemid, 'I4510' icd_code
		) union ( select 10034 itemid, 'I4519' icd_code
		) union ( select 10034 itemid, 'I452'  icd_code
		) union ( select 10034 itemid, 'I453'  icd_code
		) union ( select 10034 itemid, 'I454'  icd_code
		) union ( select 10034 itemid, 'I455'  icd_code
		) union ( select 10034 itemid, 'Q246'  icd_code
		
		-- Junctional Rhythm
		) union ( select 10035 itemid, '' icd_code
		)
		
	), ed_events as (
	
		-- search ED for cardiac examinations
	
		with tmp as (
			select d.subject_id, d.stay_id, ii.itemid
			from mimic_ed.diagnosis d join icd_itemid ii
			on d.icd_code = ii.icd_code
			where d.stay_id is not null 
			and d.icd_code in ( 
				select i.icd_code
				from icd_itemid i
			)
		)
		select t.subject_id, e.hadm_id, t.itemid
		from mimic_ed.edstays e join tmp t 
		on e.stay_id = t.stay_id
		
	), results as (
		-- merge hosp and ED records
		-- NOTE: ICD billing codes do not have timestamps associated with the records.
		--       Therefore we have no idea WHEN the diagnosis was made other than the visit/stay which it occurred.
		--		 We'll have to assume the diagnosis applies to the entire visit
		select c.subject_id, c.hadm_id, c.itemid, a.admittime, a.hospital_expire_flag, a.time_in, a.gap
		from ed_events c join mimic_derived.cohort a
		on c.hadm_id = a.hadm_id 
	)
	select r.subject_id, r.hadm_id, r.itemid, r.admittime, r.admittime as charttime, v.var_type, 1 as val_num, v.val_min, v.val_max, v.ref_min, v.ref_max, v.val_default, r.hospital_expire_flag, r.time_in, r.gap
	from results r join val_defaults v
	on r.itemid = v.itemid

), chart_events as (

	/******************************************
	 * Vital signs and interventions - ICU charted events
	 *******************************************/
	-- use 2-pass system to aggregate data (because it's faster)
	-- 1st pass collects all variables of interest filtered by first 48 hours after admission
	-- 2nd pass partitions data into subsets by variable type
	-- result is merged with val_defaults to inherit variable definitions from patient 0
	with vital_ids as (
		-- interventions (convert to binary)
		(         select 227579 itemid, 0 grp	-- using BiPAP [numeric] 227579=EPAP, 227580=IPAP, 227581=BiPap bpm (S/T -Back up), 227582=O2 flow, 
		) union ( select 227580 itemid, 0 grp
		) union ( select 227581 itemid, 0 grp
		) union ( select 227582 itemid, 0 grp
		) union ( select 227583 itemid, 3 grp	-- using CPAP (Constant Positive Airway Pressure).  values="On|Off"
		) union ( select 227287 itemid, 0 grp	-- using HFNC.  O2 Flow (additional cannula). values=numeric
		) union ( select 226169 itemid, 0 grp	-- using suction (clear the airways?).  values = 0|1
		-- vital signs (continuous)
		) union ( select 223835 itemid, 1 grp	-- FiO2. 223835=Fraction of Inspired O2.
		) union ( select 220045 itemid, 1 grp1	-- Heart rate
		) union ( select 223762 itemid, 1 grp	-- Temperature C
		) union ( select 223761 itemid, 1 grp	-- Temperature F.
		) union ( select 220210 itemid, 1 grp	-- Respiratory Rate
		) union ( select 220179 itemid, 1 grp	-- Blood pressure, systolic.
		) union ( select 220050 itemid, 1 grp
		) union ( select 220180 itemid, 1 grp	-- Blood pressure, diastolic
		) union ( select 220051 itemid, 1 grp
		) union ( select 220277 itemid, 1 grp	-- O2 saturation.  228232=PAR-Oxygen saturation (routine vital signs). 220277=O2 saturation pulseoxymetry (SpO2),  223770,223769=SpO2 alarms
		) union ( select 228232 itemid, 1 grp
		-- morse / braden scores (continuous)
		) union ( select 224054 itemid, 1 grp	-- Braden Sensory Perception
		) union ( select 224055 itemid, 1 grp	-- Braden Moisture
		) union ( select 224056 itemid, 1 grp	-- Braden Activity
		) union ( select 224057 itemid, 1 grp	-- Braden Mobility
		) union ( select 224058 itemid, 1 grp	-- Braden Nutrition
		) union ( select 224059 itemid, 1 grp	-- Braden Friction/Shear
		) union ( select 227341 itemid, 1 grp	-- Morse, History of falling (within 3 mnths)
		) union ( select 227342 itemid, 1 grp	-- Morse, Secondary diagnosis
		) union ( select 227343 itemid, 1 grp	-- Morse, Ambulatory aid
		) union ( select 227344 itemid, 1 grp	-- Morse, IV/Saline lock
		) union ( select 227345 itemid, 1 grp	-- Morse, Gait/Transferring
		) union ( select 227346 itemid, 1 grp	-- Morse, Mental status
		) union ( select 227348 itemid, 1 grp	-- Morse score, is Low risk (25-50) interventions
		) union ( select 227349 itemid, 1 grp	-- Morse score, is High risk (>51) interventions
		) union ( select 226104 itemid, 2 grp	-- Conscious level (AVPU).  227428=SOFA score, 226755=Glasgow Apache 2 score, 226994=Apache IV mortality prediction, 227013=GcsScore_ApacheIV Score	
		-- cardiac rhythm 
		) union ( select 220048 itemid, 4 grp	-- Cardiac Rhythm (includes: Asystole, Atrial Fibrillation, Atrial Flutter, SVT, VT, VF, Paced?, Heart Block, Junctional Rhythm)
		)
	), vitals as (
		-- select all values of interest within first 48 hours
	
		select c.subject_id, c.hadm_id, c.itemid, a.admittime, c.charttime, c.value, c.valuenum, a.hospital_expire_flag, a.time_in, a.gap
		from mimic_derived.cohort a join mimic_icu.chartevents c
		on a.subject_id = c.subject_id 
		where c.hadm_id is not null
		and c.itemid in (
			select vi.itemid
			from vital_ids vi
		) and c.hadm_id in (
			select *
			from visit_ids
		) and extract( epoch from age( c.charttime, a.admittime )) between 0 and a.icu_limit
		
	), ed_vitals as (
	
		with edstays as (
		
			-- merge cohort with edstays so hadm_id can be found in ED
			select e.subject_id, e.hadm_id, e.stay_id, e.intime, e.outtime, c.admittime, c.dischtime, c.edregtime, c.edouttime, c.ed_limit, c.gap, c.time_in, c.hospital_expire_flag
			from mimic_ed.edstays e join mimic_derived.cohort c
			on e.hadm_id = c.hadm_id
			
		)
		-- merge edstays with vitalsign so data can be associated with hadm_id
		select e.subject_id, e.hadm_id, e.stay_id, e.intime, e.outtime, e.admittime, v.charttime, e.edregtime, e.edouttime, e.ed_limit, e.gap, e.time_in,
			v.temperature, v.heartrate, v.resprate, v.o2sat, v.sbp, v.dbp, v.rhythm, e.hospital_expire_flag
		from edstays e join mimic_ed.vitalsign v
		on v.stay_id = e.stay_id
		where extract( epoch from age( v.charttime, e.edregtime )) between 0 and e.ed_limit
		
	), c_results as ( 
		-- shape and mold the subsets within the selection, then merge.
		-- we do a 2-pass system because it's faster.

		(
			-- BiPAP, EPAP, IPAP (binary variables) Must export both 'on' and 'off' states, interpreted by flow rate.
			select v.subject_id, v.hadm_id, v.itemid, v.admittime, v.charttime, (case when v.valuenum > 0 then 1 else 0 end) as val_num, v.hospital_expire_flag, v.time_in, v.gap
			from vitals v
			where v.valuenum is not null
			and v.itemid in ( 
				select vi.itemid
				from vital_ids vi
				where vi.grp = 0
			)
			
		) union (
		
			-- using CPAP (Constant Positive Airway Pressure).  values="On|Off"
			-- must parse separately because 'valuenum' is always NULL and uses value instead with text labels		
			with cpap_modes as (
				(         select 'Off' setting, 0 id
				) union ( select 'On'  setting, 1 id
				)
			)		
			select v.subject_id, v.hadm_id, v.itemid, v.admittime, v.charttime, cp.id as val_num, v.hospital_expire_flag, v.time_in, v.gap
			from vitals v join cpap_modes cp 
			on v.value = cp.setting
			and v.itemid in (
				select vi.itemid
				from vital_ids vi
				where vi.grp = 3
			)
	
		) union (
			-- Vitals and Morse/Braden scores. (continuous variables)
			select v.subject_id, v.hadm_id, v.itemid, v.admittime, v.charttime, v.valuenum as val_num, v.hospital_expire_flag, v.time_in, v.gap
			from vitals v
			where v.valuenum is not null 
			and v.itemid in ( 
				select vi.itemid
				from vital_ids vi
				where vi.grp = 1
			)
			
		) union (
			-- Conscuous level score (AVPU).  Must parse separately because it's values are text, not numeric.
				
			with avpu_scores as (
			
				-- standard scores --
				(         select 'Alert'                 score_name, 0 score
				) union ( select 'Arouse to Voice'       score_name, 1 score
				) union ( select 'Arouse to Pain'        score_name, 2 score
				) union ( select 'Unresponsive'          score_name, 3 score
				-- non-standard scores --
				) union ( select 'Lethargic'             score_name, 1 score
				) union ( select 'Awake/Unresponsive'    score_name, 2 score
				) union ( select 'Arouse to Stimulation' score_name, 2 score
				)
			)
			select v.subject_id, v.hadm_id, v.itemid, v.admittime, v.charttime, a.score as val_num, v.hospital_expire_flag, v.time_in, v.gap
			from vitals v join avpu_scores a
			on v.value = a.score_name
			where v.value is not null 
			and v.itemid in (
				select vi.itemid
				from vital_ids vi
				where vi.grp = 2
			)
			
		) union (
			-- Examinations: Cardiac Rhythm and related (binary variables)
			with cardiac_items as (
				(         select 'A Paced'                             diagnosis, 10026 itemid	-- Paced
				) union ( select 'V Paced'                             diagnosis, 10026 itemid
				) union ( select 'AV Paced'                            diagnosis, 10026 itemid
				) union ( select 'AF (Atrial Fibrillation)'            diagnosis, 10027 itemid	-- Atrial Fibrillation
				) union ( select 'A Flut (Atrial Flutter) '            diagnosis, 10028 itemid	-- Atrial Flutter
																								-- Using cardiac rhythm(?)
				) union ( select 'SVT (Supra Ventricular Tachycardia)' diagnosis, 10030 itemid	-- SupraVentricular TachyCardia (SVT)
				) union ( select 'VT (Ventricular Tachycardia) '       diagnosis, 10031 itemid	-- Ventricular TachyCardia (VT)
				) union ( select 'VF (Ventricular Fibrillation) '      diagnosis, 10032 itemid	-- Ventricular Fibrillation (VF)
				) union ( select 'Asystole'                            diagnosis, 10033 itemid	-- Asystole (Cardiac arrest)
				) union ( select '3rd AV (Complete Heart Block) '      diagnosis, 10034 itemid	-- heart block
				) union ( select 'JR (Junctional Rhythm)'              diagnosis, 10035 itemid	-- Junctional Rhythm
				)
			)
			select v.subject_id, v.hadm_id, ci.itemid, v.admittime, v.charttime, 1 as val_num, v.hospital_expire_flag, v.time_in, v.gap
			from vitals v join cardiac_items ci
			on v.value = ci.diagnosis
			where v.itemid in (
				select vi.itemid
				from vital_ids vi
				where vi.grp = 4
			)
			
		) union (
			-- ED Vitals
			(
				-- temperature
				select e.subject_id, e.hadm_id, 223762 itemid, e.edregtime as admittime, e.charttime, e.temperature as val_num, e.hospital_expire_flag, e.time_in, e.gap
				from ed_vitals e
				where e.temperature is not null
			
			) union (
				-- heartrate
				select e.subject_id, e.hadm_id, 220045 itemid, e.edregtime as admittime, e.charttime, e.heartrate as val_num, e.hospital_expire_flag, e.time_in, e.gap
				from ed_vitals e
				where e.heartrate is not null
			) union (
				-- respiratory rate
				select e.subject_id, e.hadm_id, 220210 itemid, e.edregtime as admittime, e.charttime, e.resprate as val_num, e.hospital_expire_flag, e.time_in, e.gap
				from ed_vitals e
				where e.resprate is not null
			
			) union (
				-- O2 saturation rate
				select e.subject_id, e.hadm_id, 220277 itemid, e.edregtime as admittime, e.charttime, e.o2sat as val_num, e.hospital_expire_flag, e.time_in, e.gap
				from ed_vitals e
				where e.o2sat is not null
			) union (
				-- sbp
				select e.subject_id, e.hadm_id, 220179 itemid, e.edregtime as admittime, e.charttime, e.sbp as val_num, e.hospital_expire_flag, e.time_in, e.gap
				from ed_vitals e
				where e.sbp is not null
				
			) union (
				-- dbp
				select e.subject_id, e.hadm_id, 220180 itemid, e.edregtime as admittime, e.charttime, e.dbp as val_num, e.hospital_expire_flag, e.time_in, e.gap
				from ed_vitals e
				where e.dbp is not null
			
			) union (

				-- cardiac rhythm
				(
					-- junctional rhythm
					select e.subject_id, e.hadm_id, 10026 itemid, e.edregtime as admittime, e.charttime, 1 as val_num, e.hospital_expire_flag, e.time_in, e.gap
					from ed_vitals e
					where lower( e.rhythm ) similar to '%pace%'	
				) union (
					-- Atrial Fibrillation
					select e.subject_id, e.hadm_id, 10027 itemid, e.edregtime as admittime, e.charttime, 1 as val_num, e.hospital_expire_flag, e.time_in, e.gap
					from ed_vitals e
					where lower( e.rhythm ) similar to '%(afib|atrial fib)%'	
				) union (
					-- Atrial Flutter
					select e.subject_id, e.hadm_id, 10028 itemid, e.edregtime as admittime, e.charttime, 1 as val_num, e.hospital_expire_flag, e.time_in, e.gap
					from ed_vitals e
					where lower( e.rhythm ) similar to '%flut%'	
				) union (
					-- Atrial Flutter
					select e.subject_id, e.hadm_id, 10030 itemid, e.edregtime as admittime, e.charttime, 1 as val_num, e.hospital_expire_flag, e.time_in, e.gap
					from ed_vitals e
					where lower( e.rhythm ) similar to '%svt%'
				) union (
					-- Ventricular TachyCardia
					select e.subject_id, e.hadm_id, 10031 itemid, e.edregtime as admittime, e.charttime, 1 as val_num, e.hospital_expire_flag, e.time_in, e.gap
					from ed_vitals e
					where lower( e.rhythm ) similar to '%ventricular tachycardia%'
				) union (
					-- Ventricular Fibrillation
					select e.subject_id, e.hadm_id, 10032 itemid, e.edregtime as admittime, e.charttime, 1 as val_num, e.hospital_expire_flag, e.time_in, e.gap
					from ed_vitals e
					where lower( e.rhythm ) similar to '%ventricular fibrillation%'
				) union (
					-- Asystole
					select e.subject_id, e.hadm_id, 10033 itemid, e.edregtime as admittime, e.charttime, 1 as val_num, e.hospital_expire_flag, e.time_in, e.gap
					from ed_vitals e
					where lower( e.rhythm ) similar to '%asystole%'
				) union (
					-- Heart block
					select e.subject_id, e.hadm_id, 10034 itemid, e.edregtime as admittime, e.charttime, 1 as val_num, e.hospital_expire_flag, e.time_in, e.gap
					from ed_vitals e
					where lower( e.rhythm ) similar to '%block%'
				) union (		
					-- junctional rhythm
					select e.subject_id, e.hadm_id, 10035 itemid, e.edregtime as admittime, e.charttime, 1 as val_num, e.hospital_expire_flag, e.time_in, e.gap
					from ed_vitals e
					where lower( e.rhythm ) similar to '%junctional%'
				)
			)
		)
	)
	-- merge with val_defaults to inherit variable definition
	select r.subject_id, r.hadm_id, r.itemid, r.admittime, r.charttime, v.var_type, r.val_num, v.val_min, v.val_max, v.ref_min, v.ref_max, v.val_default, r.hospital_expire_flag, r.time_in, r.gap
	from c_results r join val_defaults v 
	on r.itemid = v.itemid
	
), results as (
	/*********************************
	 * MERGE subquery results
	 *********************************/
	(
		select pid as subject_id, rid as hadm_id, itemid, cast( '1000-01-01 00:00:00.000' as timestamp ) as admittime, cast( '1000-01-01 00:00:00.000' as timestamp ) as charttime, var_type, val_num, val_min, val_max, ref_min, ref_max, val_default, 0 as hospital_expire_flag,
			cast( '1000-01-01 00:00:00.000' as timestamp ) as time_in, 0 as gap
		from val_defaults
	) union (
		select *
		from patient_chars
	) union (
		select *
		from labs
	) union (
		select *
		from medications
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
		select *
		from examinations
	) union (
		-- merge chartevents last because it's the largest set
		select *
		from chart_events
	)
)
/***********************************
 * Final output
 ***********************************/
select r.subject_id as patient_id, 
	r.hadm_id  as visit_id, 
	r.itemid   as event_id,
	cast( ((extract( epoch from age( r.charttime, r.time_in )) - r.gap ) / 3600) as INT) as "hour",
	r.var_type as var_type,
	r.val_num  as val_num,
	r.val_min  as val_min,
	r.val_max  as val_max,
	r.ref_min  as ref_min,
	r.ref_max  as ref_max,
	r.val_default as val_default,
	r.hospital_expire_flag as died
from results r join val_defaults v 
on r.itemid = v.itemid
order by subject_id asc, charttime asc, hadm_id asc;
