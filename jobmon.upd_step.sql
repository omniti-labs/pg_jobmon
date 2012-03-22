SET search_path = jobmon, pg_catalog;

CREATE FUNCTION _autonomous_upd_step(p_job_id integer, p_step_id integer, p_status text, p_message text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_numrows integer;
BEGIN
    UPDATE job_detail SET 
        end_time = current_timestamp,
        elapsed_time = date_part('epoch',now() - start_time)::integer,
        status = p_status,
        message = p_message
    WHERE job_id = p_job_id AND step_id = p_step_id; 
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    RETURN v_numrows;
END
$$;


CREATE FUNCTION upd_step(p_job_id integer, p_step_id integer, p_status text, p_message text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remote_query TEXT;
BEGIN
    v_remote_query := 'SELECT _autonomous_upd_step ('||
    p_job_id || ',' ||
    p_step_id || ',' ||
    quote_literal(p_status) || ',' ||
    quote_literal(p_message) || ')';

    EXECUTE 'SELECT devnull FROM dblink.dblink(''dbname=' || current_database() ||
        ''','|| quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  
END
$$;
