-- Since the cancel_job() function involves the termination of a running process, this cannot be tested via pgTAP.

/* 
To test that it works properly, run this sql file in one session. Then when the notice appears, search the job_log table for the latest
    run of the cancelled job and use its job_id with the cancel_job() function
Once that is done, return to the other session and it should have been terminated.
Search the job_detail table for more details of the above job_id. The last log entry should have a note saying that the job
    was manually cancelled with job_cancel().
*/

-- To cleanup after this script, run test09

SELECT set_config('search_path', 'jobmon, dblink, tap', false);

CREATE FUNCTION jobmon_test_jobs_cancel() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_job_id        bigint;
    v_step_id       bigint;
    v_job_name      text;
BEGIN
    
    -- Test this run by opening up another session and running cancel_job(job_id) on this job
    v_job_name := 'PG_JOBMON TEST CANCELED JOB';
    SELECT INTO v_job_id  jobmon.add_job(v_job_name);
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
    PERFORM jobmon.update_step(v_step_id, 'OK', 'Successful Step 1');
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 2');
    RAISE NOTICE 'Cancel the latest job labeled ''PG_JOBMON TEST CANCELED JOB'' using cancel_job() from another session to continue testing. You have 90 seconds...';
    PERFORM pg_sleep(90);
    --PERFORM jobmon.cancel_job(v_job_id);
    RAISE NOTICE 'TEST CANCELED JOB not tested successfully if this printed.';
    PERFORM jobmon.close_job(v_job_id);    

END
$$;

SELECT jobmon_test_jobs_cancel();
