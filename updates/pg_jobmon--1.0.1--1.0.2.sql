-- Fixed unhandled case in check_job_status where if a job had been run but never finished with an end_time or status set in job_log, it wouldn't raise an alert that is was missing
-- Set functions that can be marked as STABLE


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
    LANGUAGE plpgsql STABLE
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
                WHEN (SELECT count(*) FROM @extschema@.job_check_log l WHERE job_name = job_check_config.job_name and l.alert_code = 3 ) > sensitivity THEN 'ERROR'  
                WHEN end_time < (current_timestamp - error_threshold) THEN 'ERROR'
                WHEN (SELECT count(*) FROM @extschema@.job_check_log l WHERE job_name = job_check_config.job_name and l.alert_code = 2 ) > sensitivity THEN 'WARNING'   
                WHEN end_time < (current_timestamp - warn_threshold) THEN 'WARNING'
                WHEN end_time IS NULL THEN 'ERROR'
                ELSE 'OK'
            END AS error_code,
            CASE
                WHEN status = v_alert_code_3 THEN 'CRITICAL'
                WHEN status is null THEN 'MISSING' 
                WHEN (end_time < current_timestamp - error_threshold) OR (end_time < current_timestamp - warn_threshold OR end_time IS NULL) THEN 
                    'MISSING'
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
                WHEN (SELECT count(*) FROM @extschema@.job_check_log l WHERE job_name = job_check_config.job_name and l.alert_code = 3 ) > sensitivity THEN 'ERROR'  
                WHEN end_time < (current_timestamp - error_threshold) THEN 'ERROR'
                WHEN (SELECT count(*) FROM @extschema@.job_check_log l WHERE job_name = job_check_config.job_name and l.alert_code = 2 ) > sensitivity THEN 'WARNING'    
                WHEN end_time < (current_timestamp - warn_threshold) THEN 'WARNING'
                WHEN end_time IS NULL THEN 'ERROR'
                ELSE 'OK'
            END AS error_code,
            CASE
                WHEN status = v_alert_code_3 THEN 'CRITICAL'
                WHEN status is null THEN 'MISSING' 
                WHEN (end_time < current_timestamp - error_threshold) OR (end_time < current_timestamp - warn_threshold OR end_time IS NULL) THEN 
                    'MISSING'
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
 * Helper function to allow calling without an argument. See below for full function
 */
CREATE OR REPLACE FUNCTION check_job_status(OUT alert_code integer, OUT alert_text text)
    LANGUAGE plpgsql STABLE
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
 *  dblink Authentication mapping
 */
CREATE OR REPLACE FUNCTION auth() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
 
    v_auth          text = '';
    v_port          text;
    v_password      text; 
    v_username      text;
 
BEGIN
    SELECT username, port, pwd INTO v_username, v_port, v_password FROM @extschema@.dblink_mapping;

    IF v_port IS NULL THEN
        v_auth = 'dbname=' || current_database();
    ELSE
        v_auth := 'port='||v_port||' dbname=' || current_database();
    END IF;

    IF v_username IS NOT NULL THEN
        v_auth := v_auth || ' user='||v_username;
    END IF;

    IF v_password IS NOT NULL THEN
        v_auth := v_auth || ' password='||v_password;
    END IF;
    RETURN v_auth;    
END
$$;


/*
 *  Show Job Details By Job ID
 */
CREATE OR REPLACE FUNCTION show_detail(p_id bigint) RETURNS SETOF @extschema@.job_detail
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_job_detail     @extschema@.job_detail%ROWTYPE;
BEGIN
    FOR v_job_detail IN SELECT job_id, step_id, action, start_time, end_time, elapsed_time, status, message
        FROM @extschema@.job_detail
        WHERE job_id = p_id
        ORDER BY step_id ASC
    LOOP
        RETURN NEXT v_job_detail; 
    END LOOP;

    RETURN;
END
$$;


/*
 *  Show Job Details By Exact Name
 */
CREATE OR REPLACE FUNCTION show_detail(p_name text, int default 1) RETURNS SETOF @extschema@.job_detail
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_job_list      @extschema@.job_log%ROWTYPE;
    v_job_detail     @extschema@.job_detail%ROWTYPE;
