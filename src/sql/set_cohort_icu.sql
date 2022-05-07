/****************************************************************************
 * set_cohort_icu
 * 
 * Creates a custom version of mimic_core.admissions with additional information
 * useful in aggregating data within a specific time range.  In this case, 
 * builds a table of patient admissions data where the stay across
 * the ICU at least 48 hours in duration.  The results are stored
 * in mimic_derived.cohort and intended to be joined with data from 
 * other tables to isolate variables that fit the visit's time window.
 * 
 * Author: Matthew Lind
 * Date: May 5, 2022
 *******************************************************************************/


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

	-- hospital only
	select a.subject_id, 
		a.hadm_id,
		a.admittime as icu_in, 
		a.dischtime as icu_out, 
		extract( epoch from age( a.dischtime, a.admittime )) as icu_duration,
		a.edregtime as ed_in,
		a.edouttime as ed_out,
		0 as ed_duration,
		0 as visit_type,
		172800 as time_limit,
		a.hospital_expire_flag 
	from mimic_core.admissions a 
	where extract( epoch from age( a.dischtime, a.admittime )) >= 172800
	and a.hadm_id not in (
		select *
		from rogue_visits
	)
	
), visits as (

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


