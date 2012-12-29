pg_jobmon
=========

LOGGING
-------

*add_job(p_job_name text) RETURNS bigint*  
    Create a new entry in the job_log table. p_job_name is automatically capitalized.   
    Returns the job_id of the new job.  

*add_step(p_job_id bigint, p_action text) RETURNS bigint*  
    Add a new step in the job_detail table to an existing job. Pass it the job_id  
    created by add_job() and a description of the step.  
    Returns the step_id of the new step.

*update_step(p_step_id bigint, p_status text, p_message text) RETURNS void*  
    Update the status of the step_id passed to it.  
    p_message is for further information on the status of the step.  

*sql_step(p_job_id bigint, p_action text, p_sql text) RETURNS boolean*  
    Logs a full step for a given sql query. Logs the number of rows affected. Simple function for when you don't need to log extensive details of a single query.  
    p_job_id is the job id to log this step with.  
    p_action is for the action column in job_detail.  
    p_sql is the full sql query to be run
    Returns true/false so you can check how the step ran and continue handling the rest of your job appropriately.
    
*close_job(p_job_id bigint) RETURNS void*  
    Used to successfully close the given job_id.   
    
*fail_job(p_job_id bigint, p_fail_level int DEFAULT 3) RETURNS void*  
    Used to unsuccessfully close the given job_id.  
    Will default to failing with a level 3 alert in the log. Optional second argument allows you to fail a job with a different error level   
    (Ex. close job w/ level 2 (WARNING) to avoid a critical page but still notify that something's wrong).
    
*cancel_job(v_job_id bigint) RETURNS boolean*  
    Used to unsuccessfully terminate the given job_id from outside the running job.  
    Calls pg_cancel_backend() on the pid stored for the job in job_log.  
    Sets the final step to note that it was manually cancelled in the job_detail table.  

*sql_job(p_job_name text, p_sql text) RETURNS text*  
    Log a complete job for a given query. Records the number of rows affected. Also ensures that the job cannot run concurrently with itself.  
    p_job_name is the job name that will be recorded in job_log.  
    p_sql is the full sql query to be run.  
    Returns the job id that was created for this job and whether the job was successful.

*job_log_clear(p_interval interval) RETURNS void*  
    Deletes all jobs in job_log and job_detail tables older than the given interval.
    Also logs this task as another job itself.

The below functions all return full rows of the format for the given SETOF table, which means you can treat them as tables as far as filtering the result. For all functions that have a default integer parameter at the end, this signifies a default limit on the number of rows returned. You can change this as desired, or just leave out that parameter to get the default limit.  
All show functions also automatically uppercase the job name parameter to be consistent with the add_job function.

*show_job(p_name text, int default 10) RETURNS SETOF job_log*  
    Return all jobs from job_log that match the given job name. Automatically sorts to get the most recent jobs first, so by default gets the first 10 matching jobs

*show_job_like(p_name text, int default 10) RETURNS SETOF job_log*  
    Return all jobs from job_log that contain the given text somewhere in the job name (does a ~ match). Automatically sorts to get the most recent jobs first, so by default gets the first 10 matching jobs

*show_job_status(p_status text, int default 10) RETURNS SETOF job_log*  
    Return all jobs from job_log matching the given status. Automatically sorts to get the most recent jobs first, so by default gets the first 10 matching jobs

*show_job_status(p_name text, p_status text, int default 10) RETURNS SETOF job_log*  
    Return all jobs from job_log that match both the given job name and given status. Automatically sorts to get the most recent jobs first, so by default gets the first 10 matching jobs

*show_detail(p_id bigint) RETURNS SETOF job_detail*  
    Return the full log from job_detail for the given job id. 

*show_detail(p_name text, int default 1) RETURNS SETOF job_detail*  
    Return the full log from job_detail matching the given job name. By default returns only the most recent job details.  
    Given a higher limit, it will return all individual job details in descending job id order.

*show_running(int default 10) RETURNS SETOF job_log*  
    Returns data from job_log for any currently running jobs that use pg_jobmon.
    

**Log Tables:**  

**IMPORTANT NOTE**  
The job_log and job_detail table data WILL NOT be exported by a pg_dump. The extension system still has some issues to be worked out, one of them being that if you do a full database dump specifying --schema-only, any extension table data that has been set to be dumped will be (see catalog.pg_extension_config_dump() function). As you can imagine, over time these two tables can get quite large and that could cause a schema dump of the database to be needlessly large. Until that is fixed, these tables have had their dump setting specifically left off. If you need to dump these tables' data, please DROP the table from the extension, do your dump, then ADD the table back (http://www.postgresql.org/docs/9.1/static/sql-alterextension.html). The other tables have minimal, and more critical data, so their data has been set to be dumped.

*job_log*  
    Logs the overall job details associated with a job_id. Recommended to make partitioned on start_time if you see high logging traffic or don't 
    need to keep the data indefinitely  
   
*job_detail*
    Logs the detailed steps of each job_id associated with jobs in job_log. Recommended to make partitioned on start_time if you see high logging traffic 
    or don't need to keep the data indefinitely  

*dblink_mapping*
    Configuration table for storing dblink connection info. Allows non-superusers to use this extension and changing the port of the cluster running pg_jobmon.  
    

MONITORING
----------
*check_job_status(OUT alert_code integer, OUT alert_text text)*  
Function to run to see if any jobs have failed. No argument needs to be passed and it will automatically use the longest configured threshold interval from the job_check_config table as the period of time to check for bad jobs (see below). If nothing is configured in that table, it just checks for 3 consecutive job failures.

The alert_code output indicates one of the following 3 statuses:  
* Return code 1 means a successful job run  
* Return code 2 is for use with jobs that support a warning indicator. 
    Not critical, but someone should look into it
* Return code 3 is for use with a critical job failure 

This monitoring function was originally created with nagios in mind, hence these text alert values. By default, the job_status_text table contains the following:  
 
    1 = OK
    2 = WARNING
    3 = CRITICAL

If you'd like different status text values, just update the job_status_text table with the error_text values you'd like. DO NOT change the error_code values, though!

The alert_text output is a more detailed message indicating what the actual jobs that failed were.

An example query and output is:

    select t.error_text || c.alert_text as alert_status from jobmon.check_job_status() c 
        join jobmon.job_status_text t on c.alert_code = t.error_code;

            alert_status          
    -------------------------------
    OK(All jobs run successfully)


**Monitoring Tables:**

*job_check_config*  
Table of jobs that require special job monitoring other than 3 consecutive failures (this is done by default).
 * job_name - This is the EXACT job name as it appears in the job_log table. It is case sensitive, so jobs entered here should be in all caps. Easiest thing to do is just copy the job name right from the job_log table.
 * warn_threshold - This is the interval of time that can pass without the job running before alert_code 2 is returned by check_job_status()
 * error_threshold - This is the interval of time that can pass without the job running before alert_code 3 is returned by check_job_status()
 * active - Set this to TRUE if you want check_job_status() to actively monitor this job. Set to FALSE to disable checking without removing the data from the config table
 * sensitivity - This is the number of times the job can fail (status column in job_log is the text value of alert_code 3, CRITICAL by default) before alert_code 3 is returned by check_job_status(). Note that if you want this to return immediately on the first failure, set it to zero, not one.

*job_check_log*  
This table is used to record the job_id, job_name & alert_code automatically whenever the status column of job_log contains the text value for alert levels 2 or 3. You should hopefully never have to insert or delete from this table manually. A trigger on job_log handles this. However, if a job fails and can never be run successfully again, you may have to manually clean the table to clear out the bad job from returning in check_job_status(). It's recommended NOT to truncate to clean it up as you could inadvertently delete a job that had just failed. It's best to delete the job number specifically or delete all jobs <= a specific job_id.

*job_status_text*  
Table containing the text values for the alert levels. Defaults are listed above. Change the alert_text column for each code to have custom statuses used for the status column in job_log. 
