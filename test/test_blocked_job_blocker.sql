-- Run this function before test_blocked_job.sql in order for the BLOCKED status to be picked up properly

SELECT set_config('search_path', 'jobmon, dblink, tap', false);

DROP TABLE IF EXISTS jobmon_block_test_table;

CREATE TABLE jobmon_block_test_table (col1 int, col2 text);
INSERT INTO jobmon_block_test_table VALUES (1, 'row1');
INSERT INTO jobmon_block_test_table VALUES (2, 'row2');

BEGIN;
LOCK TABLE jobmon_block_test_table IN ACCESS EXCLUSIVE MODE;
SELECT 'Lock on test table obtained. You now have 90 seconds to run "test_blocked_job.sql" in order to move on to the next step of the test' AS NOTICE;
SELECT pg_sleep(60);
SELECT '30 seconds remaining' AS NOTICE;
SELECT pg_sleep(30);
COMMIT;

DROP TABLE jobmon_block_test_table;


