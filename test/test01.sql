\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true


-- TODO Add test at the end running check_job_status to show it not finding any of the configured jobs

SELECT set_config('search_path', 'jobmon, dblink, public', false);

SELECT plan(2);

-- Cleanup from any previous testing that didn't clean up after itself properly
DELETE FROM job_log WHERE job_name IN ('PG_JOBMON TEST GOOD JOB', 'PG_JOBMON TEST WARNING JOB', 'PG_JOBMON TEST BAD JOB', 'PG_JOBMON TEST CANCELED JOB', 'PG_JOBMON TEST SQL JOB', 'PG_JOBMON TEST JOB NEVER FINISHED', 'PG_JOBMON TEST NON-CONFIG BAD JOB', 'PG_JOBMON TEST RUNNING JOB', 'PG_JOBMON TEST BLOCKED JOB');
DELETE FROM job_check_config WHERE job_name IN ('PG_JOBMON TEST GOOD JOB', 'PG_JOBMON TEST WARNING JOB', 'PG_JOBMON TEST BAD JOB', 'PG_JOBMON TEST CANCELED JOB', 'PG_JOBMON TEST SQL JOB', 'PG_JOBMON TEST JOB NEVER RUN', 'PG_JOBMON TEST JOB NEVER FINISHED', 'PG_JOBMON TEST NON-CONFIG BAD JOB', 'PG_JOBMON TEST RUNNING JOB', 'PG_JOBMON TEST BLOCKED JOB');
DELETE FROm job_check_log WHERE job_name IN ('PG_JOBMON TEST GOOD JOB', 'PG_JOBMON TEST WARNING JOB', 'PG_JOBMON TEST BAD JOB', 'PG_JOBMON TEST CANCELED JOB', 'PG_JOBMON TEST SQL JOB', 'PG_JOBMON TEST JOB NEVER FINISHED', 'PG_JOBMON TEST NON-CONFIG BAD JOB');

DROP FUNCTION IF EXISTS jobmon_test_jobs_normal();

-- Setup jobs to monitor for
INSERT INTO job_check_config (job_name, warn_threshold, error_threshold, active, sensitivity) VALUES ('PG_JOBMON TEST JOB NEVER RUN', '1 day', '2 days', true, 0);
INSERT INTO job_check_config (job_name, warn_threshold, error_threshold, active, sensitivity) VALUES ('PG_JOBMON TEST GOOD JOB', '30 seconds', '1 min', true, 0);
INSERT INTO job_check_config (job_name, warn_threshold, error_threshold, active, sensitivity) VALUES ('PG_JOBMON TEST BAD JOB', '1 day', '2 days', true, 0);
INSERT INTO job_check_config (job_name, warn_threshold, error_threshold, active, sensitivity) VALUES ('PG_JOBMON TEST WARNING JOB', '1 day', '2 days', true, 0);
INSERT INTO job_check_config (job_name, warn_threshold, error_threshold, active, sensitivity) VALUES ('PG_JOBMON TEST JOB NEVER FINISHED', '1 min', '10 mins', true, 1);

-- Setup for a job that was started but never had end_time set
INSERT INTO jobmon.job_log (owner, job_name, start_time, pid) VALUES ('keith', 'PG_JOBMON TEST JOB NEVER FINISHED', now() - '5 days'::interval, 1234);

CREATE FUNCTION jobmon_test_jobs_normal() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_job_id        bigint;
    v_step_id       bigint;
    v_job_name      text;
    v_step_status   boolean;
    v_sql_job       text;
BEGIN

    EXECUTE 'CREATE TEMP TABLE tmp_test (col1 int, col2 text)';
    EXECUTE 'INSERT INTO tmp_test VALUES (1, ''row1'')';
    EXECUTE 'INSERT INTO tmp_test VALUES (2, ''row2'')';

    v_job_name := 'PG_JOBMON TEST GOOD JOB';
    SELECT INTO v_job_id  jobmon.add_job(v_job_name);
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
    PERFORM jobmon.update_step(v_step_id, 'OK', 'Successful Step 1');
    v_step_status := jobmon.sql_step(v_job_id, 'Test step 2', 'UPDATE tmp_test SET col2 = ''changed''');
    IF v_step_status = 'TRUE' THEN 
        RAISE NOTICE 'sql step succeeded as expected';
    END IF;
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 3');
    PERFORM jobmon.update_step(v_step_id, 'OK', 'Successful Step 3');
    PERFORM jobmon.close_job(v_job_id);
