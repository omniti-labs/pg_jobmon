/*
 *  Cancel Job
 */
CREATE FUNCTION cancel_job(p_job_id bigint) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_pid       integer;
    v_step_id   bigint;
    v_status    text;
BEGIN
    EXECUTE 'SELECT alert_text FROM @extschema@.job_status_text WHERE alert_code = 3'
        INTO v_status;
    SELECT pid INTO v_pid FROM @extschema@.job_log WHERE job_id = p_job_id;
    PERFORM pg_cancel_backend(v_pid);
    SELECT max(step_id) INTO v_step_id FROM @extschema@.job_detail WHERE job_id = p_job_id;
    PERFORM @extschema@._autonomous_update_step(v_step_id, v_status, 'Manually cancelled via call to @extschema@.cancel_job()');
    PERFORM @extschema@._autonomous_fail_job(p_job_id);
    RETURN true;
END
$$;
