/*
 *  Fail Job Autonomous
 */
CREATE FUNCTION _autonomous_fail_job(p_job_id bigint) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_numrows integer;
    v_status text;
BEGIN
    EXECUTE 'SELECT alert_text FROM @extschema@.job_status_text WHERE alert_code = 3'
        INTO v_status;
    UPDATE @extschema@.job_log SET
        end_time = current_timestamp,
        status = v_status
    WHERE job_id = p_job_id;
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    RETURN v_numrows;
END
$$;

/*
 *  Fail Job
 */
CREATE FUNCTION fail_job(p_job_id bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remote_query text;
    v_dblink_schema text;
BEGIN
    
    SELECT nspname INTO v_dblink_schema FROM pg_namespace n, pg_extension e WHERE e.extname = 'dblink' AND e.extnamespace = n.oid;
    
    v_remote_query := 'SELECT @extschema@._autonomous_fail_job('||p_job_id||')'; 

    EXECUTE 'SELECT devnull FROM ' || v_dblink_schema || '.dblink('''||@extschema@.auth()||'dbname='|| current_database() ||
        ''',' || quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  

END
$$;
