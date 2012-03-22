CREATE FUNCTION _autonomous_add_step(p_job_id integer, p_action text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_step_id INTEGER;
BEGIN
    SELECT nextval('job_detail_step_id_seq') INTO v_step_id;

    INSERT INTO job_detail (job_id, step_id, action, start_time)
    VALUES (p_job_id, v_step_id, p_action, current_timestamp);

    RETURN v_step_id;
END
$$;


CREATE FUNCTION add_step(p_job_id integer, p_action text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE 
    v_step_id INTEGER;
    v_remote_query TEXT;
BEGIN
    v_remote_query := 'SELECT _autonomous_add_step (' ||
        p_job_id || ',' ||
        quote_literal(p_action) || ')';

    EXECUTE 'SELECT step_id FROM dblink.dblink(''dbname='|| current_database() ||
        ''','|| quote_literal(v_remote_query) || ',TRUE) t (step_id int)' INTO v_step_id;      

    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'Job creation failed';
    END IF;

    RETURN v_step_id;
END
$$;
