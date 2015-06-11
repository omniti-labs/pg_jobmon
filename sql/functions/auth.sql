/*
 *  dblink Authentication mapping
 */
CREATE FUNCTION auth() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
 
    v_auth          text = '';
    v_port          text;
    v_password      text; 
    v_username      text;
 
BEGIN
    -- Ensure only one row is returned. No rows is fine, but this was the only way to force one.
    -- Trigger on table should enforce it as well, but extra check doesn't hurt.
    BEGIN
        SELECT username, port, pwd INTO STRICT v_username, v_port, v_password FROM @extschema@.dblink_mapping_jobmon;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Do nothing
        WHEN TOO_MANY_ROWS THEN
            RAISE EXCEPTION 'dblink_mapping_jobmon table can only have a single entry';
    END;
            

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


