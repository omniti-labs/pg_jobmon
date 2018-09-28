-- Add host column to dblink map table to allow logging to alternative hosts

ALTER TABLE @extschema@.dblink_mapping_jobmon ADD COLUMN host text; 


