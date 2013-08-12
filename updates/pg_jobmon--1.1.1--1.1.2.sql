-- Bugfix: Fixed show_running() to only match against non-idle queries when joining against pg_stat_activty. Still a chance of false result (see doc file), but much less likely now.

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
        WHERE p.state <> 'idle'
        AND j.status IS NULL
        ORDER BY j.job_id DESC
        LIMIT $1
    LOOP
        RETURN NEXT v_job_list; 
    END LOOP;
ELSE 
    FOR v_job_list IN SELECT j.job_id, j.owner, j.job_name, j.start_time, j.end_time, j.status, j.pid  
        FROM @extschema@.job_log j
        JOIN pg_stat_activity p ON j.pid = p.procpid
        WHERE p.current_query <> '<IDLE>' 
        AND j.status IS NULL
        ORDER BY j.job_id DESC
        LIMIT $1
    LOOP
        RETURN NEXT v_job_list; 
    END LOOP;
END IF;

RETURN;

END
$$;
