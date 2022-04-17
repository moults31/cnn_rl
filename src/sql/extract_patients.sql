/****************************************************************************
 * MIMIC-III data extraction script for combining timelines to predict patient mortality
 * 
 * Author: Matthew Lind
 * Date: April 17, 2022
 ****************************************************************************/
-- set schema
set search_path to mimic_iii;

with patient_ids as (

	/***********************************
	 * Patients - find all patients admitted to hospital who stayed at least 48 hours.
	 ***********************************/
	select subject_id
	from admissions a
	where extract( epoch from age( a.dischtime, a.admittime ) ) >= 172800

), chart_events as (

	/******************************************
	 * Vital signs and interventions - find vital sign events recorded during first 48 hours of a patient's stay 
	 *******************************************/
	select d.subject_id, c.itemid, d.admittime, d.dischtime, c.charttime, c.value, c.valuenum, c.valueuom, d.hospital_expire_flag
	from admissions d join chartevents c
	on d.subject_id = c.subject_id 
	where c.itemid in (
		-- vital sign itemids
		3420, 3421, 3422, 				-- FiO2
		211, 220045, 					-- heart rate
		676, 677, 223762,				-- temperature C
		678, 679, 223761,				-- temperature F
		219, 615, 618, 					-- Repiratory rate,         orig: [618, 619, 220210, 224688, 224689, 224690]
		6, 51, 455, 6701, 220179, 220050,   		-- blood pressure systolic  orig: [51, 442, 455, 6701, 224167, 225309]
		8368, 8440, 8441, 8555, 224643, 225310,		-- blood pressure diastolic
		220277,						-- O2 saturation
		
		-- intervention itemids
		454, 223900,			-- Glasgow Coma "Motor" score
		63, 64, 65, 66, 67,		-- BiPAP.  enumerated: 68
		1457, 2866, 6875, 227583, 	-- CPAP
		1768,				-- HFNC (High Flow Nasal Cannula)
		226169, 227807			-- suction (all kinds)  other: 97, 102, 107, 112, 3365, 5743, 42758, 43059, 44630, 223994, 224427, 224436, 224437, 224806, 224808, 224810, 224812, 
		
	) and c.subject_id in (
		-- ids of patients admitted to hospital and stayed for at least 48 hours.
		select *
		from patient_ids
		
	) and extract( epoch from age( c.charttime, d.admittime )) between 0 and 172800 and c.valuenum is not null
	
), labs as (

	/****************************************************
	 * Labs - find labs recorded during first 48 hours of a patient's stay.
	 *****************************************************/
	select d.subject_id, l.itemid, d.admittime, d.dischtime, l.charttime, l.value, l.valuenum, l.valueuom, d.hospital_expire_flag
	from admissions d join labevents l
	on d.subject_id = l.subject_id 
	where l.itemid in (
		-- ids of lab clinical variables of interest
		50862,			-- Albumin
		50863,			-- Alkaline Phosphatase
		50868,			-- Anion Gap
		50878,			-- Asparate Aminotransferase
		50803, 50804, 50882,	-- Bicarbonate (Carbon Dioxide)
		51006,			-- Blood Urea Nitrogen (BUN)
		50893,			-- Calcium, Total
		50902,			-- Chloride
		50809, 50931,		-- Glucose
		51222,			-- Hemoglobin
		51237,			-- International normalized Ration (INR)
		51484,			-- Ketones (Urine?)
		50813,			-- Lactate
		50956,			-- Lipase
		51250,			-- Mean Corpuscular Volume (MCV)
		50818,			-- partial pressure Carbone Dioxide (PaCO2)
		50821,			-- partial pressure Oxygen (PaO2)
		51275,			-- partial Thromboplastin Time (PTT)
		50820,			-- pH
		50970,			-- Phosphate
		51265,			-- Platelet Count
		50822, 50971, 		-- Potassium
		51277, 			-- Red Cell Distribution Width (RDW)
		50983,			-- Sodium
		50885,			-- Bilirubin, Total
		50976,			-- Protein, Total
		51002, 51003, 		-- Troponin
		51300, 51301		-- White Blood Cells (WBC)
		
	) and l.subject_id in (
		-- ids of patients admitted to hospital and stayed for at least 48 hours.
		select *
		from patient_ids
	) 
	and extract( epoch from age( l.charttime, d.admittime )) between 0 and 172800 and l.valuenum is not null

), input_events as (

	/*****************************************************
	 * Input events - merge events from CareVue (CV) and MetaVision (MV) databases for common inputevents
	 *****************************************************/

	with inputs as (
		-- Search both CareVue and MetaVision databases and extract records of interest.
		-- The fields must match those used in other tables so records can be merged.
		(
			-- CareVue
			select cv.subject_id, cv.itemid, cv.charttime, cast(cv.amount as varchar(255)) as value, cv.amount as valuenum, cv.amountuom as valueuom
			from inputevents_cv cv
			where cv.subject_id in ( 
				select * 
				from patient_ids 
			) and itemid in (
				30008, 30181, 			-- Albumin 5%
				30009, 43237, 43353, 		-- Albumin 25%
				30103,42185,42323,43009,44044,44172,44236,44819,45669,46122,46410,46418,46530,46684,	-- Fresh Frozen Plasma (FFP)  zero vs. >0
				41415,41538,41688,41704,41742,44094,45036,46776		-- lactulose
			) and cv.amount is not null
			
		) union (
			-- MetaVision
			select mv.subject_id, mv.itemid, mv.starttime as charttime, cast(mv.amount as varchar(255)) as value, mv.amount as valuenum, mv.amountuom as valueuom
			from inputevents_mv mv 
			where mv.subject_id in ( 
				select * 
				from patient_ids 
			) and itemid in (
				220864, 		-- Albumin 5%
				220862,			-- Albumin 25%
				226367, 227072		-- Fresh Frozen Plasma (FFP), zero vs. >0
			) and mv.amount  is not null
		)
	)
	-- Join input events to the admissions table to conform with data coming from other sources.
	select d.subject_id, i.itemid, d.admittime, d.dischtime, i.charttime, i.value, i.valuenum, i.valueuom, d.hospital_expire_flag
	from admissions d join inputs i
	on d.subject_id = i.subject_id
	where d.subject_id in (
		select *
		from patient_ids 
	) and extract( epoch from age( i.charttime, d.admittime )) between 0 and 172800
	and i.valuenum is not null

), output_events as (

	/***********************
	 * Output events - events for collection of samples output from the patient.
	 **********************/
	select d.subject_id, o.itemid, d.admittime, d.dischtime, o.charttime, cast( o.value as varchar(255)), o.value as valuenum, o.valueuom, d.hospital_expire_flag
	from admissions d join outputevents o 
	on d.subject_id = o.subject_id 
	where o.itemid in (
		-- Urine: CareVue
		40055, -- "Urine Out Foley"
		43175, -- "Urine ."
		40069, -- "Urine Out Void"
		40094, -- "Urine Out Condom Cath"
		40715, -- "Urine Out Suprapubic"
		40473, -- "Urine Out IleoConduit"
		40085, -- "Urine Out Incontinent"
		40057, -- "Urine Out Rt Nephrostomy"
		40056, -- "Urine Out Lt Nephrostomy"
		40405, -- "Urine Out Other"
		40428, -- "Urine Out Straight Cath"
		40086, -- Urine Out Incontinent
		40096, -- "Urine Out Ureteral Stent #1"
		40651, -- "Urine Out Ureteral Stent #2"
		-- URINE: Metavision
		226559, -- "Foley"
		226560, -- "Void"
		227510, -- "TF Residual"
		226561, -- "Condom Cath"
		226584, -- "Ileoconduit"
		226563, -- "Suprapubic"
		226564, -- "R Nephrostomy"
		226565, -- "L Nephrostomy"
		226567, -- Straight Cath
		226557, -- "R Ureteral Stent"
		226558  -- "L Ureteral Stent"
		
--		40055, 226559	-- Foley catheter placed (not sure if we want this vs. some other Foley)
		
	) and o.subject_id in (
		-- ids of patients admitted to hospital and stayed for at least 48 hours.
		select *
		from patient_ids
	) and extract( epoch from age( o.charttime, d.admittime )) between 0 and 172800 and o.value is not null

)
/*********************************
 * MERGE 
 *********************************/
(
	-- merge chart_events with input/output events
	(
		-- merge chartevents and labs
		(
			select *
			from chart_events
		) union (
			select *
			from labs
		)
	) union (
		-- merge inputs and outputs
		(
			select *
			from input_events
		) union (
			select *
			from output_events
		)	
	)
)
order by subject_id asc, charttime asc;

