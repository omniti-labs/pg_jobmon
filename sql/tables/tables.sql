-- ########## pg_jobmon extension table definitions ##########
-- Recommended to make job_log and job_detail tables partitioned on start_time 
--  if you see high logging traffic or don't need to keep the data indefinitely
CREATE TABLE job_log (
    job_id bigint NOT NULL,
    owner text NOT NULL,
    job_name text NOT NULL,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone,
    status text,
    pid integer NOT NULL,
    CONSTRAINT job_log_job_id_pkey PRIMARY KEY (job_id)
);
CREATE INDEX job_log_job_name_idx ON job_log (job_name);
CREATE INDEX job_log_start_time_idx ON job_log (start_time);
CREATE INDEX job_log_status_idx ON job_log (status);
CREATE INDEX job_log_pid_idx ON job_log (pid);
CREATE SEQUENCE job_log_job_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE job_log_job_id_seq OWNED BY job_log.job_id;
ALTER TABLE job_log ALTER COLUMN job_id SET DEFAULT nextval('job_log_job_id_seq'::regclass);


CREATE TABLE job_detail (
    job_id bigint NOT NULL,
    step_id bigint NOT NULL,
    action text NOT NULL,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone,
    elapsed_time real,
    status text,
    message text,
    CONSTRAINT job_detail_step_id_pkey PRIMARY KEY (step_id),
    CONSTRAINT job_detail_job_id_fkey FOREIGN KEY (job_id) REFERENCES job_log(job_id) ON DELETE CASCADE
);
CREATE INDEX job_detail_job_id_idx ON job_detail (job_id);
CREATE SEQUENCE job_detail_step_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE job_detail_step_id_seq OWNED BY job_detail.step_id;
ALTER TABLE job_detail ALTER COLUMN step_id SET DEFAULT nextval('job_detail_step_id_seq'::regclass);


CREATE TABLE job_check_log (
    job_id bigint NOT NULL,
    job_name text NOT NULL,
    alert_code int DEFAULT 3 NOT NULL
);
SELECT pg_catalog.pg_extension_config_dump('job_check_log', '');


CREATE TABLE dblink_mapping_jobmon (
    username text,
    port text,
    pwd text,
    host text
);
SELECT pg_catalog.pg_extension_config_dump('dblink_mapping_jobmon', '');

CREATE FUNCTION dblink_limit_trig() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
v_count     smallint;
BEGIN

    EXECUTE 'SELECT count(*) FROM '|| TG_TABLE_SCHEMA ||'.'|| TG_TABLE_NAME INTO v_count;
    IF v_count > 1 THEN
        RAISE EXCEPTION 'Only a single row may exist in this table';
    END IF;

    RETURN NULL;
END
$$;

CREATE TRIGGER dblink_limit_trig AFTER INSERT ON @extschema@.dblink_mapping_jobmon
FOR EACH ROW
EXECUTE PROCEDURE @extschema@.dblink_limit_trig();


CREATE TABLE job_check_config (
    job_name text NOT NULL,
    warn_threshold interval NOT NULL,
    error_threshold interval NOT NULL,
    active boolean DEFAULT false NOT NULL,
    sensitivity smallint DEFAULT 0 NOT NULL,
    escalate int,
    CONSTRAINT job_check_config_job_name_pkey PRIMARY KEY (job_name)
);
SELECT pg_catalog.pg_extension_config_dump('job_check_config', '');


CREATE TABLE job_status_text (
    alert_code  integer NOT NULL,
    alert_text  text NOT NULL,
    CONSTRAINT job_status_text_alert_code_pkey PRIMARY KEY (alert_code)
);
SELECT pg_catalog.pg_extension_config_dump('job_status_text', 'WHERE alert_code NOT IN (1,2,3)');
INSERT INTO job_status_text (alert_code, alert_text) VALUES (1, 'OK');
INSERT INTO job_status_text (alert_code, alert_text) VALUES (2, 'WARNING');
INSERT INTO job_status_text (alert_code, alert_text) VALUES (3, 'CRITICAL');
