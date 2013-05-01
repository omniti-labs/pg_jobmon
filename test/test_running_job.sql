-- To check for a running job, a second session is required, so pgTAP cannot be used.
-- To cleanup after this script if it doesn't finish properly, run test09

SELECT set_config('search_path', 'jobmon, dblink, tap', false);

CREATE FUNCTION jobmon_test_jobs_running() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_job_id        bigint;
    v_step_id       bigint;
    v_job_name      text;
BEGIN
    
    v_job_name := 'PG_JOBMON TEST RUNNING JOB';
    SELECT INTO v_job_id  jobmon.add_job(v_job_name);
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
    PERFORM jobmon.update_step(v_step_id, 'OK', 'Successful Step 1');
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 2');
    RAISE NOTICE 'Sleeping for 20 seconds for proper test result. Please wait for next notice...';
    PERFORM pg_sleep(20);
    RAISE NOTICE 'Run check_job_status() from another session. You should see "PG_JOBMON TEST RUNNING JOB" in the result set with the alert status "RUNNING". You have 60 seconds...';
    PERFORM pg_sleep(60);
    PERFORM jobmon.close_job(v_job_id);    

END
$$;

INSERT INTO job_check_config (job_name, warn_threshold, error_threshold, active, sensitivity) VALUES ('PG_JOBMON TEST RUNNING JOB', '10 seconds', '1 min', true, 0);

SELECT jobmon_test_jobs_running();

SELECT 'Run check_job_status() again. It should return all clear.' AS NOTICE;

DELETE FROM job_log WHERE job_name = 'PG_JOBMON TEST RUNNING JOB';
DELETE FROM job_check_config WHERE job_name = 'PG_JOBMON TEST RUNNING JOB';
DROP FUNCTION jobmon_test_jobs_running();