BEGIN

    FOR v_job_list IN SELECT job_id, owner, job_name, start_time, end_time, status, pid  
        FROM @extschema@.job_log
        WHERE job_name = upper(p_name)
        ORDER BY job_id DESC
        LIMIT $2
    LOOP
        FOR v_job_detail IN SELECT job_id, step_id, action, start_time, end_time, elapsed_time, status, message
            FROM @extschema@.job_detail
            WHERE job_id = v_job_list.job_id
            ORDER BY step_id ASC
        LOOP
            RETURN NEXT v_job_detail; 
        END LOOP;
    END LOOP;

    RETURN;
END
$$;


/*
 *  Show Jobs By Exact Name
 */
CREATE OR REPLACE FUNCTION show_job(p_name text, int default 10) RETURNS SETOF @extschema@.job_log
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_job_list      @extschema@.job_log%ROWTYPE;
BEGIN
    FOR v_job_list IN SELECT job_id, owner, job_name, start_time, end_time, status, pid  
        FROM @extschema@.job_log
        WHERE job_name = upper(p_name)
        ORDER BY job_id DESC
        LIMIT $2
    LOOP
        RETURN NEXT v_job_list; 
    END LOOP;

    RETURN;
END
$$;


/*
 *  Show Jobs Like Name
 */
CREATE OR REPLACE FUNCTION show_job_like(p_name text, int default 10) RETURNS SETOF @extschema@.job_log
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_job_list      @extschema@.job_log%ROWTYPE;
BEGIN
    FOR v_job_list IN SELECT job_id, owner, job_name, start_time, end_time, status, pid  
        FROM @extschema@.job_log
        WHERE job_name ~ upper(p_name)
        ORDER BY job_id DESC
        LIMIT $2
    LOOP
        RETURN NEXT v_job_list; 
    END LOOP;

    RETURN;
END
$$;


/*
 *  Show Jobs By Status
 */
CREATE OR REPLACE FUNCTION show_job_status(p_status text, int default 10) RETURNS SETOF @extschema@.job_log
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_job_list      @extschema@.job_log%ROWTYPE;
BEGIN
    FOR v_job_list IN SELECT job_id, owner, job_name, start_time, end_time, status, pid  
        FROM @extschema@.job_log
        WHERE status = p_status
        ORDER BY job_id DESC
        LIMIT $2
    LOOP
        RETURN NEXT v_job_list; 
    END LOOP;

    RETURN;
END
$$;

/*
 *  Show Jobs By Exact Name and Status
 */
CREATE OR REPLACE FUNCTION show_job_status(p_name text, p_status text, int default 10) RETURNS SETOF @extschema@.job_log
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_job_list      @extschema@.job_log%ROWTYPE;
BEGIN
    FOR v_job_list IN SELECT job_id, owner, job_name, start_time, end_time, status, pid  
        FROM @extschema@.job_log
        WHERE job_name = upper(p_name)
        AND status = p_status
        ORDER BY job_id DESC
        LIMIT $3
    LOOP
        RETURN NEXT v_job_list; 
    END LOOP;

    RETURN;
END
$$;


/*
 *  Show Currently Running Jobs
 */
CREATE OR REPLACE FUNCTION show_running(int default 10) RETURNS SETOF @extschema@.job_log
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_job_list      @extschema@.job_log%ROWTYPE;
    v_version       int;
BEGIN

SELECT current_setting('server_version_num')::int INTO v_version;

IF v_version >= 90200 THEN
    FOR v_job_list IN SELECT j.job_id, j.owner, j.job_name, j.start_time, j.end_time, j.status, j.pid  
        FROM @extschema@.job_log j
        JOIN pg_stat_activity p ON j.pid = p.pid
        WHERE j.status IS NULL
        ORDER BY j.job_id DESC
        LIMIT $1
    LOOP
        RETURN NEXT v_job_list; 
    END LOOP;
ELSE 
    FOR v_job_list IN SELECT j.job_id, j.owner, j.job_name, j.start_time, j.end_time, j.status, j.pid  
        FROM @extschema@.job_log j
        JOIN pg_stat_activity p ON j.pid = p.procpid
        WHERE j.status IS NULL
        ORDER BY j.job_id DESC
        LIMIT $1
    LOOP
        RETURN NEXT v_job_list; 
    END LOOP;
END IF;

RETURN;

END
$$;
