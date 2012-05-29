-- log in using psql and run this script with \i

SELECT * FROM jobmon.show_job('PG_JOBMON TEST GOOD JOB');
SELECT * FROM jobmon.show_job_like('jobmon');
SELECT * FROM jobmon.show_job_status('CRITICAL');
SELECT * FROM jobmon.show_job_status('PG_JOBMON TEST BAD JOB', 'CRITICAL');
SELECT * FROM jobmon.show_detail((SELECT job_id FROM jobmon.show_job('PG_JOBMON TEST GOOD JOB', 1) ORDER BY job_id DESC)::bigint);
SELECT * FROM jobmon.show_detail('PG_JOBMON TEST GOOD JOB custom');
