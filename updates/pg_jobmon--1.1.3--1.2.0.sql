-- New configuration column "escalate" to provide alert escalation capability. Allows for when a job fails at a certain alert level a given number of times, the alert level in the monitoring is raised to the next level up. (Experimental. Please provide feedback)
-- Adjust monitor trigger on job_log table to be able to handle custom alert codes better.
-- Included alert_text value in description returned by check_job_status to make it clearer how many of each alert status occurred. 
-- Fixed pgTAP tests to pass properly and account for new return values. Added tests for escalation.

ALTER TABLE @extschema@.job_check_config ADD escalate int;

/* 
 * Escalation trigger to cause the alert_code value of job_check_log to be higher than the originally inserted value
 * if the escalation policy is set and the number of failed jobs exceeds the configured value
 */
CREATE FUNCTION job_check_log_escalate_trig() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE

v_count                         int;
v_escalate                      int;
v_highest_logged_alert_code     int;
v_max_alert_code                int;
v_step_id                       bigint;

BEGIN

SELECT escalate INTO v_escalate FROM @extschema@.job_check_config WHERE job_name = NEW.job_name;
IF v_escalate IS NOT NULL THEN
    -- Only get the count of the highest number of failures for an alert code for a specific job
    SELECT count(job_name)
        , alert_code 
    INTO v_count
        , v_highest_logged_alert_code 
    FROM @extschema@.job_check_log 
    WHERE job_name = NEW.job_name 
    GROUP BY job_name, alert_code 
    ORDER BY alert_code DESC 
    LIMIT 1 ;

    -- Ensure new alert codes are always equal to at least the last escalated value
    IF v_highest_logged_alert_code > NEW.alert_code THEN
       NEW.alert_code = v_highest_logged_alert_code; 
    END IF;

    -- +1 to ensure the insertion that matches the v_escalate value triggers the escalation, not the next insertion
    IF v_count + 1 >= v_escalate THEN
        SELECT max(alert_code) INTO v_max_alert_code FROM @extschema@.job_status_text;
        IF NEW.alert_code < v_max_alert_code THEN -- Don't exceed the highest configured alert code
            NEW.alert_code = NEW.alert_code + 1;
            -- Log that alert code was escalated by the last job that failed
            EXECUTE 'SELECT @extschema@.add_step('||NEW.job_id||', ''ALERT ESCALATION'')' INTO v_step_id;
            EXECUTE 'SELECT @extschema@.update_step('||v_step_id||', ''ESCALATE'', 
                ''Job has alerted at level '||NEW.alert_code - 1 ||' in excess of the escalate value configured for this job ('||v_escalate||
                    '). Alert code value has been escaleted to: '||NEW.alert_code||''')';
            EXECUTE 'UPDATE @extschema@.job_log SET status = ''ESCALATED'' WHERE job_id = '||NEW.job_id;
        END IF;
    END IF;
END IF; 

RETURN NEW;
END
$$;

CREATE TRIGGER job_check_log_escalate_trig
BEFORE INSERT ON @extschema@.job_check_log
FOR EACH ROW EXECUTE PROCEDURE job_check_log_escalate_trig();


/*
 *  Job Monitor Trigger
 */
CREATE OR REPLACE FUNCTION job_monitor() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_alert_code    int;
BEGIN

    SELECT alert_code INTO v_alert_code FROM @extschema@.job_status_text WHERE alert_text = NEW.status;
    IF v_alert_code IS NOT NULL THEN
        IF v_alert_code = 1 THEN
            DELETE FROM @extschema@.job_check_log WHERE job_name = NEW.job_name;
        ELSE
            INSERT INTO @extschema@.job_check_log (job_id, job_name, alert_code) VALUES (NEW.job_id, NEW.job_name, v_alert_code);
        END IF;
    END IF;

    RETURN NULL;
END
$$;


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
SELECT l.alert_code, 'FAILED_RUN' AS alert_status, l.job_name, '3 consecutive '||t.alert_text||' runs' AS alert_text
FROM @extschema@.job_check_log l 
JOIN @extschema@.job_status_text t ON l.alert_code = t.alert_code
WHERE l.job_name NOT IN (
    SELECT c.job_name FROM @extschema@.job_check_config c
) GROUP BY l.job_name, l.alert_code, t.alert_text HAVING count(*) > 2;

GET DIAGNOSTICS v_rowcount = ROW_COUNT;
IF v_rowcount IS NOT NULL AND v_rowcount > 0 THEN
    v_problem_count := v_problem_count + 1;
END IF;

-- Check for jobs with specially configured sensitivity
INSERT INTO jobmon_check_job_status_temp (alert_code, alert_status, job_name, alert_text)
SELECT l.alert_code, 'FAILED_RUN' as alert_status, l.job_name, count(*)||' '||t.alert_text||' run(s)' AS alert_text 
FROM @extschema@.job_check_log l
JOIN @extschema@.job_check_config c ON l.job_name = c.job_name
JOIN @extschema@.job_status_text t ON l.alert_code = t.alert_code
GROUP BY l.job_name, l.alert_code, t.alert_text, c.sensitivity HAVING count(*) > c.sensitivity;

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


/*
 * Helper function to allow calling without an argument.
 */
CREATE OR REPLACE FUNCTION check_job_status(OUT alert_code int, OUT alert_status text, OUT job_name text, OUT alert_text text) RETURNS SETOF record 
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_longest_period    interval;
    v_row               record;
BEGIN

-- Interval doesn't matter if nothing is in job_check_config. Just give default of 1 week. 
-- Still monitors for any 3 consecutive failures.
SELECT COALESCE(greatest(max(error_threshold), max(warn_threshold)), '1 week') INTO v_longest_period FROM @extschema@.job_check_config;

FOR v_row IN SELECT q.alert_code, q.alert_status, q.job_name, q.alert_text FROM @extschema@.check_job_status(v_longest_period) q
LOOP
        alert_code := v_row.alert_code;
        alert_status := v_row.alert_status;
        job_name := v_row.job_name;
        alert_text := v_row.alert_text;
        RETURN NEXT;
END LOOP;

END
$$;

