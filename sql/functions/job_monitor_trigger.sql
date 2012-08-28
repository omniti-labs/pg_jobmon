/*
 *  Job Monitor Trigger
 */
CREATE FUNCTION job_monitor() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_ok    text;
    v_bad   text;
BEGIN
    SELECT alert_text INTO v_ok FROM @extschema@.job_status_text WHERE alert_code = 1;
    SELECT alert_text INTO v_bad FROM @extschema@.job_status_text WHERE alert_code = 3;
    IF NEW.status = v_ok THEN
        DELETE FROM @extschema@.job_check_log WHERE job_name = NEW.job_name;
    ELSIF NEW.status = v_bad THEN
        INSERT INTO @extschema@.job_check_log (job_id, job_name) VALUES (NEW.job_id, NEW.job_name);
    ELSE
        -- Do nothing
    END IF;

    return null;
END
$$;
-- Create trigger on table
CREATE TRIGGER trg_job_monitor AFTER UPDATE ON job_log FOR EACH ROW EXECUTE PROCEDURE job_monitor();
