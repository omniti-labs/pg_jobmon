/*
 *  Job Monitor Trigger
 */
CREATE FUNCTION job_monitor() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bad   text;
    v_ok    text;
    v_warn  text;
BEGIN
    SELECT alert_text INTO v_ok FROM @extschema@.job_status_text WHERE alert_code = 1;
    SELECT alert_text INTO v_warn FROM @extschema@.job_status_text WHERE alert_code = 2;
    SELECT alert_text INTO v_bad FROM @extschema@.job_status_text WHERE alert_code = 3;
    IF NEW.status = v_ok THEN
        DELETE FROM @extschema@.job_check_log WHERE job_name = NEW.job_name;
    ELSIF NEW.status = v_warn THEN
        INSERT INTO @extschema@.job_check_log (job_id, job_name, alert_code) VALUES (NEW.job_id, NEW.job_name, 2);        
    ELSIF NEW.status = v_bad THEN
        INSERT INTO @extschema@.job_check_log (job_id, job_name, alert_code) VALUES (NEW.job_id, NEW.job_name, 3);
    ELSE
        -- Do nothing
    END IF;

    return null;
END
$$;
