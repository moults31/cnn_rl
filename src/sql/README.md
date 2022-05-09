# Exporting patient data

The SQL scripts in this directory can be used to aggregate and export patient data for use in CNN_RL deep learning framework. 

## Set patient cohort

The first step is to set the patient cohort so the export script knows what data to aggregate.  The patient cohort is set by a choice of scripts:

__set_patient_cohort_icu.sql__: Defines cohort as patients with a stay of at least 48 hours based on time of admission to the ICU.

__set_patient_cohort_icu_ed.sql__: Defines cohort as patients with a stay of at least 48 hours based on time of admission to the ICU or ED - whichever occurs first.  

In the latter case, the 48 hour interval is only counted for hours which the patient is actually in the hospital.  For example, if the patient first visits the ED at 12:00 pm and is discharged at 3:00 pm, that counts as 3 hours out of the 48 hour interval.  If the patient is later admitted to the ICU as part of the same visit (as defined in the mimic_core.admissions table), then data will be aggregated for the next 45 hours until the 48 hour interval is satisfied or the patient is discharged - whichever occurs first.  Data timestamped beyond the 45th hour after admission to the ICU is ignored.  There are no visits (that we know of) where a patient visits the ED and/or ICU more than once apiece (no 'ins and outs').

The implication needs to be carefully considered because most ED visits last only a few hours, but ICU visits can last for weeks or months.  It is not uncommon for the gap between exiting the ED and being admitted to the ICU (or vice versa) spanning days or weeks.  This means the transition of data between departments may not be accurate with regards to continuity, and the patient's health can change considerably.  

To set the patient cohort, execute the set_cohort_xxx.sql script of choice. The cohort will be defined in the table _mimic_derived.cohort_.  All other data processing scripts source this table to do work, therefore it's important to set the patient cohort before proceeding to the next steps.

## Export patient data

The next step is to aggregate the patient data.  This is expected to be performed interactively in a postgreSQL IDE such as DBeaver, and exported to .csv (comma separated value) file using the file export tool.  The first row of the resulting .csv should include the column names as they will be needed by the parser to generate the images.

Patience will need to be exercised as the MIMIC-IV database is quite large and the export process can take several minutes to complete.

## Export clinical scores

After the patient data is exported, the clinical scores (MEWS, SOFA, ...) should be exported as they will become the ground truth labels for predictions in deep learning benchmarks.

__mews_score.sql__: Aggregates MEWS (Modified Early Warning System) components scores, and tabulates the composite score along with warning if the score exceeds the MEWS recommendation (>= 3 points, indicating the patient requires immediate medical attention).

__sofa_score.sql__: Aggregates SOFA (Sepsis Organ Failure Assessment) component scores, and tabultes the composite score, and estimated mortality for the tabulated score.  

Both scripts depend on mimic_derived.cohort being defined using one of the set_patient_cohort_xxx.sql scripts.  Failure to set the cohort will likely result in errors.