--    RAISE NOTICE 'Finished TEST GOOD JOB';

    
    v_job_name := 'PG_JOBMON TEST WARNING JOB';
    SELECT INTO v_job_id  jobmon.add_job(v_job_name);
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
    PERFORM jobmon.update_step(v_step_id, 'OK', 'Successful Step 1');
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 2');
    PERFORM jobmon.update_step(v_step_id, 'WARNING', 'Failed Step 2');
    v_step_status := jobmon.sql_step(v_job_id, 'Test step 3', 'DELETE FROM tmp_test WHERE col3 = 0');
    IF v_step_status = 'FALSE' THEN
        RAISE NOTICE 'sql step failed as expected';
    END IF;
    PERFORM jobmon.fail_job(v_job_id, 2);
--    RAISE NOTICE 'Finished TEST WARNING JOB';

     
    v_job_name := 'PG_JOBMON TEST BAD JOB';
    SELECT INTO v_job_id  jobmon.add_job(v_job_name);
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
    PERFORM jobmon.update_step(v_step_id, 'OK', 'Successful Step 1');
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 2');
    PERFORM jobmon.update_step(v_step_id, 'CRITICAL', 'Failed Step 2');
    v_step_status := jobmon.sql_step(v_job_id, 'Test step 3', 'DELETE FROM tmp_test WHERE col3 = 0');
    IF v_step_status = 'FALSE' THEN
        RAISE NOTICE 'sql step failed as expected';
    END IF;
    PERFORM jobmon.fail_job(v_job_id);
--    RAISE NOTICE 'Finished TEST BAD JOB';

    v_sql_job := jobmon.sql_job('PG_JOBMON TEST SQL JOB', 'UPDATE tmp_test SET col2 = ''changed again''');

    -- Cause 3 consecutive job failures for check_job_status() to catch
    v_job_name := 'PG_JOBMON TEST NON-CONFIG BAD JOB';
    SELECT INTO v_job_id jobmon.add_job(v_job_name);
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
    PERFORM jobmon.update_step(v_step_id, 'CRITICAL', 'Testing repeated job failure');
    PERFORM jobmon.fail_job(v_job_id);
    v_job_name := 'PG_JOBMON TEST NON-CONFIG BAD JOB';
    SELECT INTO v_job_id jobmon.add_job(v_job_name);
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
    PERFORM jobmon.update_step(v_step_id, 'CRITICAL', 'Testing repeated job failure');
    PERFORM jobmon.fail_job(v_job_id);
    v_job_name := 'PG_JOBMON TEST NON-CONFIG BAD JOB';
    SELECT INTO v_job_id jobmon.add_job(v_job_name);
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
    PERFORM jobmon.update_step(v_step_id, 'CRITICAL', 'Testing repeated job failure');
    PERFORM jobmon.fail_job(v_job_id);

END
$$;

SELECT results_eq('SELECT * FROM check_job_status()'
    , $$VALUES(3,'MISSING','PG_JOBMON TEST BAD JOB','Has not completed a run since highest configured monitoring time period')
        , (3,'MISSING','PG_JOBMON TEST GOOD JOB','Has not completed a run since highest configured monitoring time period')
        , (3,'MISSING','PG_JOBMON TEST JOB NEVER FINISHED','Has not completed a run since highest configured monitoring time period')
        , (3,'MISSING','PG_JOBMON TEST JOB NEVER RUN','Has not completed a run since highest configured monitoring time period')
        , (3,'MISSING','PG_JOBMON TEST WARNING JOB','Has not completed a run since highest configured monitoring time period')$$
    , 'Test for valid check_job_status() result when nothing has run yet');

SELECT pass('Cleanup and setup complete');
SELECT * FROM finish();
