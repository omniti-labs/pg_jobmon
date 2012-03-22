-- ########## pg_jobmon extension table definitions ##########
-- See about making these into partitioned tables by start_time
CREATE TABLE job_log (
    job_id bigint NOT NULL,
    owner text NOT NULL,
    job_name text NOT NULL,
    start_time timestamp without time zone NOT NULL,
    end_time timestamp without time zone,
    status text,
    pid integer NOT NULL,
    PRIMARY KEY (job_id)
);
SELECT pg_catalog.pg_extension_config_dump('job_log', '');
CREATE INDEX job_log_job_name ON job_log (job_name);
CREATE INDEX job_log_start_time ON job_log (start_time);
CREATE INDEX job_log_pid ON job_log (pid);
CREATE SEQUENCE job_log_job_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE job_log_job_id_seq OWNED BY job_log.job_id;
ALTER TABLE job_log ALTER COLUMN job_id SET DEFAULT nextval('job_log_job_id_seq'::regclass);
CREATE TRIGGER trg_job_monitor AFTER UPDATE ON job_masters FOR EACH ROW EXECUTE PROCEDURE job_monitor();


CREATE TABLE job_detail (
    job_id bigint NOT NULL,
    step_id bigint NOT NULL,
    action text NOT NULL,
    start_time timestamp without time zone NOT NULL,
    end_time timestamp without time zone,
    elapsed_time integer,
    status text,
    message text
    PRIMARY KEY (job_id, step_id)
);
SELECT pg_catalog.pg_extension_config_dump('job_detail', '');
ALTER TABLE job_detail ADD CONSTRAINT job_detail_job_id_fkey FOREIGN KEY (job_id) REFERENCES job_log(job_id);
CREATE SEQUENCE job_detail_step_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE job_detail_step_id_seq OWNED BY job_detail.step_id;
ALTER TABLE job_detail ALTER COLUMN step_id SET DEFAULT nextval('job_detail_step_id_seq'::regclass);


CREATE TABLE job_check_log (
    job_id integer NOT NULL,
    job_name text NOT NULL
);
SELECT pg_catalog.pg_extension_config_dump('job_check_log', '');

CREATE TABLE job_check_config (
    job_name text NOT NULL,
    warn_threshold interval NOT NULL,
    error_threshold interval NOT NULL,
    active boolean DEFAULT false NOT NULL,
--    escalate text DEFAULT 'email'::text NOT NULL,
    sensitivity smallint DEFAULT 0 NOT NULL,
    PRIMARY KEY (job_name)
);
SELECT pg_catalog.pg_extension_config_dump('job_check_config', '');



