-- Show job custom name
CREATE FUNCTION show_job(p_name text, int default 10) RETURNS SETOF @extschema@.job_log
    LANGUAGE plpgsql
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

-- Show job name like
CREATE FUNCTION show_job_like(p_name text, int default 10) RETURNS SETOF @extschema@.job_log
    LANGUAGE plpgsql
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


-- Status Any name
CREATE FUNCTION show_job_status(p_status text, int default 10) RETURNS SETOF @extschema@.job_log
    LANGUAGE plpgsql
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

-- Status Custom name
CREATE FUNCTION show_job_status(p_name text, p_status text, int default 10) RETURNS SETOF @extschema@.job_log
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
        LIMIT $2
    LOOP
        RETURN NEXT v_job_list; 
    END LOOP;

    RETURN;
END
$$;


-- Detail by job id
CREATE FUNCTION show_detail(p_id bigint) RETURNS SETOF @extschema@.job_detail
    LANGUAGE plpgsql
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

-- Detail by jobname

CREATE FUNCTION show_detail(p_name text, int default 10) RETURNS SETOF @extschema@.job_detail
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


-- Running jobs
CREATE FUNCTION show_running(int default 10) RETURNS SETOF @extschema@.job_log
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
        LIMIT $2
    LOOP
        RETURN NEXT v_job_list; 
    END LOOP;

    RETURN;
END
$$;

