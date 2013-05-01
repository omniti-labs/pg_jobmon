-- Fixed failing jobs not showing up in check_job_status() if no missing jobs existed

/*
 *  Check Job status
 *
 * p_history is how far into job_log's past the check will go. Don't go further back than the longest job's interval that is contained
 *      in job_check_config to keep check efficient
 * Return code 1 means a successful job run
 * Return code 2 is for use with jobs that support a warning indicator. Not critical, but someone should look into it
 * Return code 3 is for use with a critical job failure 
 */
CREATE OR REPLACE FUNCTION check_job_status(p_history interval, OUT alert_code int, OUT alert_status text, OUT job_name text, OUT alert_text text) RETURNS SETOF record 
LANGUAGE plpgsql
    AS $$
DECLARE
    v_count                 int = 1;
    v_longest_period        interval;
    v_row                   record;
    v_rowcount              int;
    v_problem_count         int := 0;
    v_version               int;
BEGIN

-- Leave this check here in case helper function isn't used and this is called directly with an interval argument
SELECT greatest(max(error_threshold), max(warn_threshold)) INTO v_longest_period FROM @extschema@.job_check_config;
IF v_longest_period IS NOT NULL THEN
    IF p_history < v_longest_period THEN
        RAISE EXCEPTION 'Input argument must be greater than or equal to the longest threshold in job_check_config table';
    END IF;
END IF;
    
SELECT current_setting('server_version_num')::int INTO v_version;

CREATE TEMP TABLE jobmon_check_job_status_temp (alert_code int, alert_status text, job_name text, alert_text text, pid int);

-- Check for jobs with three consecutive errors and not set for any special configuration
INSERT INTO jobmon_check_job_status_temp (alert_code, alert_status, job_name, alert_text)
SELECT l.alert_code, 'FAILED_RUN' AS alert_status, l.job_name, '3 consecutive job failures' AS alert_text
FROM @extschema@.job_check_log l 
WHERE l.job_name NOT IN (
    SELECT c.job_name FROM @extschema@.job_check_config c
) GROUP BY l.job_name, l.alert_code HAVING count(*) > 2;

GET DIAGNOSTICS v_rowcount = ROW_COUNT;
IF v_rowcount IS NOT NULL AND v_rowcount > 0 THEN
    v_problem_count := v_problem_count + 1;
END IF;

-- Check for jobs with specially configured sensitivity
INSERT INTO jobmon_check_job_status_temp (alert_code, alert_status, job_name, alert_text)
SELECT l.alert_code, 'FAILED_RUN' as alert_status, l.job_name, count(*)||' consecutive job failure(s)' AS alert_text FROM @extschema@.job_check_log l
JOIN @extschema@.job_check_config c ON l.job_name = c.job_name
GROUP BY l.job_name, l.alert_code, c.sensitivity HAVING count(*) > c.sensitivity;

GET DIAGNOSTICS v_rowcount = ROW_COUNT;
IF v_rowcount IS NOT NULL AND v_rowcount > 0 THEN
    v_problem_count := v_problem_count + 1;
END IF;

-- Check for missing jobs that have configured time thresholds. Jobs that have not run since before the p_history will return pid as NULL
INSERT INTO jobmon_check_job_status_temp (alert_code, alert_status, job_name, alert_text, pid)
SELECT CASE WHEN l.max_start IS NULL AND l.end_time IS NULL THEN 3
    WHEN (CURRENT_TIMESTAMP - l.max_start) > c.error_threshold THEN 3
    WHEN (CURRENT_TIMESTAMP - l.max_start) > c.warn_threshold THEN 2
    ELSE 3
  END AS ac
, CASE WHEN (CURRENT_TIMESTAMP - l.max_start) > c.warn_threshold OR l.end_time IS NULL THEN 'MISSING' 
    ELSE l.status 
  END AS alert_status
, c.job_name
, COALESCE('Last completed run: '||l.max_end, 'Has not completed a run since highest configured monitoring time period') AS alert_text
, l.pid
FROM @extschema@.job_check_config c
LEFT JOIN (
    WITH max_start_time AS (
        SELECT w.job_name, max(w.start_time) as max_start, max(w.end_time) as max_end FROM @extschema@.job_log w WHERE start_time > (CURRENT_TIMESTAMP - p_history) GROUP BY w.job_name)
    SELECT a.job_name, a.end_time, a.status, a.pid, m.max_start, m.max_end
    FROM @extschema@.job_log a
    JOIN max_start_time m ON a.job_name = m.job_name and a.start_time = m.max_start
    WHERE start_time > (CURRENT_TIMESTAMP - p_history)
) l ON c.job_name = l.job_name
WHERE c.active
AND (CURRENT_TIMESTAMP - l.max_start) > c.warn_threshold OR l.max_start IS NULL
ORDER BY ac, l.job_name, l.max_start;

