SET search_path = jobmon, pg_catalog;

CREATE FUNCTION _autonomous_cancel_job(p_job_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    p_pid INTEGER;
BEGIN
    SELECT pid FROM job_logs WHERE job_id = p_job_id INTO p_pid;
    SELECT pg_cancel_backend(p_pid);
    SELECT _autonomous_fail_job(p_job_id);    
END
$$;
