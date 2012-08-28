/*
 *  Log a single query step
 */
CREATE FUNCTION sql_step(p_job_id bigint, p_action text, p_sql text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_step_id   bigint;
    v_numrows   bigint;
BEGIN
    v_step_id := @extschema@.add_step(p_job_id, p_action);
    EXECUTE p_sql;
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    PERFORM @extschema@.update_step(v_step_id, 'OK', 'Rows affected: ' || v_numrows);
    PERFORM @extschema@.close_job(p_job_id);

    RETURN true;
EXCEPTION
    WHEN OTHERS THEN
        PERFORM @extschema@.update_step(v_step_id, 'CRITICAL', 'ERROR: '||coalesce(SQLERRM,'unknown'));
        RETURN false;
END
$$;
