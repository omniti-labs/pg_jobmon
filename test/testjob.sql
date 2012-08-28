CREATE OR REPLACE FUNCTION testjob () RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_job_id        bigint;
    v_step_id       bigint;
    v_job_name      text;
    v_step_status   boolean;
    v_sql_job       text;
    v_tmp           text;
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
    RAISE NOTICE 'Finished TEST GOOD JOB';

/*    FOR v_tmp IN SELECT col1, col2 FROM tmp_test LOOP
        RAISE NOTICE 'col1: %,   col2 %', v_tmp.col1, v_tmp.col2;
    END LOOP;
*/     
    v_job_name := 'PG_JOBMON TEST BAD JOB';
    SELECT INTO v_job_id  jobmon.add_job(v_job_name);
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
    PERFORM jobmon.update_step(v_step_id, 'OK', 'Successful Step 1');
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 2');
    PERFORM jobmon.update_step(v_step_id, 'CRITICAL', 'Failed Step 2');
    v_step_status := jobmon.sql_step(v_job_id, 'Test step 3', 'DELETE FROM tmp_test WHERE col3 = 0');
    IF v_step_status = 'FALSE' THEN
        RAISE NOTICE 'sql step failed as excepted';
    END IF;
    PERFORM jobmon.fail_job(v_job_id);
    RAISE NOTICE 'Finished TEST BAD JOB';

    v_sql_job := jobmon.sql_job('SQL JOB TEST', 'UPDATE tmp_test SET col2 = ''changed again''');

/*
    FOR v_tmp IN SELECT col1, col2 FROM tmp_test LOOP
        RAISE NOTICE 'col1: %,   col2 %', v_tmp.col1, v_tmp.col2;
    END LOOP;
*/
    -- Test this run by opening up another session and running cancel_job(job_id) on this job
    v_job_name := 'PG_JOBMON TEST CANCELED JOB';
    SELECT INTO v_job_id  jobmon.add_job(v_job_name);
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 1');
    PERFORM jobmon.update_step(v_step_id, 'OK', 'Successful Step 1');
    SELECT INTO v_step_id jobmon.add_step(v_job_id, 'Test step 2');
    RAISE NOTICE 'Cancel the latest job labeled ''PG_JOBMON TEST CANCELED JOB'' using cancel_job() to continue testing';
    PERFORM pg_sleep(60);
    --PERFORM jobmon.cancel_job(v_job_id);
    RAISE NOTICE 'TEST CANCELED JOB not tested successfully if this printed. See comments in function on how to perform this test';
    PERFORM jobmon.close_job(v_job_id);    
    
END
$$;
