SET search_path = jobmon, pg_catalog;

CREATE FUNCTION _autonomous_fail_job(p_job_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_numrows integer;
BEGIN
    UPDATE job_log SET
        end_time = current_timestamp,
        status = 'BAD'
    WHERE job_id = p_job_id;
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    RETURN v_numrows;
END
$$;


CREATE FUNCTION fail_job(p_job_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remote_query TEXT;
BEGIN
    v_remote_query := 'SELECT _autonomous_fail_job('||p_job_id||')'; 

    EXECUTE 'SELECT devnull FROM dblink.dblink(''dbname=' || current_database() ||
        ''',' || quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  

END
$$;
