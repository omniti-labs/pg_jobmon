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
