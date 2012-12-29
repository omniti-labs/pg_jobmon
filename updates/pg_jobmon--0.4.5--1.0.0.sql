-- IMPORTANT NOTE: fail_job() & _autonomous_fail_job() functions have been dropped and recreated with new arguments. Please check function permissions before and after update.
-- fail_job() can now take an optional second argument to set the final alert code level that the job should fail with in the job_log table. Allows jobs to fail with level 2 (WARNING) instead of only level 3 (CRITICAL). Default is level 3.
-- New check_job_status() function that doesn't require an argument. Will automatically get longest threshold interval from job_check_config table if it exists and use that. Recommend using only this version of fuction from now on.
-- check_job_status(interval) will now throw an exception if you pass an interval that is shorter than the longest job period that is being monitored. If nothing is set in the config table, interval doesn't matter, so will just run normally checking for 3 consecutive failures. Changed documentation to only mention the no-argument version since that's the safest/easiest way to use it.
-- Added ability for check_job_status() to monitor for three level 2 alerts in a row. Added another column to job_check_log table to track alert level of the job failure. Fixed trigger function on job_log table to set the alert level in job_check_log.

ALTER TABLE @extschema@.job_check_log ADD alert_code int DEFAULT 3 NOT NULL;
DROP FUNCTION @extschema@._autonomous_fail_job(bigint);
DROP FUNCTION @extschema@.fail_job(bigint);

/*
 *  Job Monitor Trigger
 */
CREATE OR REPLACE FUNCTION job_monitor() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bad   text;
    v_ok    text;
    v_warn  text;
BEGIN
    SELECT alert_text INTO v_ok FROM @extschema@.job_status_text WHERE alert_code = 1;
    SELECT alert_text INTO v_warn FROM @extschema@.job_status_text WHERE alert_code = 2;
    SELECT alert_text INTO v_bad FROM @extschema@.job_status_text WHERE alert_code = 3;
    IF NEW.status = v_ok THEN
        DELETE FROM @extschema@.job_check_log WHERE job_name = NEW.job_name;
    ELSIF NEW.status = v_warn THEN
        INSERT INTO @extschema@.job_check_log (job_id, job_name, alert_code) VALUES (NEW.job_id, NEW.job_name, 2);        
    ELSIF NEW.status = v_bad THEN
        INSERT INTO @extschema@.job_check_log (job_id, job_name, alert_code) VALUES (NEW.job_id, NEW.job_name, 3);
    ELSE
        -- Do nothing
    END IF;

    return null;
END
$$;


/*
 * Helper function to allow calling without an argument. See below for full function
 */
