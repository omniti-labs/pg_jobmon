/*
 *  Show Job Details By Job ID
 */
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

/*
 *  Show Job Details By Exact Name
 */
CREATE FUNCTION show_detail(p_name text, int default 1) RETURNS SETOF @extschema@.job_detail
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
