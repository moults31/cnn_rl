/****************************************************************************
 * set_cohort_icu_ed
 * 
 * Creates a custom version of mimic_core.admissions with additional information
 * useful in aggregating data within a specific time range.  In this case, 
 * builds a table of patient admissions data where the combined stay across
 * the ICU and ED was at least 48 hours in duration.  The results are stored
 * in mimic_derived.cohort and intended to be joined with data from 
 * other tables to isolate variables that fit the visit's time window.
 * 
 * Author: Matthew Lind
 * Date: May 5, 2022
 */
set search_path to mimic_iv;

-- Removed previous version of table (if it exists)
drop table if exists mimic_derived.cohort;

-- Create table
create table mimic_derived.cohort 
(
	subject_id		INTEGER NOT NULL,
	hadm_id			INTEGER NOT NULL,
	visit_type		INTEGER not null,
	admittime		TIMESTAMP NOT NULL,
	dischtime		TIMESTAMP,
	icu_duration	BIGINT,
	icu_limit		BIGINT,
	edregtime		TIMESTAMP,
	edouttime		TIMESTAMP,	
	ed_duration		BIGINT,
	ed_limit		BIGINT,
	gap				BIGINT,
	time_in			TIMESTAMP,
	time_out		TIMESTAMP,
	hospital_expire_flag SMALLINT
);