-- ########## pg_jobmon extension function definitions ##########
CREATE OR REPLACE FUNCTION _autonomous_add_job(p_owner text, p_job_name text, p_pid integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_job_id INTEGER;
BEGIN
    SELECT nextval('jobmon.job_log_job_id_seq') INTO v_job_id;

    INSERT INTO job_log (job_id, owner, job_name, start_time, pid)
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


CREATE FUNCTION _autonomous_add_step(p_job_id integer, p_action text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_step_id INTEGER;
BEGIN
    SELECT nextval('job_detail_step_id_seq') INTO v_step_id;

    INSERT INTO job_detail (job_id, step_id, action, start_time)
    VALUES (p_job_id, v_step_id, p_action, current_timestamp);

    RETURN v_step_id;
END
$$;


CREATE FUNCTION add_step(p_job_id integer, p_action text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE 
    v_step_id INTEGER;
    v_remote_query TEXT;
BEGIN
    v_remote_query := 'SELECT _autonomous_add_step (' ||
        p_job_id || ',' ||
        quote_literal(p_action) || ')';

    EXECUTE 'SELECT step_id FROM dblink.dblink(''dbname='|| current_database() ||
        ''','|| quote_literal(v_remote_query) || ',TRUE) t (step_id int)' INTO v_step_id;      

    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'Job creation failed';
    END IF;

    RETURN v_step_id;
END
$$;


CREATE FUNCTION _autonomous_cancel_job(p_job_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    p_pid INTEGER;
BEGIN
    SELECT pid FROM job_logs WHERE job_id = p_job_id INTO p_pid;
    SELECT pg_cancel_backend(p_pid);
    SELECT _autonomous_fail_job(p_job_id);    
END
$$;


CREATE FUNCTION _autonomous_close_job(p_job_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_numrows integer;
BEGIN    
    UPDATE job_log SET
        end_time = current_timestamp,
        status = 'OK'
    WHERE job_id = p_job_id;
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    RETURN v_numrows;
END
$$;


CREATE FUNCTION close_job(p_job_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remote_query TEXT;
BEGIN
    v_remote_query := 'SELECT _autonomous_close_job('||p_job_id||')'; 

    EXECUTE 'SELECT devnull FROM dblink.dblink(''dbname=' || current_database() ||
        ''',' || quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  
END
$$;


CREATE FUNCTION _autonomous_fail_job(p_job_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_numrows integer;
BEGIN
    UPDATE job_log SET
        end_time = current_timestamp,
        status = 'BAD'
    WHERE job_id = p_job_id;
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    RETURN v_numrows;
END
$$;


CREATE FUNCTION fail_job(p_job_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remote_query TEXT;
BEGIN
    v_remote_query := 'SELECT _autonomous_fail_job('||p_job_id||')'; 

    EXECUTE 'SELECT devnull FROM dblink.dblink(''dbname=' || current_database() ||
        ''',' || quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  

END
$$;


CREATE FUNCTION _autonomous_upd_step(p_job_id integer, p_step_id integer, p_status text, p_message text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_numrows integer;
BEGIN
    UPDATE job_detail SET 
        end_time = current_timestamp,
        elapsed_time = date_part('epoch',now() - start_time)::integer,
        status = p_status,
        message = p_message
    WHERE job_id = p_job_id AND step_id = p_step_id; 
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    RETURN v_numrows;
END
$$;


CREATE FUNCTION upd_step(p_job_id integer, p_step_id integer, p_status text, p_message text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remote_query TEXT;
BEGIN
    v_remote_query := 'SELECT _autonomous_upd_step ('||
    p_job_id || ',' ||
    p_step_id || ',' ||
    quote_literal(p_status) || ',' ||
    quote_literal(p_message) || ')';

    EXECUTE 'SELECT devnull FROM dblink.dblink(''dbname=' || current_database() ||
        ''','|| quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  
END
$$;


CREATE FUNCTION job_monitor() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.status = 'OK' THEN
        DELETE FROM job_check WHERE job_name = NEW.job_name;
    ELSIF NEW.status = 'BAD' THEN
        INSERT INTO job_check (job_id, job_name) VALUES (NEW.job_id, NEW.job_name);
    ELSE
        -- Do nothing
    END IF;

    return null;
END
$$;


-- v_history is how far into job_log's past the check will go. Don't go further back than your longest job's interval to keep check efficient
CREATE FUNCTION check_job_status(v_history interval) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
    v_jobs RECORD;
    v_job_errors RECORD;
    v_count int = 1;
    v_trouble text[];
    v_bad TEXT := 'BAD(';
    v_warn TEXT := 'WARNING(';
begin

    -- Generic check for jobs without special monitoring. Should error on 3 failures
    FOR v_job_errors IN SELECT l.job_name FROM check_job_log l 
        WHERE l.job_name NOT IN (select c.job_name from job_check_config c where l.job_name <> c.job_name) GROUP BY l.job_name HAVING count(*) > 2
    LOOP
        v_trouble[v_count] := v_job_errors.job_name;
        v_count := v_count+1;
    END LOOP;
    
    IF array_upper(v_trouble,1) > 0 THEN
        v_bad := v_bad || 'Jobs w/ 3 consecutive errors: '||array_to_string(v_trouble,', ')||'; ';
    END IF;
    
    -- Jobs with special monitoring (threshold different than 3 errors, must run within a timeframe, etc)
    for v_jobs in 
                select
                    job_name,
                    status, 
                    current_timestamp,
                    current_timestamp - timestamp as last_run_time,  
                    case
                        when (select count(*) from job_check where job_name = job_check_config.job_name) > sensitivity then 'ERROR'  
                        when timestamp < (current_timestamp - error_threshold) then 'ERROR' 
                        when timestamp < (current_timestamp - warn_threshold) then 'WARNING'
                        else 'OK'
                    end as nagios_code,
                    case
                        when status = 'BAD' then 'BAD' 
                        when status is null then 'MISSING' 
                        when (timestamp < current_timestamp - error_threshold) OR (timestamp < current_timestamp - warn_threshold) then 
                            case 
                                when status = 'OK' then 'MISSING'
                                else status
                            end
                    end as job_status
                from
                    job_check_config 
                    left join (
                                select
                                    job_name,
                                    max(timestamp) as timestamp 
                                from
                                    job_log
                                where
                                    timestamp > now() - v_history
                                group by 
                                    job_name 
                                ) last_job using (job_name)
                    left join (
                                select 
                                    job_name,    
                                    timestamp, 
                                    coalesce(status,
                                    (select case when (select count(*) from pg_locks where not granted and pid = m.pid) > 0 THEN 'BLOCKED' ELSE NULL END),
                                    (select case when (select count(*) from pg_stat_activity where procpid = m.pid) > 0 THEN 'RUNNING' ELSE NULL END),
                                    'FOOBAR') as status
                                from
                                    job_log m 
                                where 
                                    timestamp > now() - v_history
                                ) lj_status using (job_name,timestamp)   
                 where active      
loop

    if v_jobs.nagios_code = 'ERROR' then
        v_bad := v_bad || v_jobs.job_name || ': ' || coalesce(v_jobs.job_status,'null??') || '; ';
    end if;

    if v_jobs.nagios_code = 'WARNING' then
        v_warn := v_warn || v_jobs.job_name || ': Last run ' || coalesce(v_jobs.job_status,'null??') || '; ';
    end if;
    
    if v_jobs.job_status = 'MISSING' AND v_jobs.last_run_time IS NULL then
        v_bad := v_bad || v_jobs.job_name || ': MISSING - Last run over ' || v_history || ' hrs ago. Check job_log for more details;';
    end if;

end loop;

if v_bad <> 'BAD(' then
    v_bad := v_bad || ')'; 
    return v_bad;
end if;

if v_warn <> 'WARNING(' then
    v_warn := v_warn || ')';
    return v_warn;
end if; 

return 'OK(Current job reports looks acceptable)';

end
$$;
