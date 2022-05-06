/*****************************************
 * mews_score.sql
 * 
 * Compute MEWS score for each patient visit in specified cohort
 * 
 * This is a modified MEWS score with the maximum score value for each
 * variable used over the visit, then summed for the final score for the patient.
 * Each visit is treated separately.
 ******************************************/

with visit_ids as(

	select distinct c.hadm_id
	from mimic_derived.cohort c 
	
), mews_data as (

	/*****************************************
	 * collect MEWS variables
	 * 
	 * (accessing chartevents is really slow, so we'll aggregate what we need
	 * and do all processing downstream where it'll be much faster).
	 ******************************************/
	(
		select c.subject_id, c.hadm_id, c.itemid, c.charttime, c.value, c.valuenum
		from mimic_icu.chartevents c join mimic_core.admissions a 
		on c.hadm_id = a.hadm_id 
		where c.itemid in (
			220210,			-- respiratory rate
			220045,			-- hear rate
			220179, 220050,	-- systolic blood pressure
			226104,			-- Conscious level (AVPU)
			223761,	223762	-- temperature C/F
		)
		and c.hadm_id in (
			select *
			from visit_ids
		)
		and extract( epoch from age( c.charttime, a.admittime )) between 0 and 172800
		
	) union (
		-- Hourly Urine (for 2 hours)
		select o.subject_id, o.hadm_id, o.itemid, o.charttime, NULL as value, o.value as valuenum
		from mimic_icu.outputevents o join mimic_core.admissions a 
		on o.hadm_id = a.hadm_id 
		where itemid in (
			226627, 	-- OR
			226631,		-- PACU
			227489,		-- irrigant output
			226559		-- Foley catheter output
		)
		and o.hadm_id in (
			select *
			from visit_ids
		) 
		and extract( epoch from age( o.charttime, a.admittime )) between 0 and 172800
	)
		
), mews_variables as (

	/**************************
	 * Compute MEWS Score for each variable
	 **************************/
	(
		-- respiratory rate (breaths per minute)
		select m.subject_id, m.hadm_id, 0 as itemid, m.charttime, 
			(case
				when m.valuenum is null or m.valuenum <= 0 then 0 
				when m.valuenum <= 8 then 2
				when m.valuenum between 9  and 14 then 0
				when m.valuenum between 15 and 20 then 1
				when m.valuenum between 21 and 29 then 2
				when m.valuenum >= 30 then 3
				else 0 
			end) as value
		from mews_data m 
		where itemid = 220210
		
	) union (
	
		-- heart rate (beats per minute)
		select m.subject_id, m.hadm_id, 1 as itemid, m.charttime, 
			(case
				when m.valuenum is null or m.valuenum < 0 then 0 
				when m.valuenum < 40 then 2
				when m.valuenum between 40  and 50  then 1
				when m.valuenum between 51  and 100 then 0
				when m.valuenum between 101 and 110 then 1
				when m.valuenum between 111 and 129 then 2
				when m.valuenum > 129 then 3
				else 0 
			end) as value
		from mews_data m 
		where itemid = 220045
	
	) union (
		-- blood pressure, systolic
		select m.subject_id, m.hadm_id, 2 as itemid, m.charttime, 
			(case
				when m.valuenum is null or m.valuenum <= 0 then 0 
				when m.valuenum < 71 then 3
				when m.valuenum <= 80  then 2
				when m.valuenum <= 100 then 1
				when m.valuenum <= 200 then 0
				when m.valuenum > 200 then 3
				else 0 
			end) as value
		from mews_data m 
		where itemid in (
			220179, 220050
		)
	
	) union (
		-- Conscious level (AVPU)
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
		select m.subject_id, m.hadm_id, 3 as itemid, m.charttime, a.score as value
		from mews_data m  join avpu_scores a 
		on m.value = a.score_name
		where itemid in (
			226104
		)
	
	) union (
		-- Temperature C
		select m.subject_id, m.hadm_id, 4 as itemid, m.charttime,
			(case
				when m.valuenum is null then 0 
				when m.valuenum <  35.0 then 2
				when m.valuenum <= 36.0 then 1
				when m.valuenum <= 38.0 then 0
				when m.valuenum <= 38.6 then 1
				when m.valuenum >  38.6 then 2
				else 0 
			end) as value
		from mews_data m  
		where itemid = 223762		-- temperature C
	
	) union (
		-- Temperature F
		select m.subject_id, m.hadm_id, 4 as itemid, m.charttime,
			(case
				when m.valuenum is null   then 0 
				when m.valuenum <  95.0   then 2
				when m.valuenum <= 96.8   then 1
				when m.valuenum <= 100.4  then 0
				when m.valuenum <= 101.48 then 1
				when m.valuenum >  101.48 then 2
				else 0 
			end) as value
		from mews_data m 
		where itemid = 223761 	-- temperature F
	
	) union (
		-- Hourly Urine (for 2 hours)
		select m.subject_id, m.hadm_id, 5 as itemid, m.charttime, 
			(case
				when m.valuenum is null then 0 
				when m.valuenum < 10 then 3
				when m.valuenum < 30 then 2
				when m.valuenum < 45 then 1
				else 0 
			end) as value
			
		from mews_data m 
		where itemid in (
			226627, 	-- OR
			226631,		-- PACU
			227489,		-- irrigant output
			226559		-- Foley catheter output
		)
	)
	
), mews_max as ( 

	-- find largest score recorded for each variable
	select m.hadm_id, m.itemid, max( m.value ) as max_score
	from mews_variables m
	group by m.hadm_id, m.itemid
	
), mews_results as (

	-- compute MEWS score per patient visit
	select m.hadm_id, sum( m.max_score ) as score
	from mews_max m
	group by m.hadm_id
	
), final_results as (
	-- merge results into full patient cohort
	(
		-- scored visits
		select a.subject_id, r.hadm_id, r.score
		from mews_results r join mimic_core.admissions a 
		on r.hadm_id = a.hadm_id
	) UNION (
		-- unscored visits
		SELECT a.subject_id, a.hadm_id, 0 AS score
		FROM mimic_core.admissions a
		WHERE a.hadm_id NOT IN (
			SELECT m.hadm_id
			FROM mews_results m
		)
	)
)
SELECT a.subject_id as patient_id, r.hadm_id as visit_id, r.score as mews_score, (case when r.score >= 4 then 1 else 0 end) as mews_warning, a.hospital_expire_flag as died
FROM final_results r join mimic_core.admissions a
on r.hadm_id = a.hadm_id
ORDER BY r.subject_id ASC, r.hadm_id ASC;

