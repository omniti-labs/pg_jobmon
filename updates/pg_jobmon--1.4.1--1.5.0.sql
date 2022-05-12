-- Added new configuration column to support host/service names allowing for dynamic ip addresses to be used.


ALTER TABLE @extschema@.dblink_mapping_jobmon ADD COLUMN hostaddr text;

UPDATE @extschema@.dblink_mapping_jobmon SET hostaddr = host,  host = NULL;