GET DIAGNOSTICS v_rowcount = ROW_COUNT;
IF v_rowcount IS NOT NULL AND v_rowcount > 0 THEN
    v_problem_count := v_problem_count + 1;
END IF;

-- Check for BLOCKED after RUNNING to ensure blocked jobs are labelled properly   
IF v_version >= 90200 THEN
    -- Jobs currently running that have not run before within their configured monitoring time period
    FOR v_row IN SELECT j.job_name
        FROM @extschema@.job_log j
        JOIN @extschema@.job_check_config c ON j.job_name = c.job_name
        JOIN pg_catalog.pg_stat_activity a ON j.pid = a.pid
        WHERE j.start_time > (CURRENT_TIMESTAMP - p_history)
        AND (CURRENT_TIMESTAMP - j.start_time) >= least(c.warn_threshold, c.error_threshold)
        AND j.end_time IS NULL 
    LOOP
        UPDATE jobmon_check_job_status_temp t 
        SET alert_status = 'RUNNING'
            , alert_text = (SELECT COALESCE('Currently running. Last completed run: '||max(end_time),
                        'Currently running. Job has not had a completed run within configured monitoring time period.') 
                FROM @extschema@.job_log 
                WHERE job_log.job_name = v_row.job_name 
                AND job_log.start_time > (CURRENT_TIMESTAMP - p_history))
        WHERE t.job_name = v_row.job_name;
     END LOOP;
    
    -- Jobs blocked by locks 
    FOR v_row IN SELECT j.job_name
        FROM @extschema@.job_log j
        JOIN pg_catalog.pg_locks l ON j.pid = l.pid
        JOIN pg_catalog.pg_stat_activity a ON j.pid = a.pid
        WHERE j.start_time > (CURRENT_TIMESTAMP - p_history)
        AND NOT l.granted
    LOOP
        UPDATE jobmon_check_job_status_temp t 
        SET alert_status = 'BLOCKED'
            , alert_text = COALESCE('Another transaction has a lock that blocking this job from completing') 
        WHERE t.job_name = v_row.job_name;
     END LOOP;  

ELSE -- version less than 9.2 with old procpid column

    -- Jobs currently running that have not run before within their configured monitoring time period
    FOR v_row IN SELECT j.job_name
        FROM @extschema@.job_log j
        JOIN @extschema@.job_check_config c ON j.job_name = c.job_name
        JOIN pg_catalog.pg_stat_activity a ON j.pid = a.procpid
        WHERE j.start_time > (CURRENT_TIMESTAMP - p_history)
        AND (CURRENT_TIMESTAMP - j.start_time) >= least(c.warn_threshold, c.error_threshold)
        AND j.end_time IS NULL 
    LOOP
        UPDATE jobmon_check_job_status_temp t 
        SET alert_status = 'RUNNING'
            , alert_text = (SELECT COALESCE('Currently running. Last completed run: '||max(end_time),
                        'Currently running. Job has not had a completed run within configured monitoring time period.') 
                FROM @extschema@.job_log 
                WHERE job_log.job_name = v_row.job_name 
                AND job_log.start_time > (CURRENT_TIMESTAMP - p_history))
        WHERE t.job_name = v_row.job_name;
   END LOOP;  

   -- Jobs blocked by locks 
    FOR v_row IN SELECT j.job_name
        FROM @extschema@.job_log j
        JOIN pg_catalog.pg_locks l ON j.pid = l.pid
        JOIN pg_catalog.pg_stat_activity a ON j.pid = a.procpid
        WHERE j.start_time > (CURRENT_TIMESTAMP - p_history)
        AND NOT l.granted
    LOOP
        UPDATE jobmon_check_job_status_temp t 
        SET alert_status = 'BLOCKED'
            , alert_text = COALESCE('Another transaction has a lock that blocking this job from completing') 
        WHERE t.job_name = v_row.job_name;
    END LOOP;  

END IF; -- end version check IF

IF v_problem_count > 0 THEN
    FOR v_row IN SELECT t.alert_code, t.alert_status, t.job_name, t.alert_text FROM jobmon_check_job_status_temp t ORDER BY alert_code DESC, job_name ASC, alert_status ASC
    LOOP
        alert_code := v_row.alert_code;
        alert_status := v_row.alert_status;
        job_name := v_row.job_name;
        alert_text := v_row.alert_text;
        RETURN NEXT;
    END LOOP;
ELSE
        alert_code := 1;
        alert_status := 'OK'; 
        job_name := NULL;
        alert_text := 'All jobs run successfully';
        RETURN NEXT;
END IF;

DROP TABLE IF EXISTS jobmon_check_job_status_temp;

END
$$;

