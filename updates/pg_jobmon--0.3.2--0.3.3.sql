-- Turn off the dump of table data for the log tables. pg_dump isn't handling this properly and will dump all the data out for these tables even in a --schema-only dump.
-- Data for other tables is minimal, and more critical, so not removing their dump settings.
-- Data for these tables can be dumped if it's needed by temporarily removing the table from the extention and then adding it back.

-- This is commented out because doing this in an extension update doesn't actually do anything. You MUST run this command manually to stop pg_dump from dumping out table data if it is causing you any problems. 
-- It's still required to run this script, or at least have it in your extensions folder for future updates, so that your pg_jobmon version is up to date and you can install future versions.
/*
UPDATE pg_extension SET extconfig = (SELECT array_agg(t.oid) FROM (
	SELECT unnest(extconfig) AS oid, split_part(unnest(extconfig)::regclass::text, '.', 2) AS tablename 
	FROM pg_extension WHERE extname = 'pg_jobmon') t
WHERE t.tablename NOT IN ('job_log', 'job_detail') ) WHERE extname = 'pg_jobmon';
*/
