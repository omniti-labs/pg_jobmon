-- Make column names in job_status_text table more consistent with the check_job_status() function return column names.
-- Fix check_job_status() returning extra spaces and ; in the alert_text when a job has failed
-- Fix check_job_status() to use alert_text value for code 3 instead of hardcoded value 'CRITICAL'

ALTER TABLE @extschema@.job_status_text RENAME COLUMN error_code TO alert_code;
ALTER TABLE @extschema@.job_status_text RENAME COLUMN error_text TO alert_text;
ALTER INDEX @extschema@.job_status_text_error_code_pkey RENAME TO job_status_text_alert_code_pkey;


CREATE OR REPLACE FUNCTION _autonomous_close_job(p_job_id bigint) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_numrows integer;
    v_status text;
BEGIN    
    EXECUTE 'SELECT alert_text FROM @extschema@.job_status_text WHERE alert_code = 1'
        INTO v_status;
    UPDATE @extschema@.job_log SET
        end_time = current_timestamp,
        status = v_status
    WHERE job_id = p_job_id;
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    RETURN v_numrows;
END
$$;


CREATE OR REPLACE FUNCTION _autonomous_fail_job(p_job_id bigint) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_numrows integer;
    v_status text;
BEGIN
    EXECUTE 'SELECT alert_text FROM @extschema@.job_status_text WHERE alert_code = 3'
        INTO v_status;
    UPDATE @extschema@.job_log SET
        end_time = current_timestamp,
        status = v_status
    WHERE job_id = p_job_id;
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    RETURN v_numrows;
END
$$;


CREATE OR REPLACE FUNCTION cancel_job(p_job_id bigint) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_pid       integer;
    v_step_id   bigint;
    v_status    text;
BEGIN
    EXECUTE 'SELECT alert_text FROM @extschema@.job_status_text WHERE alert_code = 3'
        INTO v_status;
    SELECT pid INTO v_pid FROM @extschema@.job_log WHERE job_id = p_job_id;
    PERFORM pg_cancel_backend(v_pid);
    SELECT max(step_id) INTO v_step_id FROM @extschema@.job_detail WHERE job_id = p_job_id;
    PERFORM @extschema@._autonomous_update_step(v_step_id, v_status, 'Manually cancelled via call to @extschema@.cancel_job()');
    PERFORM @extschema@._autonomous_fail_job(p_job_id);
    RETURN true;
END
$$;


CREATE OR REPLACE FUNCTION job_monitor() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_ok    text;
    v_bad   text;
BEGIN
    SELECT alert_text INTO v_ok FROM @extschema@.job_status_text WHERE alert_code = 1;
    SELECT alert_text INTO v_bad FROM @extschema@.job_status_text WHERE alert_code = 3;
    IF NEW.status = v_ok THEN
        DELETE FROM @extschema@.job_check_log WHERE job_name = NEW.job_name;
    ELSIF NEW.status = v_bad THEN
        INSERT INTO @extschema@.job_check_log (job_id, job_name) VALUES (NEW.job_id, NEW.job_name);
    ELSE
        -- Do nothing
    END IF;

    return null;
END
$$;


CREATE OR REPLACE FUNCTION check_job_status(p_history interval, OUT alert_code integer, OUT alert_text text) 
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_jobs                  RECORD;
    v_job_errors            RECORD;
    v_count                 int = 1;
    v_trouble               text[];
    v_alert_code_3          text;
BEGIN
    
    alert_text := '(';
    alert_code := 1;
    -- Generic check for jobs without special monitoring. Should error on 3 failures
    FOR v_job_errors IN SELECT l.job_name FROM @extschema@.job_check_log l 
        WHERE l.job_name NOT IN (SELECT c.job_name FROM @extschema@.job_check_config c WHERE l.job_name <> c.job_name) GROUP BY l.job_name HAVING count(*) > 2
    LOOP
        v_trouble[v_count] := v_job_errors.job_name;
        v_count := v_count+1;
    END LOOP;
    
    IF array_upper(v_trouble,1) > 0 THEN
        alert_code = 3;
        alert_text := alert_text || 'Jobs w/ 3 consecutive errors: '||array_to_string(v_trouble,', ')||'; ';
    END IF;

    SELECT jt.alert_text INTO v_alert_code_3 FROM @extschema@.job_status_text jt WHERE jt.alert_code = 3;
    
    -- Jobs with special monitoring (threshold different than 3 errors; must run within a timeframe; etc)
    FOR v_jobs IN 
                SELECT
                    job_name,
                    status, 
                    current_timestamp,
                    current_timestamp - start_time AS last_run_time,  
                    CASE
                        WHEN (SELECT count(*) FROM @extschema@.job_check_log WHERE job_name = job_check_config.job_name) > sensitivity THEN 'ERROR'  
                        WHEN start_time < (current_timestamp - error_threshold) THEN 'ERROR' 
                        WHEN start_time < (current_timestamp - warn_threshold) THEN 'WARNING'
                        ELSE 'OK'
                    END AS error_code,
                    CASE
                        WHEN status = v_alert_code_3 THEN 'CRITICAL'
                        WHEN status is null THEN 'MISSING' 
                        WHEN (start_time < current_timestamp - error_threshold) OR (start_time < current_timestamp - warn_threshold) THEN 
                            CASE 
                                WHEN status = 'OK' THEN 'MISSING'
                                else status
                            END
                    END AS job_status
                FROM
                    @extschema@.job_check_config 
                    LEFT JOIN (SELECT
                                    job_name,
                                    max(start_time) AS start_time 
                                FROM
                                    @extschema@.job_log
                                WHERE
                                    start_time > now() - p_history
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
        alert_text := alert_text || v_jobs.job_name || ': ' || coalesce(v_jobs.job_status,'null??') || '; ';
    END IF;

    IF v_jobs.error_code = 'WARNING' THEN
        IF alert_code <> 3 THEN
            alert_code := 2;
        END IF;
        alert_text := alert_text || v_jobs.job_name || ': ' || coalesce(v_jobs.job_status,'null??') || '; ';
    END IF;
    
    IF v_jobs.job_status = 'MISSING' THEN
        IF v_jobs.last_run_time IS NULL THEN  
            alert_text := alert_text || ' - Last run over ' || p_history || ' ago. Check job_log for more details; ';
        ELSE
            alert_text := alert_text || ' - Last run at ' || current_timestamp - v_jobs.last_run_time || '; ';
        END IF; 
    END IF;

END LOOP;

IF alert_text = '(' THEN
    alert_text := alert_text || 'All jobs run successfully';
END IF;

alert_text := alert_text || ')';

END
$$;
