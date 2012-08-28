/*
 *  Log a complete, single query job
 */
CREATE FUNCTION sql_job(p_job_name text, p_sql text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_job_id    bigint;
    v_step_id   bigint;
    v_numrows   bigint;
    v_adv_lock  boolean;
    v_return    text;
BEGIN
    v_job_id := @extschema@.add_job(p_job_name);
    
    -- Take advisory lock to prevent multiple calls to function overlapping
    v_adv_lock := pg_try_advisory_lock(hashtext('sql_log'), hashtext(p_job_name));
    IF v_adv_lock = 'false' THEN
        v_step_id := @extschema@.add_step(v_job_id,'Obtaining advisory lock for job: '||v_job_name);
        PERFORM @extschema@.update_step(v_step_id, 'OK','Found concurrent job. Exiting gracefully');
        PERFORM @extschema@.close_job(v_job_id);
        RETURN 'Concurrent job found. Obtaining advisory lock FAILED for job: %', v_job_name;
    END IF;

    v_step_id := @extschema@.add_step(v_job_id, 'Running sql: ' || quote_literal(p_sql));
    EXECUTE p_sql;
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    PERFORM @extschema@.update_step(v_step_id, 'OK', 'Rows affected: ' || v_numrows);
    PERFORM @extschema@.close_job(v_job_id);
    
    PERFORM pg_advisory_unlock(hashtext('sql_log'), hashtext(p_job_name));

    RETURN 'Job logged with job id: ' || v_job_id;

EXCEPTION
    WHEN OTHERS THEN 
        PERFORM @extschema@.update_step(v_step_id, 'CRITICAL', 'ERROR: '||coalesce(SQLERRM,'unknown'));
        PERFORM @extschema@.fail_job(v_job_id);
        PERFORM pg_advisory_unlock(hashtext('sql_log'), hashtext(p_job_name));
        RETURN 'Job ID ' || v_job_id || ' failed. See job_detail table for more details';
END
$$;
