/*****************************************
 * sofa_score.sql
 * 
 * Compute SOFA score for each patient visit in specified cohort
 * 
 * This is a modified SOFA score with the maximum score value for each
 * variable used over the visit, then summed for the final score for the patient.
 * Each visit is treated separately.
 ******************************************/
with visit_ids as(

	select distinct a.hadm_id
	from mimic_core.admissions a 
	where extract( epoch from age( a.dischtime, a.admittime )) >= 172800
	
), est_mortality as (
	
	(         select 0 score, 3.3   mortality
	) union ( select 1 score, 5.8   mortality
	) union ( select 2 score, 3.8   mortality
	) union ( select 3 score, 3.3   mortality
	) union ( select 4 score, 7.0   mortality
	) union ( select 5 score, 10    mortality
	) union ( select 6 score, 4.5   mortality
	) union ( select 7 score, 15.3  mortality
	) union ( select 8 score, 22.5  mortality
	) union ( select 9 score, 22.5  mortality
	) union ( select 10 score, 45.8 mortality
	) union ( select 11 score, 40   mortality
	) union ( select 12 score, 45.8 mortality
	) union ( select 13 score, 60   mortality
	) union ( select 14 score, 51.5 mortality
	) union ( select 15 score, 82.0 mortality
	) union ( select 16 score, 87.3 mortality
	) union ( select 17 score, 90   mortality
	) union ( select 18 score, 90   mortality
	) union ( select 19 score, 90   mortality
	) union ( select 20 score, 90   mortality
	) union ( select 21 score, 90   mortality
	) union ( select 22 score, 90   mortality
	) union ( select 23 score, 90   mortality
	) union ( select 24 score, 90   mortality
	)
	
), sofa_data as (

	/*****************************************
	 * collect sofa variables
	 * 
	 * (accessing chartevents is really slow, so we'll aggregate what we need
	 * and do all processing downstream where it'll be much faster).
	 ******************************************/
	(
		select c.subject_id, c.hadm_id, c.itemid, c.charttime, c.value, c.valuenum
		from mimic_icu.chartevents c join mimic_core.admissions a3 
		on c.hadm_id = a3.hadm_id 
		where c.itemid in (
			223835,					-- FiO2
			220052, 225312,			-- Arterial Blood pressure mean (MAP?)
			225690					-- bilirubin, total (labs)
		)
		and c.hadm_id in (
			select *
			from visit_ids
		)
		and extract( epoch from age( c.charttime, a3.admittime )) between 0 and 172800
		
	) union ( 
		select l.subject_id, l.hadm_id, l.itemid, l.charttime, l.value, l.valuenum
		from mimic_hosp.labevents l join mimic_core.admissions a2 
		on l.hadm_id = a2.hadm_id 
		where l.itemid in ( 
			50821,		-- Partial Pressure Oxygen (PaO2)
			50885,		-- Bilirubin (total)
			50912,		-- Creatinine 
			51265		-- Platelets count (primary platelets stat)
		)
		and l.valuenum is not null
		and l.hadm_id in (
			select *
			from visit_ids
		)
		and extract( epoch from age( l.charttime, a2.admittime )) between 0 and 172800
		
	) union ( 
		-- Input events (hypotension)
		select i.subject_id, i.hadm_id, i.itemid, i.starttime as charttime, NULL as value, i.amount as valuenum
		from mimic_icu.inputevents i join mimic_core.admissions a 
		on i.hadm_id = a.hadm_id 
		where i.itemid in (
			221653,				-- Dobutamine		
			221662,  			-- Dopamine
			221906				-- Norepinephrine
		)
		and i.hadm_id in (
			select *
			from visit_ids
		)
		and extract( epoch from age( i.starttime, a.admittime )) between 0 and 172800
		
	) union ( 
		-- Output events (urine)
		select a.subject_id, o.hadm_id, o.itemid, o.charttime, null as value, o.value as valuenum
		from mimic_icu.outputevents o join mimic_core.admissions a 
		on o.hadm_id = a.hadm_id 
		where o.itemid in ( 
			226627, 226631, 227489		-- Urine: OR, PACU, volume
		)
		and o.hadm_id in (
			select *
			from visit_ids
		)
		and extract( epoch from age( o.charttime, a.admittime )) between 0 and 172800
	)
		
), sofa_variables as (

	/**************************
	 * Compute sofa Score for each variable
	 **************************/
	(
		-- Respiration (PaO2 / FiO2)
		-- need to compute the ratio
		with respiration_avg as ( 
			-- compute average PaO2 and FiO2 over the visit, otherwise we cannot compute the ratio
			select s.hadm_id, s.itemid, avg( s.valuenum ) as value
			from sofa_data s
			group by s.hadm_id, s.itemid
			
		), respiration_ratio as (
		
			-- compute the respiration ratio
			select a.hadm_id, (case when b.value = 0 then 0 else floor(a.value * 100 / b.value) end) as ratio
			from respiration_avg a join respiration_avg b 
			on a.hadm_id = b.hadm_id
			where a.itemid = 50821 and b.itemid = 223835
		)
		-- score the results
		select r.hadm_id, 0 as itemid, (case when r.ratio is null then 0
			when r.ratio < 100 then 4
			when r.ratio < 200 then 3
			when r.ratio < 300 then 2
			when r.ratio < 400 then 1
			else 0
			end) as value
		from respiration_ratio r
		
	) union (
	
		-- Coagulation (Platelets)
		select m.hadm_id, 1 as itemid, 
			(case
				when m.valuenum is null then 0 
				when m.valuenum < 20  then 4
				when m.valuenum < 50  then 3
				when m.valuenum < 100 then 2
				when m.valuenum < 150 then 1
				else 0 
			end) as value
		from sofa_data m
		where m.itemid = 51265
	
	) union (
		-- Liver (Bilirubin)
		select m.hadm_id, 2 as itemid, 
			(case
				when m.valuenum is null then 0 
				when m.valuenum < 1.2 then 0
				when m.valuenum < 2   then 1
				when m.valuenum < 6   then 2
				when m.valuenum < 12  then 3
				else 4
			end) as value
		from sofa_data m 
		where itemid in (
			50885, 225690
		)
	
	) union (
		-- Cardiovascular (Hypotension)
		with cardio_scores as (
			(
				-- Mean Arterial Pressure (MAP)
				select m.hadm_id, m.itemid,
					(case
						when m.valuenum < 70 then 1
						else 0
					end) as value
				from sofa_data m
				where itemid in (
					220052, 225312	-- MAP (Mean arterial pressure)
				)
				
			) union ( 
				-- Dopamine
				select m.hadm_id, m.itemid,
					(case
						when m.valuenum < 5 then 2
						when m.valuenum > 15 then 4
						else 3
					end) as value
				from sofa_data m
				where itemid = 221662
		
			) union (
				-- Dobutamine
				select m.hadm_id, m.itemid,
					(case
						when m.valuenum > 0 then 2
						else 0
					end) as value
				from sofa_data m
				where itemid = 221653
				
			) union (
				-- Norepinephrine
				select m.hadm_id, m.itemid,
					(case
						when m.valuenum < 0.1 then 3
						else 4
					end) as value
				from sofa_data m
				where itemid = 221906
			)
		)
		select c.hadm_id, 3 as itemid, max( c.value ) as value
		from cardio_scores c
		group by c.hadm_id
	
	) union (
		-- Glasgow Coma Score	
		with gcs_variables as (
		
			-- Glasgow score components
			-- we include the 'minute' to ensure the Eye, Motor, and Verbal scores are grouped by timestamp
			-- as patients often had multiple scores recorded throughout their stay, sometimes only minutes apart.
			select c.hadm_id, c.valuenum, floor( extract( epoch from age (c.charttime, a.admittime)) / 60 ) as "minute" 
			from mimic_icu.chartevents c join mimic_core.admissions a 
			on c.hadm_id = a.hadm_id 
			where c.itemid in (
				220739, 223901, 223900	-- Full Glasgow Coma Scale
			)
			and c.hadm_id in (
				select *
				from visit_ids
			)
			and extract( epoch from age( c.charttime, a.admittime )) between 0 and 172800
	
		), gcs_total as (
		
			-- Total score by minute
			select g.hadm_id, sum( g.valuenum ) as score, 'Total' as score_name, g.minute
			from gcs_variables g
			group by g.hadm_id, g.minute
			
		), gcs_results as ( 
		
			-- get max score per visit
			select g.hadm_id, max( g.score ) as value
			from gcs_total g
			group by g.hadm_id
		)
		select r.hadm_id, 4 as itemid,
			(case
				when r.value is null then 0 
				when r.value <  6 then 4
				when r.value < 10 then 3
				when r.value < 13 then 2
				when r.value < 15 then 1
				else 0 
			end) as value
		from gcs_results r 
	
	) union (
		-- Renal
		with renal_scores as (
			(
				-- Creatinine
				select m.hadm_id, 5 as itemid,
					(case
						when m.valuenum is null then 0 
						when m.valuenum < 1.2 then 0
						when m.valuenum < 2   then 1
						when m.valuenum < 3.5 then 2
						when m.valuenum < 5   then 3
						else 4 
					end) as value
				from sofa_data m 
				where m.itemid = 50912
			) union (
				-- Urine output
				select m.hadm_id, 6 as itemid,
					(case
						when m.valuenum < 200 then 4
						when m.valuenum < 500 then 3
						else 0
					end) as value
				from sofa_data m
				where m.itemid in (
					226627, 226631, 227489	-- urine output (mL)
				)
			)
		)
		select r.hadm_id, 5 as itemid, max( r.value ) as value
		from renal_scores r
		group by r.hadm_id
	)
	
), sofa_max as ( 

	-- find largest score recorded for each variable
	select m.hadm_id, m.itemid, max( m.value ) as max_score
	from sofa_variables m
	group by m.hadm_id, m.itemid
	
), sofa_results as (

	-- compute sofa score per patient visit
	select m.hadm_id, sum( m.max_score ) as score
	from sofa_max m
	group by m.hadm_id
	
), final_results as (
	-- final results
	(
		-- scored visits
		select a.subject_id, r.hadm_id, r.score, a.hospital_expire_flag
		from sofa_results r join mimic_core.admissions a 
		on r.hadm_id = a.hadm_id
	) union (
		-- unscored visits
		select a2.subject_id, a2.hadm_id, 0 score, a2.hospital_expire_flag
		from mimic_core.admissions a2
		where a2.hadm_id not in (
			select s.hadm_id
			from sofa_results s
		)
	)
)
-- final output
select f.subject_id as patient_id, f.hadm_id as visit_id, f.score as sofa_score, e.mortality as est_mortality, f.hospital_expire_flag as died
from final_results f join est_mortality e 
on f.score = e.score
order by f.subject_id asc, f.hadm_id asc ;

