SET search_path = jobmon, pg_catalog;

-- See about making these into partitioned tables by start_time

-- Add trigger to populate check_jobs table when job fails
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
CREATE TRIGGER manage_check_jobs AFTER UPDATE ON job_masters FOR EACH ROW EXECUTE PROCEDURE jobmon.manage_check_jobs();


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
ALTER TABLE job_detail ADD CONSTRAINT job_detail_job_id_fkey FOREIGN KEY (job_id) REFERENCES job_log(job_id);
CREATE SEQUENCE job_detail_step_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE job_detail_step_id_seq OWNED BY job_detail.step_id;
ALTER TABLE job_detail ALTER COLUMN step_id SET DEFAULT nextval('job_detail_step_id_seq'::regclass);


CREATE TABLE job_check (
    job_id integer NOT NULL,
    job_name text NOT NULL
);

CREATE TABLE job_status (
    job_name text NOT NULL,
    warn_threshold interval NOT NULL,
    error_threshold interval NOT NULL,
    active boolean DEFAULT false NOT NULL,
--    escalate text DEFAULT 'email'::text NOT NULL,
    sensitivity smallint DEFAULT 0 NOT NULL,
    PRIMARY KEY (job_name)
);





