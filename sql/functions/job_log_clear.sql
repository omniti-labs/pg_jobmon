/*
 *  Delete jobs from job_log and job_detail table older than a given interval.
 *  Also logs this job purging task.
 */
CREATE FUNCTION job_log_clear(p_interval interval) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    
    v_boundary      timestamptz;
    v_job_id        bigint;
    v_rowcount      bigint;
    v_step_id       bigint;

BEGIN

v_boundary := now() - p_interval;
v_job_id := @extschema@.add_job('Purging pg_jobmon job logs older than '|| v_boundary);
v_step_id := @extschema@.add_step(v_job_id,'Purging pg_jobmon job logs older than '|| v_boundary);

DELETE FROM @extschema@.job_log WHERE start_time <= v_boundary;

GET DIAGNOSTICS v_rowcount = ROW_COUNT;
IF v_rowcount > 0 THEN
    RAISE NOTICE 'Deleted % rows from job_log and associated rows in job_detail', v_rowcount;
    PERFORM @extschema@.update_step(v_step_id, 'OK', 'Deleted '||v_rowcount||' rows from job_log and associated rows in job_detail');
ELSE
    RAISE NOTICE 'No jobs logged older than %', v_boundary;
    PERFORM @extschema@.update_step(v_step_id, 'OK', 'No jobs logged older than '|| v_boundary);
END IF;
PERFORM @extschema@.close_job(v_job_id);
RETURN;

EXCEPTION
    WHEN OTHERS THEN
        IF v_step_id IS NULL THEN
            v_step_id := @extschema@.add_step(v_job_id, 'EXCEPTION before first step logged');
        END IF;
        PERFORM @extschema@.update_step(v_step_id, 'CRITICAL', 'ERROR: '||coalesce(SQLERRM,'unknown'));
        PERFORM @extschema@.fail_job(v_job_id);
        RAISE EXCEPTION '%', SQLERRM;
END
$$;
