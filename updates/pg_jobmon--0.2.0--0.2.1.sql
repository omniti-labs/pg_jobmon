DROP FUNCTION IF EXISTS @extschema@.close_job(bigint);
DROP FUNCTION IF EXISTS @extschema@.close_job(bigint, text);
DROP FUNCTION IF EXISTS  @extschema@.fail_job(bigint);
DROP FUNCTION IF EXISTS  @extschema@.fail_job(bigint, text);
DROP FUNCTION IF EXISTS @extschema@.cancel_job(bigint);
DROP FUNCTION IF EXISTS @extschema@.cancel_job(bigint, text);


CREATE FUNCTION close_job(p_job_id bigint, text default '@extschema@.job_alert_nagios') RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remote_query text;
    v_dblink_schema text;
BEGIN

    SELECT nspname INTO v_dblink_schema FROM pg_namespace n, pg_extension e WHERE e.extname = 'dblink' AND e.extnamespace = n.oid;
    
    v_remote_query := 'SELECT @extschema@._autonomous_close_job('||p_job_id||', '''|| $2 ||''')'; 

    EXECUTE 'SELECT devnull FROM ' || v_dblink_schema || '.dblink(''dbname=' || current_database() ||
        ''',' || quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  
END
$$;


CREATE FUNCTION fail_job(p_job_id bigint, text default '@extschema@.job_alert_nagios') RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remote_query text;
    v_dblink_schema text;
BEGIN
    
    SELECT nspname INTO v_dblink_schema FROM pg_namespace n, pg_extension e WHERE e.extname = 'dblink' AND e.extnamespace = n.oid;
    
    v_remote_query := 'SELECT @extschema@._autonomous_fail_job('||p_job_id||', '''|| $2 ||''')'; 

    EXECUTE 'SELECT devnull FROM ' || v_dblink_schema || '.dblink(''dbname=' || current_database() ||
        ''',' || quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  

END
$$;


CREATE FUNCTION cancel_job(p_job_id bigint, text default '@extschema@.job_alert_nagios') RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_pid       integer;
    v_step_id   bigint;
    v_status    text;
BEGIN
    EXECUTE 'SELECT error_text FROM ' || $2 || ' WHERE error_code = 3'
        INTO v_status;
    SELECT pid INTO v_pid FROM @extschema@.job_log WHERE job_id = p_job_id;
    PERFORM pg_cancel_backend(v_pid);
    SELECT max(step_id) INTO v_step_id FROM @extschema@.job_detail WHERE job_id = p_job_id;
    PERFORM @extschema@._autonomous_update_step(p_job_id, v_step_id, v_status, 'Manually cancelled via call to @extschema@.cancel_job()');
    PERFORM @extschema@._autonomous_fail_job(p_job_id, $2);
    RETURN true;
END
$$;


CREATE OR REPLACE FUNCTION show_detail(p_name text, int default 1) RETURNS SETOF @extschema@.job_detail
    LANGUAGE plpgsql
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


CREATE OR REPLACE FUNCTION show_job_status(p_name text, p_status text, int default 10) RETURNS SETOF @extschema@.job_log
    LANGUAGE plpgsql
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


CREATE OR REPLACE FUNCTION show_running(int default 10) RETURNS SETOF @extschema@.job_log
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_job_list      @extschema@.job_log%ROWTYPE;
BEGIN
    FOR v_job_list IN SELECT job_id, owner, job_name, start_time, end_time, status, pid  
        FROM @extschema@.job_log j
        JOIN pg_stat_activity p ON j.pid = p.procpid
        WHERE status IS NULL
        ORDER BY job_id DESC
        LIMIT $1
    LOOP
        RETURN NEXT v_job_list; 
    END LOOP;

    RETURN;
END
$$;
