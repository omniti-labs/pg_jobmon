\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

SELECT set_config('search_path', 'jobmon, dblink, tap', false);

SELECT plan(6);

SELECT jobmon_test_jobs_normal();

SELECT results_eq('SELECT job_name, status FROM job_log ORDER BY job_id' 
    , $$VALUES('PG_JOBMON TEST JOB NEVER FINISHED', NULL)
        , ('PG_JOBMON TEST GOOD JOB', 'OK')
        , ('PG_JOBMON TEST WARNING JOB', 'WARNING')
        , ('PG_JOBMON TEST BAD JOB', 'CRITICAL')
        , ('PG_JOBMON TEST SQL JOB', 'OK')
        , ('PG_JOBMON TEST NON-CONFIG BAD JOB', 'CRITICAL')
        , ('PG_JOBMON TEST NON-CONFIG BAD JOB', 'CRITICAL')
        , ('PG_JOBMON TEST NON-CONFIG BAD JOB', 'CRITICAL')$$
    , 'Checking job_log values');

SELECT results_eq('SELECT action, status, message FROM jobmon.job_detail WHERE job_id = (SELECT job_id FROM jobmon.job_log WHERE job_name = ''PG_JOBMON TEST GOOD JOB'') ORDER BY step_id ASC'
    , $$VALUES('Test step 1', 'OK', 'Successful Step 1')
        , ('Test step 2', 'OK', 'Rows affected: 2')
        , ('Test step 3', 'OK', 'Successful Step 3')$$
    , 'Checking GOOD JOB details');

SELECT results_eq('SELECT action, status, message FROM jobmon.job_detail WHERE job_id = (SELECT job_id FROM jobmon.job_log WHERE job_name = ''PG_JOBMON TEST WARNING JOB'') ORDER BY step_id ASC'
    , $$VALUES('Test step 1', 'OK', 'Successful Step 1')
        , ('Test step 2', 'WARNING', 'Failed Step 2')
        , ('Test step 3', 'CRITICAL', 'ERROR: column "col3" does not exist')$$
    , 'Checking WARNING JOB details');

SELECT results_eq('SELECT action, status, message FROM jobmon.job_detail WHERE job_id = (SELECT job_id FROM jobmon.job_log WHERE job_name = ''PG_JOBMON TEST BAD JOB'') ORDER BY step_id ASC'
    , $$VALUES('Test step 1', 'OK', 'Successful Step 1')
        , ('Test step 2', 'CRITICAL', 'Failed Step 2')
        , ('Test step 3', 'CRITICAL', 'ERROR: column "col3" does not exist')$$
    , 'Checking CRITICAL JOB details');

SELECT results_eq('SELECT action, status, message FROM jobmon.job_detail WHERE job_id = (SELECT job_id FROM jobmon.job_log WHERE job_name = ''PG_JOBMON TEST SQL JOB'') ORDER BY step_id ASC'
    , $$VALUES('Running sql: ''UPDATE tmp_test SET col2 = ''''changed again''''''', 'OK', 'Rows affected: 2')$$
    , 'Checking SQL JOB details');

SELECT results_eq('SELECT action, status, message FROM jobmon.job_detail WHERE job_id = (SELECT job_id FROM jobmon.job_log WHERE job_name = ''PG_JOBMON TEST NON-CONFIG BAD JOB'' LIMIT 1) ORDER BY step_id ASC'
    , $$VALUES('Test step 1', 'CRITICAL', 'Testing repeated job failure')$$
    , 'Checking NON-CONFIG BAD JOB details');

SELECT * FROM finish();
