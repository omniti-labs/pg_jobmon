SET search_path = jobmon, pg_catalog;

CREATE FUNCTION manage_job_check() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.status = 'OK' THEN
        DELETE FROM jobmon.job_check WHERE job_name = NEW.job_name;
    ELSIF NEW.status = 'BAD' THEN
        INSERT INTO jobmon.job_check (job_id, job_name) VALUES (NEW.job_id, NEW.job_name);
    ELSE
        -- Do nothing
    END IF;

    return null;
END
$$;
