\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

SELECT set_config('search_path', 'jobmon, dblink, public', false);

SELECT plan(7);

SELECT results_eq('SELECT * FROM check_job_status() order by job_name, alert_status', 
    $$VALUES(3,'FAILED_RUN','PG_JOBMON TEST BAD JOB','1 CRITICAL run(s)')
        , (3,'MISSING','PG_JOBMON TEST JOB NEVER FINISHED','Has not completed a run since highest configured monitoring time period')
        , (3,'MISSING','PG_JOBMON TEST JOB NEVER RUN','Has not completed a run since highest configured monitoring time period')
        , (3,'FAILED_RUN','PG_JOBMON TEST NON-CONFIG BAD JOB','3 consecutive CRITICAL runs')
        , (2,'FAILED_RUN','PG_JOBMON TEST WARNING JOB','1 WARNING run(s)')$$
    , 'Checking for initial job failures in check_job_status()');

SELECT pass('Sleeping for 40 seconds to test for warning threshold...');
SELECT pg_sleep(40);

SELECT results_eq('SELECT alert_code, alert_status, job_name FROM check_job_status() order by job_name, alert_status', 
    $$VALUES(3,'FAILED_RUN','PG_JOBMON TEST BAD JOB')
        , (2,'MISSING','PG_JOBMON TEST GOOD JOB')
        , (3,'MISSING','PG_JOBMON TEST JOB NEVER FINISHED')
        , (3,'MISSING','PG_JOBMON TEST JOB NEVER RUN')
        , (3,'FAILED_RUN','PG_JOBMON TEST NON-CONFIG BAD JOB')
        , (2,'FAILED_RUN','PG_JOBMON TEST WARNING JOB')$$
    , 'Checking for missing warning threshold job failure in check_job_status()');

SELECT pass('Sleeping for 30 seconds to test for error threshold...');
SELECT pg_sleep(30);

SELECT results_eq('SELECT alert_code, alert_status, job_name FROM check_job_status() order by job_name, alert_status', 
    $$VALUES(3,'FAILED_RUN','PG_JOBMON TEST BAD JOB')
        , (3,'MISSING','PG_JOBMON TEST GOOD JOB')
        , (3,'MISSING','PG_JOBMON TEST JOB NEVER FINISHED')
        , (3,'MISSING','PG_JOBMON TEST JOB NEVER RUN')
        , (3,'FAILED_RUN','PG_JOBMON TEST NON-CONFIG BAD JOB')
        , (2,'FAILED_RUN','PG_JOBMON TEST WARNING JOB')$$
    , 'Checking for missing error threshold job failure in check_job_status()');

CREATE OR REPLACE FUNCTION jobmon_test_jobs_normal() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_job_id        bigint;
    v_step_id       bigint;
    v_job_name      text;
BEGIN
-- Run successful version of this job to make sure it clears out of the log 
v_job_name := 'PG_JOBMON TEST NON-CONFIG BAD JOB';
SELECT INTO v_job_id jobmon.add_job(v_job_name);
SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
PERFORM jobmon.update_step(v_step_id, 'OK', 'Testing job recovery');
PERFORM jobmon.close_job(v_job_id);

END
$$;

SELECT jobmon_test_jobs_normal();

SELECT results_eq('SELECT alert_code, alert_status, job_name FROM check_job_status() order by job_name, alert_status', 
    $$VALUES(3,'FAILED_RUN','PG_JOBMON TEST BAD JOB')
        , (3,'MISSING','PG_JOBMON TEST GOOD JOB')
        , (3,'MISSING','PG_JOBMON TEST JOB NEVER FINISHED')
        , (3,'MISSING','PG_JOBMON TEST JOB NEVER RUN')
        , (2,'FAILED_RUN','PG_JOBMON TEST WARNING JOB')$$
    , 'Checking for missing error threshold job failure in check_job_status()');

SELECT results_eq('SELECT action, status, message FROM jobmon.job_detail WHERE job_id = (SELECT job_id FROM jobmon.job_log WHERE job_name = ''PG_JOBMON TEST NON-CONFIG BAD JOB'' ORDER BY job_id DESC LIMIT 1) ORDER BY step_id ASC'
    , $$VALUES('Test step 1', 'OK', 'Testing job recovery')$$
    , 'Checking NON-CONFIG BAD JOB recovery details');


SELECT * FROM finish();
