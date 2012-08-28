/*
 *  Update Step Autonomous
 */
CREATE FUNCTION _autonomous_update_step(p_step_id bigint, p_status text, p_message text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_numrows integer;
BEGIN
    UPDATE @extschema@.job_detail SET 
        end_time = current_timestamp,
        elapsed_time = date_part('epoch',now() - start_time)::real,
        status = p_status,
        message = p_message
    WHERE step_id = p_step_id; 
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    RETURN v_numrows;
END
$$;

/*
 *  Update Step
 */
CREATE FUNCTION update_step(p_step_id bigint, p_status text, p_message text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remote_query text;
    v_dblink_schema text;
BEGIN
    SELECT nspname INTO v_dblink_schema FROM pg_namespace n, pg_extension e WHERE e.extname = 'dblink' AND e.extnamespace = n.oid;
    
    v_remote_query := 'SELECT @extschema@._autonomous_update_step ('||
    p_step_id || ',' ||
    quote_literal(p_status) || ',' ||
    quote_literal(p_message) || ')';

    EXECUTE 'SELECT devnull FROM ' || v_dblink_schema || '.dblink('''||@extschema@.auth()||'dbname='|| current_database() ||
        ''','|| quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  
END
$$;