CREATE FUNCTION check_job_status(OUT alert_code integer, OUT alert_text text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_alert_code        integer;
    v_alert_text        text;
    v_longest_period    interval;
BEGIN

SELECT greatest(max(error_threshold), max(warn_threshold)) INTO v_longest_period FROM @extschema@.job_check_config;
IF v_longest_period IS NOT NULL THEN
    SELECT * INTO v_alert_code, v_alert_text FROM @extschema@.check_job_status(v_longest_period);
ELSE
    -- Interval doesn't matter if nothing is in job_check_config. Just give default of 1 week. 
    -- Still monitors for any 3 consecutive failures.
    SELECT * INTO v_alert_code, v_alert_text FROM @extschema@.check_job_status('1 week');
END IF;

alert_code := v_alert_code;
alert_text := v_alert_text;

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
CREATE OR REPLACE FUNCTION check_job_status(p_history interval, OUT alert_code integer, OUT alert_text text) 
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_alert_code_3          text;
    v_count                 int = 1;
    v_jobs                  RECORD;
    v_job_errors            RECORD;
    v_longest_period        interval;
    v_trouble               text[];
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
alert_text := '(';
alert_code := 1;
-- Generic check for jobs without special monitoring. Should error on 3 failures
FOR v_job_errors IN SELECT l.job_name, l.alert_code FROM @extschema@.job_check_log l 
    WHERE l.job_name NOT IN (SELECT c.job_name FROM @extschema@.job_check_config c WHERE l.job_name <> c.job_name) GROUP BY l.job_name, l.alert_code HAVING count(*) > 2
LOOP
    v_trouble[v_count] := v_job_errors.job_name;
    v_count := v_count+1;
    alert_code = greatest(alert_code, v_job_errors.alert_code);
END LOOP;

IF array_upper(v_trouble,1) > 0 THEN
    alert_text := alert_text || 'Jobs w/ 3 consecutive problems: '||array_to_string(v_trouble,', ')||'; ';
END IF;

SELECT jt.alert_text INTO v_alert_code_3 FROM @extschema@.job_status_text jt WHERE jt.alert_code = 3;

-- Jobs with special monitoring (threshold different than 3 errors; must run within a timeframe; etc)
IF v_version >= 90200 THEN
    FOR v_jobs IN 
        SELECT
            job_name,
            current_timestamp,
            current_timestamp - end_time AS last_run_time,  
            CASE
                WHEN (SELECT count(*) FROM @extschema@.job_check_log WHERE job_name = job_check_config.job_name) > sensitivity THEN 'ERROR'  
                WHEN end_time < (current_timestamp - error_threshold) THEN 'ERROR' 
                WHEN end_time < (current_timestamp - warn_threshold) THEN 'WARNING'
                ELSE 'OK'
            END AS error_code,
            CASE
                WHEN status = v_alert_code_3 THEN 'CRITICAL'
                WHEN status is null THEN 'MISSING' 
                WHEN (end_time < current_timestamp - error_threshold) OR (end_time < current_timestamp - warn_threshold) THEN 
                    CASE 
                        WHEN status = 'OK' THEN 'MISSING'
                        ELSE status
                    END
                ELSE status
            END AS job_status
        FROM
            @extschema@.job_check_config 
            LEFT JOIN (SELECT
                            job_name,
                            max(start_time) AS start_time,
                            max(end_time) AS end_time 
                        FROM
                            @extschema@.job_log
                        WHERE
                            (end_time > now() - p_history OR end_time IS NULL)
                        GROUP BY 
                            job_name 
                        ) last_job using (job_name)
            LEFT JOIN (SELECT 
                            job_name,    
                            start_time, 
                            coalesce(status,
                            (SELECT CASE WHEN (SELECT count(*) FROM pg_locks WHERE not granted and pid = m.pid) > 0 THEN 'BLOCKED' ELSE NULL END),
                            (SELECT CASE WHEN (SELECT count(*) FROM pg_stat_activity WHERE pid = m.pid) > 0 THEN 'RUNNING' ELSE NULL END),
                            'FOOBAR') AS status
                        FROM
                            @extschema@.job_log m 
                        WHERE 
                            start_time > now() - p_history
                        ) lj_status using (job_name,start_time)   
         WHERE active      
    LOOP

        IF v_jobs.error_code = 'ERROR' THEN
            alert_code := 3;
            alert_text := alert_text || v_jobs.job_name || ': ' || coalesce(v_jobs.job_status,'null??');
        END IF;

        IF v_jobs.error_code = 'WARNING' THEN
            IF alert_code <> 3 THEN
                alert_code := 2;
            END IF;
            alert_text := alert_text || v_jobs.job_name || ': ' || coalesce(v_jobs.job_status,'null??');
        END IF;
        
        IF v_jobs.job_status = 'BLOCKED' THEN
             alert_text := alert_text || ' - Object lock is blocking job completion';
        ELSIF v_jobs.job_status = 'MISSING' THEN
            IF v_jobs.last_run_time IS NULL THEN  
                alert_text := alert_text || ' - Last run over ' || p_history || ' ago. Check job_log for more details';
            ELSE
                alert_text := alert_text || ' - Last run at ' || current_timestamp - v_jobs.last_run_time;
            END IF;
        END IF;

        IF alert_code <> 1 AND v_jobs.job_status <> 'OK' THEN
            alert_text := alert_text || '; ';
        END IF;

    END LOOP;
ELSE -- version less than 9.2 with old procpid column
    FOR v_jobs IN 
        SELECT
            job_name,
            current_timestamp,
            current_timestamp - end_time AS last_run_time,  
            CASE
                WHEN (SELECT count(*) FROM @extschema@.job_check_log WHERE job_name = job_check_config.job_name) > sensitivity THEN 'ERROR'  
                WHEN end_time < (current_timestamp - error_threshold) THEN 'ERROR' 
                WHEN end_time < (current_timestamp - warn_threshold) THEN 'WARNING'
                ELSE 'OK'
            END AS error_code,
            CASE
                WHEN status = v_alert_code_3 THEN 'CRITICAL'
                WHEN status is null THEN 'MISSING' 
                WHEN (end_time < current_timestamp - error_threshold) OR (end_time < current_timestamp - warn_threshold) THEN 
                    CASE 
                        WHEN status = 'OK' THEN 'MISSING'
                        ELSE status
                    END
                ELSE status
            END AS job_status
        FROM
            @extschema@.job_check_config 
            LEFT JOIN (SELECT
                            job_name,
                            max(start_time) AS start_time,
                            max(end_time) AS end_time 
                        FROM
                            @extschema@.job_log
                        WHERE
                            (end_time > now() - p_history OR end_time IS NULL)
                        GROUP BY 
                            job_name 
                        ) last_job using (job_name)
            LEFT JOIN (SELECT 
                            job_name,    
                            start_time, 
                            coalesce(status,
                            (SELECT CASE WHEN (SELECT count(*) FROM pg_locks WHERE not granted and pid = m.pid) > 0 THEN 'BLOCKED' ELSE NULL END),
                            (SELECT CASE WHEN (SELECT count(*) FROM pg_stat_activity WHERE procpid = m.pid) > 0 THEN 'RUNNING' ELSE NULL END),
                            'FOOBAR') AS status
                        FROM
                            @extschema@.job_log m 
                        WHERE 
                            start_time > now() - p_history
                        ) lj_status using (job_name,start_time)   
         WHERE active      
    LOOP

        IF v_jobs.error_code = 'ERROR' THEN
            alert_code := 3;
            alert_text := alert_text || v_jobs.job_name || ': ' || coalesce(v_jobs.job_status,'null??');
        END IF;

        IF v_jobs.error_code = 'WARNING' THEN
            IF alert_code <> 3 THEN
                alert_code := 2;
            END IF;
            alert_text := alert_text || v_jobs.job_name || ': ' || coalesce(v_jobs.job_status,'null??');
        END IF;
        
        IF v_jobs.job_status = 'BLOCKED' THEN
             alert_text := alert_text || ' - Object lock is blocking job completion';
        ELSIF v_jobs.job_status = 'MISSING' THEN
            IF v_jobs.last_run_time IS NULL THEN  
                alert_text := alert_text || ' - Last run over ' || p_history || ' ago. Check job_log for more details';
            ELSE
                alert_text := alert_text || ' - Last run at ' || current_timestamp - v_jobs.last_run_time;
            END IF;
        END IF;

        IF alert_code <> 1 AND v_jobs.job_status <> 'OK' THEN
            alert_text := alert_text || '; ';
        END IF;

    END LOOP;
END IF; -- end version check IF

IF alert_text = '(' THEN
    alert_text := alert_text || 'All jobs run successfully';
END IF;

alert_text := alert_text || ')';

END
$$;


/*
 *  Fail Job Autonomous
 */
CREATE FUNCTION _autonomous_fail_job(p_job_id bigint, p_fail_level int) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_numrows integer;
    v_status text;
BEGIN
    EXECUTE 'SELECT alert_text FROM @extschema@.job_status_text WHERE alert_code = '||p_fail_level
        INTO v_status;
    UPDATE @extschema@.job_log SET
        end_time = current_timestamp,
        status = v_status
    WHERE job_id = p_job_id;
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    RETURN v_numrows;
END
$$;

/*
 *  Fail Job
 */
CREATE FUNCTION fail_job(p_job_id bigint, p_fail_level int DEFAULT 3) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remote_query text;
    v_dblink_schema text;
BEGIN
    
    SELECT nspname INTO v_dblink_schema FROM pg_namespace n, pg_extension e WHERE e.extname = 'dblink' AND e.extnamespace = n.oid;
    
    v_remote_query := 'SELECT @extschema@._autonomous_fail_job('||p_job_id||', '||p_fail_level||')'; 

    EXECUTE 'SELECT devnull FROM ' || v_dblink_schema || '.dblink('||quote_literal(@extschema@.auth())||
        ',' || quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  

END
$$;


/*
 *  Cancel Job
 */
CREATE OR REPLACE FUNCTION cancel_job(p_job_id bigint) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_current_role  text;
    v_pid           integer;
    v_step_id       bigint;
    v_status        text;
BEGIN
    EXECUTE 'SELECT alert_text FROM @extschema@.job_status_text WHERE alert_code = 3'
        INTO v_status;
    SELECT pid INTO v_pid FROM @extschema@.job_log WHERE job_id = p_job_id;
    SELECT current_user INTO v_current_role;
    PERFORM pg_cancel_backend(v_pid);
    SELECT max(step_id) INTO v_step_id FROM @extschema@.job_detail WHERE job_id = p_job_id;
    PERFORM @extschema@._autonomous_update_step(v_step_id, v_status, 'Manually cancelled via call to @extschema@.cancel_job() by '||v_current_role);
    PERFORM @extschema@._autonomous_fail_job(p_job_id, 3);
    RETURN true;
END
$$;
