/*
 *  Job Monitor Trigger
 */
CREATE OR REPLACE FUNCTION job_monitor() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_alert_code    int;
BEGIN

    SELECT alert_code INTO v_alert_code FROM @extschema@.job_status_text WHERE alert_text = NEW.status;
    IF v_alert_code IS NOT NULL THEN
        IF v_alert_code = 1 THEN
            DELETE FROM @extschema@.job_check_log WHERE job_name = NEW.job_name;
        ELSE
            INSERT INTO @extschema@.job_check_log (job_id, job_name, alert_code) VALUES (NEW.job_id, NEW.job_name, v_alert_code);
        END IF;
    END IF;

    RETURN NULL;
END
$$;

CREATE TRIGGER trg_job_monitor 
AFTER UPDATE ON @extschema@.job_log 
FOR EACH ROW EXECUTE PROCEDURE @extschema@.job_monitor();
