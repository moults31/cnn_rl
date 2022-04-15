-- NB: Meant to be run manually in a PostgreSQL-compatible GUI client

-- only run if these views already exist.
drop view patient_ids;
drop view vitals;
drop view labs;
drop view result;

-- 1. find all patients admitted to hospital who stayed at least 48 hours.
create view patient_ids as
	select subject_id
	from admissions a
	where extract( epoch from age( a.dischtime, a.admittime ) ) >= 172800


-- 2. find vital sign chart events recorded during first 48 hours of a patient's stay 
create view vitals as
select d.subject_id, c.itemid, d.admittime, d.dischtime, c.charttime, c.value, c.valuenum, c.valueuom, d.hospital_expire_flag
from admissions d join chartevents c
on d.subject_id = c.subject_id 
where c.itemid in (
	-- ids of vital sign clinical variables of interest
	3420, 3421, 3422, 							-- FiO2
	211, 220045, 								-- heart rate
	676, 677, 8537, 223762,						-- temperature C
	678, 679, 223761,							-- temperature F
	618, 619, 220210, 224688, 224689, 224690,	-- respiratory rate
	51, 442, 455, 6701, 224167, 225309,			-- blood pressure systolic
	8368, 8440, 8441, 8555, 224643, 225310,		-- blood pressure diastolic
	220277										-- O2 saturation
) and c.subject_id in (
	-- ids of patients admitted to hospital and stayed for at least 48 hours.
    -- 2, 3, 4              -- for debugging/testing in place of select query on next lines.
	select *
	from patient_ids
) and extract( epoch from age( c.charttime, d.admittime )) between 0 and 172800 and c.valuenum is not null
order by c.subject_id asc, c.charttime asc ;




-- 3. find labs recorded during first 48 hours of a patient's stay.
create view labs as
select d.subject_id, l.itemid, d.admittime, d.dischtime, l.charttime, l.value, l.valuenum, l.valueuom, d.hospital_expire_flag
from admissions d join labevents l
on d.subject_id = l.subject_id 
where l.itemid in (
	-- ids of lab clinical variables of interest
	50983, 50971, 50882, 50868, 50809,
	50893, 51006, 50970, 50976, 50862,
	50885, 50878, 50863, 51301, 51222,
	51265, 50813, 51002, 51003, 50820,
	51484, 50902, 51237, 50956, 51250,
	50818, 50821, 51275, 51277
) and l.subject_id in (
	-- ids of patients admitted to hospital and stayed for at least 48 hours.
    -- 2, 3, 4        -- limit to small patient cohort for testing/debugging instead of select query on next lines
	select *
	from patient_ids
) 
and extract( epoch from age( l.charttime, d.admittime )) between 0 and 172800 and l.valuenum is not null
order by l.subject_id asc, l.charttime asc ;


-- 4. merge vitals view with labs view to form the final result
create view result as
(
	select *
	from vitals v
) union (
	select *
	from labs l
)

--=============================================================
-- verify everything worked
select *
from vitals 
where subject_id < 10   -- limit output to first 10 patient ids

select *
from labs 
where subject_id < 10   --limit output to first 10 patient ids
--==============================================================

-- dump to .csv here
-- 5. everything (this could take a while if it's the full 50K patient cohort)
select *
from result
order by subject_id asc, charttime asc