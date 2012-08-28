/*
 *  Show Currently Running Jobs
 */
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
        LIMIT $1
    LOOP
        RETURN NEXT v_job_list; 
    END LOOP;

    RETURN;
END
$$;
