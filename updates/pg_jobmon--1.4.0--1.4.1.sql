-- Fix incorrect data type usage in the add_job() function (Github Issue #14).


/*
 *  Add Step
 */
CREATE OR REPLACE FUNCTION add_step(p_job_id bigint, p_action text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE 
    v_step_id bigint;
    v_remote_query text;
    v_dblink_schema text;
    
BEGIN

    SELECT nspname INTO v_dblink_schema FROM pg_namespace n, pg_extension e WHERE e.extname = 'dblink' AND e.extnamespace = n.oid;
    
    v_remote_query := 'SELECT @extschema@._autonomous_add_step (' ||
        p_job_id || ',' ||
        quote_literal(p_action) || ')';

    EXECUTE 'SELECT step_id FROM ' || v_dblink_schema || '.dblink('||quote_literal(@extschema@.auth())||
        ','|| quote_literal(v_remote_query) || ',TRUE) t (step_id bigint)' INTO v_step_id;

    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'Job creation failed';
    END IF;

    RETURN v_step_id;
END
$$;
