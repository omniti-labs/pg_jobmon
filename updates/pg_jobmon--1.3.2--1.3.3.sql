-- Fix jobmon_status_text table so that it works properly with a pg_dump of wherever pg_jobmon is installed (Github Issue #2, Pull Request #5).

SELECT pg_catalog.pg_extension_config_dump('job_status_text', 'WHERE alert_code NOT IN (1,2,3)');
