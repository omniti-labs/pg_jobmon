CREATE FUNCTION job_check_log_escalate_trig() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE

v_count                         int;
v_escalate                      int;
v_highest_logged_alert_code     int;
v_max_alert_code                int;
v_step_id                       bigint;

BEGIN

SELECT escalate INTO v_escalate FROM @extschema@.job_check_config WHERE job_name = NEW.job_name;
IF v_escalate IS NOT NULL THEN
    -- Only get the count of the highest number of failures for an alert code for a specific job
    SELECT count(job_name)
        , alert_code 
    INTO v_count
        , v_highest_logged_alert_code 
    FROM @extschema@.job_check_log 
    WHERE job_name = NEW.job_name 
    GROUP BY job_name, alert_code 
    ORDER BY alert_code DESC 
    LIMIT 1 ;

    -- Ensure new alert codes are always equal to at least the last escalated value
    IF v_highest_logged_alert_code > NEW.alert_code THEN
       NEW.alert_code = v_highest_logged_alert_code; 
    END IF;

    -- +1 to ensure the insertion that matches the v_escalate value triggers the escalation, not the next insertion
    IF v_count + 1 >= v_escalate THEN
        SELECT max(alert_code) INTO v_max_alert_code FROM @extschema@.job_status_text;
        IF NEW.alert_code < v_max_alert_code THEN -- Don't exceed the highest configured alert code
            NEW.alert_code = NEW.alert_code + 1;
            -- Log that alert code was escalated by the last job that failed
            EXECUTE 'SELECT @extschema@.add_step('||NEW.job_id||', ''ALERT ESCALATION'')' INTO v_step_id;
            EXECUTE 'SELECT @extschema@.update_step('||v_step_id||', ''ESCALATE'', 
                ''Job has alerted at level '||NEW.alert_code - 1 ||' in excess of the escalate value configured for this job ('||v_escalate||
                    '). Alert code value has been escaleted to: '||NEW.alert_code||''')';
            EXECUTE 'UPDATE @extschema@.job_log SET status = ''ESCALATED'' WHERE job_id = '||NEW.job_id;
        END IF;
    END IF;
END IF; 

RETURN NEW;
END
$$;


CREATE TRIGGER job_check_log_escalate_trig
BEFORE INSERT ON @extschema@.job_check_log
FOR EACH ROW EXECUTE PROCEDURE job_check_log_escalate_trig();


