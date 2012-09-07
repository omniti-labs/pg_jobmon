-- Added port column to dblink_mapping table to allow changing the default port.

ALTER TABLE @extschema@.dblink_mapping ADD COLUMN port text;
ALTER TABLE @extschema@.dblink_mapping ALTER COLUMN username DROP NOT NULL;

/*
 *  dblink Authentication mapping
 */
CREATE OR REPLACE FUNCTION auth() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
 
    v_auth          text = '';
    v_port          text;
    v_password      text; 
    v_username      text;
 
BEGIN
    SELECT username, port, pwd INTO v_username, v_port, v_password FROM @extschema@.dblink_mapping;

    IF v_port IS NULL THEN
        v_auth = 'dbname=' || current_database();
    ELSE
        v_auth := 'port='||v_port||' dbname=' || current_database();
    END IF;

    IF v_username IS NOT NULL THEN
        v_auth := v_auth || ' user='||v_username;
    END IF;

    IF v_password IS NOT NULL THEN
        v_auth := v_auth || ' password='||v_password;
    END IF;
    RETURN v_auth;    
END
$$;


/*
 *  Add Job
 */
CREATE OR REPLACE FUNCTION add_job(p_job_name text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE 
    v_job_id bigint;
    v_remote_query text;
    v_dblink_schema text;
BEGIN
    SELECT nspname INTO v_dblink_schema FROM pg_namespace n, pg_extension e WHERE e.extname = 'dblink' AND e.extnamespace = n.oid;
    
    v_remote_query := 'SELECT @extschema@._autonomous_add_job (' ||
        quote_literal(current_user) || ',' ||
        quote_literal(p_job_name) || ',' ||
        pg_backend_pid() || ')';

    EXECUTE 'SELECT job_id FROM ' || v_dblink_schema || '.dblink('||quote_literal(@extschema@.auth())||
        ','|| quote_literal(v_remote_query) || ',TRUE) t (job_id int)' INTO v_job_id;      

    IF v_job_id IS NULL THEN
        RAISE EXCEPTION 'Job creation failed';
    END IF;

    RETURN v_job_id;
END
$$;


/*
 *  Add Step
 */
CREATE OR REPLACE FUNCTION add_step(p_job_id bigint, p_action text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE 
    v_step_id bigint;
    v_remote_query text;
    v_dblink_schema text;
    
BEGIN

    SELECT nspname INTO v_dblink_schema FROM pg_namespace n, pg_extension e WHERE e.extname = 'dblink' AND e.extnamespace = n.oid;
    
    v_remote_query := 'SELECT @extschema@._autonomous_add_step (' ||
        p_job_id || ',' ||
        quote_literal(p_action) || ')';

    EXECUTE 'SELECT step_id FROM ' || v_dblink_schema || '.dblink('||quote_literal(@extschema@.auth())||
        ','|| quote_literal(v_remote_query) || ',TRUE) t (step_id int)' INTO v_step_id;      

    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'Job creation failed';
    END IF;

    RETURN v_step_id;
END
$$;


/*
 *  Close Job
 */
CREATE OR REPLACE FUNCTION close_job(p_job_id bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remote_query text;
    v_dblink_schema text;
BEGIN

    SELECT nspname INTO v_dblink_schema FROM pg_namespace n, pg_extension e WHERE e.extname = 'dblink' AND e.extnamespace = n.oid;
    
    v_remote_query := 'SELECT @extschema@._autonomous_close_job('||p_job_id||')'; 

    EXECUTE 'SELECT devnull FROM ' || v_dblink_schema || '.dblink('||quote_literal(@extschema@.auth())||
        ',' || quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  
END
$$;


/*
 *  Fail Job
 */
CREATE OR REPLACE FUNCTION fail_job(p_job_id bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remote_query text;
    v_dblink_schema text;
BEGIN
    
    SELECT nspname INTO v_dblink_schema FROM pg_namespace n, pg_extension e WHERE e.extname = 'dblink' AND e.extnamespace = n.oid;
    
    v_remote_query := 'SELECT @extschema@._autonomous_fail_job('||p_job_id||')'; 

    EXECUTE 'SELECT devnull FROM ' || v_dblink_schema || '.dblink('||quote_literal(@extschema@.auth())||
        ',' || quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  

END
$$;


/*
 *  Update Step
 */
CREATE OR REPLACE FUNCTION update_step(p_step_id bigint, p_status text, p_message text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_remote_query text;
    v_dblink_schema text;
BEGIN
    SELECT nspname INTO v_dblink_schema FROM pg_namespace n, pg_extension e WHERE e.extname = 'dblink' AND e.extnamespace = n.oid;
    
    v_remote_query := 'SELECT @extschema@._autonomous_update_step ('||
    p_step_id || ',' ||
    quote_literal(p_status) || ',' ||
    quote_literal(p_message) || ')';

    EXECUTE 'SELECT devnull FROM ' || v_dblink_schema || '.dblink('||quote_literal(@extschema@.auth())||
        ','|| quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  
END
$$;