with rogue_visits as (

	select a.hadm_id 
	from mimic_core.admissions a 
	where (a.dischtime <= a.admittime) or (a.edregtime is not null and a.edregtime > a.edouttime)

), cohort as (

	--	Aggregate by visit type:
	--
	--	0 = hospital only
	--	1 = ed only
	--	2 = disjoint, hospital before ed
	--	3 = disjoint, ed before hospital
	--	4 = overlap, hospital before ed
	--	5 = overlap, ed before hospital
	--	6 = nested, ed inside of hospital
	--	7 = nested, hospital inside of ed
	(
		-- hospital only
		select a.subject_id, 
			a.hadm_id,
			a.admittime as icu_in, 
			a.dischtime as icu_out, 
			extract( epoch from age( a.dischtime, a.admittime )) as icu_duration,
			null as ed_in,
			null as ed_out,
			0 as ed_duration,
			0 as visit_type,
			172800 as time_limit,
			a.hospital_expire_flag 
		from mimic_core.admissions a 
		where a.edregtime is null
		and extract( epoch from age( a.dischtime, a.admittime )) >= 172800
		and a.hadm_id not in (
			select *
			from rogue_visits
		)
		
	) union (
		-- hospital and ed
		select a.subject_id, 
			a.hadm_id, 
			a.admittime as icu_in, 
			a.dischtime as icu_out, 
			extract( epoch from age( a.dischtime, a.admittime )) as icu_duration,
			a.edregtime as ed_in,
			a.edouttime as ed_out,
			extract( epoch from age( a.edouttime, a.edregtime )) as ed_duration,
			(case
				-- list complex criteria first because the other way around results in false labels being applied
				when (a.edregtime <= a.admittime) and (a.dischtime <= a.edouttime) then 7	-- nested, hospital insside ed				
				when (a.admittime <= a.edregtime) and (a.edouttime <= a.dischtime) then 6	-- nested, ed inside hospital
				when (a.edregtime <= a.admittime) and (a.admittime <= a.edouttime) and (a.edouttime <= a.dischtime) then 5	-- overlap, ed before hospital
				when (a.admittime <= a.edregtime) and (a.edregtime <= a.dischtime) and (a.dischtime <= a.edouttime) then 4	-- overlap, hospital before ed
				when (a.edouttime <= a.admittime) then 3	-- ed, then hospital																
				when (a.dischtime <= a.edregtime) then 2	-- hospital, then ed
--				when e.hadm_id is null then 1	-- ed only
				else 1
			end) as visit_type,
			172800 as time_limit,
			a.hospital_expire_flag 
		from mimic_core.admissions a
		where a.edregtime is not null
		and a.hadm_id not in (
			select *
			from rogue_visits
		)
	)
	
), visits as (

	-- Compute in/out times of icu, ed, and overall visit.
	-- Include gaps in stays, differentials between stay checkpoints, and max interval allowed in stay.
	(
		-- 0: hospital only
		select c.subject_id, c.hadm_id, c.icu_in, c.icu_out, c.icu_duration, c.ed_in, c.ed_out, c.ed_duration, c.visit_type,
			c.icu_duration as duration, 
			0 as gap,  
			c.icu_in  as time_in,
			c.icu_out as time_out,
			c.time_limit as icu_limit,
			0 as ed_limit,
			c.hospital_expire_flag
		from cohort c
		where c.visit_type = 0
	) union ( 
		-- 1: ed only
		select c.subject_id, c.hadm_id, c.icu_in, c.icu_out, c.icu_duration, c.ed_in, c.ed_out, c.ed_duration, c.visit_type,
			c.ed_duration as duration, 
			0 as gap, 
			c.ed_in as time_in,
			c.ed_out as time_out,
			0 as icu_limit,
			c.time_limit as ed_limit,
			c.hospital_expire_flag
		from cohort c
		where c.visit_type = 1
	) union ( 
		-- 2: disjoint, hospital before ed
		select c.subject_id, c.hadm_id, c.icu_in, c.icu_out, c.icu_duration, c.ed_in, c.ed_out, c.ed_duration, c.visit_type,
			(c.icu_duration + c.ed_duration) as duration, 
			extract( epoch from age( c.ed_in, c.icu_out )) as gap, 
			c.icu_in as time_in,
			c.ed_out as time_out,
			c.time_limit as icu_limit,
			(case 
				when extract( epoch from age( c.ed_in, c.icu_in )) >= c.time_limit then 0
				else c.time_limit - icu_duration
			end) as ed_limit,
			c.hospital_expire_flag
		from cohort c
		where c.visit_type = 2
	) union ( 
	
		-- 3: disjoint, ed before hospital
		select c.subject_id, c.hadm_id, c.icu_in, c.icu_out, c.icu_duration, c.ed_in, c.ed_out, c.ed_duration, c.visit_type,
			(c.icu_duration + c.ed_duration) as duration, 
			extract( epoch from age( c.icu_in, c.ed_out )) as gap, 
			c.ed_in   as time_in,
			c.icu_out as time_out,
			(case 
				when c.ed_duration >= c.time_limit then 0
				else c.time_limit - c.ed_duration
			end) as icu_limit,
			c.time_limit as ed_limit,
			c.hospital_expire_flag
		from cohort c
		where c.visit_type = 3
		
	) union ( 
		-- 4: overlap, hospital before ed
		select c.subject_id, c.hadm_id, c.icu_in, c.icu_out, c.icu_duration, c.ed_in, c.ed_out, c.ed_duration, c.visit_type,
			extract( epoch from age( c.ed_out, c.icu_in )) as duration, 
			0 as gap, 
			c.icu_in as time_in,
			c.ed_out as time_out,
			c.time_limit as icu_limit,
			(case 
				when extract( epoch from age( c.ed_in, c.icu_in )) >= c.time_limit then 0
				else c.time_limit - extract( epoch from age( c.ed_in, c.icu_in ))
			end) as ed_limit,
			c.hospital_expire_flag
		from cohort c
		where c.visit_type = 4
	) union ( 
		-- 5: overlap, ed before hospital
		select c.subject_id, c.hadm_id, c.icu_in, c.icu_out, c.icu_duration, c.ed_in, c.ed_out, c.ed_duration, c.visit_type,
			extract( epoch from age( c.icu_out, c.ed_in )) as duration, 
			0 as gap, 
			c.ed_in as time_in,
			c.icu_out as time_out,
			(case 
				when extract( epoch from age( c.icu_in, c.ed_in )) >= c.time_limit then 0
				else c.time_limit - extract( epoch from age( c.icu_in, c.ed_in ))
			end) as icu_limit,
			c.time_limit as ed_limit,
			c.hospital_expire_flag
		from cohort c
		where c.visit_type = 5
	) union ( 
		-- 6: nested, ed inside of hospital
		select c.subject_id, c.hadm_id, c.icu_in, c.icu_out, c.icu_duration, c.ed_in, c.ed_out, c.ed_duration, c.visit_type,
			c.icu_duration as duration, 
			0 as gap, 
			c.icu_in  as time_in,
			c.icu_out as time_out,
			c.time_limit as icu_limit,
			(case 
				when extract( epoch from age( c.ed_in, c.icu_in )) >= c.time_limit then 0
				else c.time_limit - extract( epoch from age( c.ed_in, c.icu_in ))
			end) as ed_limit,
			c.hospital_expire_flag
		from cohort c
		where c.visit_type = 6
	) union ( 
		-- 7: nested, hospital inside of ed
		select c.subject_id, c.hadm_id, c.icu_in, c.icu_out, c.icu_duration, c.ed_in, c.ed_out, c.ed_duration, c.visit_type,
			c.ed_duration as duration, 
			0 as gap, 
--			extract( epoch from age( c.icu_in, c.ed_in )) as diff,
			c.ed_in  as time_in,
			c.ed_out as time_out,
			(case 
				when extract( epoch from age( c.icu_in, c.ed_in )) >= c.time_limit then 0
				else c.time_limit - extract( epoch from age( c.icu_in, c.ed_in ))
			end) as icu_limit,
			c.time_limit as ed_limit,
			c.hospital_expire_flag
		from cohort c
		where c.visit_type = 7
	)
)
-- populate the table with the results
insert into mimic_derived.cohort(
	subject_id, 
	hadm_id, 
	visit_type, 
	admittime, 
	dischtime, 
	icu_duration, 
	icu_limit, 
	edregtime, 
	edouttime, 
	ed_duration, 
	ed_limit, 
	gap, 
	time_in, 
	time_out, 
	hospital_expire_flag
)
select v.subject_id, v.hadm_id, v.visit_type, v.icu_in as admittime, v.icu_out as dischtime, v.icu_duration, v.icu_limit, v.ed_in as edregtime, v.ed_out as edouttime, v.ed_duration, v.ed_limit, v.gap, v.time_in, v.time_out, v.hospital_expire_flag
from visits v
where (extract( epoch from age( v.time_out, v.time_in )) - v.gap) >= 172800
order by v.subject_id asc, v.time_in asc;


