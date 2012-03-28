CREATE OR REPLACE FUNCTION testjob () RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_job_id        bigint;
    v_step_id       bigint;
    v_job_name      text;
BEGIN

    v_job_name := 'PG_JOBMON TEST GOOD JOB';
    SELECT into v_job_id  jobmon.add_job(v_job_name);
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
    SELECT jobmon.update_step(v_job_id, v_step_id, 'OK', 'Successful Step 1');
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 2');
    SELECT jobmon.update_step(v_job_id, v_step_id, 'OK', 'Successful Step 2');
    SELECT jobmon.close_job(v_job_id);
    RAISE NOTICE 'Finished TEST GOOD JOB';
    
    v_job_name = 'PG_JOBMON TEST BAD JOB';
    SELECT into v_job_id  jobmon.add_job(v_job_name);
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
    SELECT jobmon.update_step(v_job_id, v_step_id, 'OK', 'Successful Step 1');
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 2');
    SELECT jobmon.update_step(v_job_id, v_step_id, 'BAD', 'Failed Step 2');
    SELECT jobmon.fail_job(v_job_id);
    RAISE NOTICE 'Finished TEST BAD JOB';
    
    v_job_name = 'PG_JOBMON TEST CANCELED JOB';
    SELECT into v_job_id  jobmon.add_job(v_job_name);
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
    SELECT jobmon.update_step(v_job_id, v_step_id, 'OK', 'Successful Step 1');
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 2');
    SELECT jobmon.cancel_job(v_job_id);
    RAISE NOTICE 'Finished TEST CANCELED JOB';
    
END
$$;
