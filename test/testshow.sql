-- log in using psql and run this script with \i
\set ECHO all
SELECT * FROM jobmon.show_job('PG_JOBMON TEST GOOD JOB');
SELECT * FROM jobmon.show_job_like('jobmon');
SELECT * FROM jobmon.show_job_status('CRITICAL');
SELECT * FROM jobmon.show_job_status('PG_JOBMON TEST BAD JOB', 'CRITICAL');
SELECT * FROM jobmon.show_detail((SELECT job_id FROM jobmon.show_job('PG_JOBMON TEST GOOD JOB', 1))::bigint);
SELECT * FROM jobmon.show_detail('PG_JOBMON TEST CANCELED JOB');
--check the job_check_log to make sure failed jobs are queing up there
SELECT * from jobmon.job_check_log;
