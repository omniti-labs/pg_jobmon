-- Tests for escalation

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

SELECT set_config('search_path', 'jobmon, dblink, public', false);

SELECT plan(3);

UPDATE job_check_config SET escalate = 3 WHERE job_name = 'PG_JOBMON TEST WARNING JOB';
INSERT INTO job_status_text (alert_code, alert_text) SELECT max(alert_code+1), 'PG_JOBMON TEST ALERT LEVEL' FROM job_status_text;
INSERT INTO job_status_text (alert_code, alert_text) SELECT max(alert_code+1), 'PG_JOBMON TEST ALERT LEVEL' FROM job_status_text;

CREATE OR REPLACE FUNCTION jobmon_test_jobs_normal() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_job_id        bigint;
    v_step_id       bigint;
    v_job_name      text;
    v_step_status   boolean;
BEGIN    
    
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

END
$$;

SELECT jobmon_test_jobs_normal();
SELECT jobmon_test_jobs_normal();

SELECT results_eq('SELECT max(alert_code) FROM job_check_log WHERE job_name = ''PG_JOBMON TEST WARNING JOB''',
   ARRAY[3],
   'Checking that alert_code got escalated properly'); 

SELECT jobmon_test_jobs_normal();
SELECT jobmon_test_jobs_normal();
SELECT jobmon_test_jobs_normal();

SELECT results_eq('SELECT max(alert_code) FROM job_check_log WHERE job_name = ''PG_JOBMON TEST WARNING JOB''',
   ARRAY[4],
   'Checking that alert_code got escalated properly again'); 

SELECT jobmon_test_jobs_normal();
SELECT jobmon_test_jobs_normal();
SELECT jobmon_test_jobs_normal();
SELECT jobmon_test_jobs_normal();

SELECT results_eq('SELECT max(alert_code) FROM job_check_log WHERE job_name = ''PG_JOBMON TEST WARNING JOB''',
   ARRAY[5],
   'Checking that alert_code got escalated properly again'); 

SELECT * FROM finish();
