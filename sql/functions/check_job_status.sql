/*
 *  Check Job status
 *
 * p_history is how far into job_log's past the check will go. Don't go further back than the longest job's interval that is contained
 *      in job_check_config to keep check efficient
 * Return code 1 means a successful job run
 * Return code 2 is for use with jobs that support a warning indicator. Not critical, but someone should look into it
 * Return code 3 is for use with a critical job failure 
 */
CREATE FUNCTION check_job_status(p_history interval, OUT alert_code integer, OUT alert_text text) 
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

IF alert_text = '(' THEN
    alert_text := alert_text || 'All jobs run successfully';
END IF;

alert_text := alert_text || ')';

END
$$;
