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

with patient_ids as (

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
		select a.subject_id, a.hadm_id, p.itemid, a.admittime, p.starttime, 0 as var_type, (case when p.value is null or p.value <> 1 then 0 else 1 end) as val_num, 0 as val_min, 1 as val_max, 0 as ref_min, 0 as ref_max, 0 as val_default, a.hospital_expire_flag 
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
			226104,						-- Conscious level (AVPU).  227428=SOFA score, 226755=Glasgow Apache 2 score, 226994=Apache IV mortality prediction, 227013=GcsScore_ApacheIV Score	
			
			-- intervention itemids
			223900						-- Glasgow Coma "Motor" score
	
		) and c.subject_id in (
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


