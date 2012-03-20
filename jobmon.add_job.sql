SET search_path = jobmon, pg_catalog;

CREATE OR REPLACE FUNCTION _autonomous_add_job(p_owner text, p_job_name text, p_pid integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_job_id INTEGER;
BEGIN
    SELECT nextval('jobmon.job_log_job_id_seq') INTO v_job_id;

    INSERT INTO jobmon.job_log (job_id, owner, job_name, start_time, pid)
    VALUES (v_job_id, p_owner, p_job_name, current_timestamp, p_pid); 

    RETURN v_job_id; 
END
$$;


CREATE FUNCTION add_job(p_job_name text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE 
    v_job_id INTEGER;
    v_remote_query TEXT;
BEGIN
    v_remote_query := 'SELECT jobmon._autonomous_add_job (' ||
        quote_literal(current_user) || ',' ||
        quote_literal(p_job_name) || ',' ||
        pg_backend_pid() || ')';

    EXECUTE 'SELECT job_id FROM dblink.dblink(''dbname='|| current_database() ||
        ''','|| quote_literal(v_remote_query) || ',TRUE) t (job_id int)' INTO v_job_id;      

    IF v_job_id IS NULL THEN
        RAISE EXCEPTION 'Job creation failed';
    END IF;

    RETURN v_job_id;
END
$$;
