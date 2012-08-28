/*
 *  dblink Authentication mapping
 */
CREATE FUNCTION auth() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_username  text;
    v_password  text;
    v_auth      text;
BEGIN
    SELECT username, pwd INTO v_username, v_password FROM @extschema@.dblink_mapping;
    IF v_username IS NULL THEN
        RETURN '';
    END IF;

    v_auth := 'user='||v_username;
    IF v_password IS NOT NULL THEN
        v_auth := v_auth || ' password='||v_password;
    END IF;
    v_auth := v_auth || ' ';
    RETURN v_auth;    
END
$$;
