/*
 *  Show Jobs Like Name
 */
CREATE FUNCTION show_job_like(p_name text, int default 10) RETURNS SETOF @extschema@.job_log
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
