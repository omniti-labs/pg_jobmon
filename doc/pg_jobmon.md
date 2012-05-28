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

*update_step(p_job_id bigint, p_step_id bigint, p_status text, p_message text) RETURNS void*  
    Update the status of the job_id and step_id passed to it.  
    p_message is for further information on the status of the step.  
    
*close_job(p_job_id bigint, text default 'job_alert_nagios') RETURNS void*  
    Used to successfully close the given job_id.  
    Defaults to using job_alert_nagios table status text. You can feed it another table name
    that allows you to use custom status text that you set up in another table.  
    See MONITORING section for more info.  
    
*fail_job(p_job_id bigint, p_config_table text) RETURNS void*  
    Used to unsuccessfully close the given job_id.  
    Defaults to using job_alert_nagios table status text. You can feed it another table name
    that allows you to use custom status text that you set up in another table.  
    See MONITORING section for more info.  
    
*cancel_job(v_job_id bigint, p_config_table text) RETURNS boolean*
    Used to unsuccessfully terminate the given job_id from outside the running job.  
    Calls pg_cancel_backend() on the pid stored for the job in job_log.  
    Sets the final step to note that it was manually cancelled in the job_detail table.  
    Defaults to using job_alert_nagios table status text. You can feed it another table name
    that allows you to use custom status text that you set up in another table.  
    See MONITORING section for more info.

The below functions all return full rows of the format for the given SETOF table, which means you can treat them as tables as far as filtering the result. For all functions that have a default integer parameter at the end, this signifies a default limit on the number of rows returned. You can change this as desired, or just leave out that parameter to get the default limit.
All show functions also automatically uppercase all parameters to be consistent with above logging functions.

*show_job(p_name text, int default 10) RETURNS SETOF job_log*  
    Return all jobs from job_log that match the given job name. 

*show_job_like(p_name text, int default 10) RETURNS SETOF job_log*  
    Return all jobs from job_log that contain the given text somewhere in the job name (does a ~ match).

*show_job_status(p_status text, int default 10) RETURNS SETOF job_log*  
    Return all jobs from job_log matching the given status.

*show_job_status(p_name text, p_status text, int default 10) RETURNS SETOF @extschema@.job_log*  
    Return all jobs from job_log that match both the given job name and given status.

*show_detail(p_id bigint) RETURNS SETOF @extschema@.job_detail*  
    Return the full log from job_detail for the given job id.

*show_detail(p_name text, int default 1) RETURNS SETOF @extschema@.job_detail*  
    Return the full log from job_detail matching the given job name. By default returns only the most recent job details.  
    Given a higher limit, it will return all individual job details in descending job id order.

*show_running(int default 10) RETURNS SETOF @extschema@.job_log*  
    Returns the details from job_log for any currently running jobs that use pg_jobmon.
    

**Log Tables:**  

*job_log*  
    Logs the overall job details associated with a job_id. Recommended to make partitioned on start_time if you see high logging traffic or don't 
    need to keep the data indefinitely  
   
*job_detail*
    Logs the detailed steps of each job_id associated with jobs in job_log. Recommended to make partitioned on start_time if you see high logging traffic 
    or don't need to keep the data indefinitely 
    

MONITORING
----------

*check_job_status(p_history interval, OUT alert_code integer, OUT alert_text text)*  
The above function takes as a parameter the interval of time that you'd like to go backwards to check for bad jobs. It's recommended not to look back any further than the longest interval that a single job runs to help the check run efficiently. For example, if the longest interval between any job is a week, then pass '1 week'.

The alert_code output indicates one of the following 3 statuses:  
* Return code 1 means a successful job run  
* Return code 2 is for use with jobs that support a warning indicator. 
    Not critical, but someone should look into it
* Return code 3 is for use with a critical job failure 

This monitoring function was originally created with nagios in mind. By default, all logging functions use the job_alert_nagios table to associate  
 
    1 = OK
    2 = WARNING
    3 = CRITICAL

If you'd like these alert codes to be associated with other error text, you can create another table and join against it associating the code with whichever text you'd like. Alternate logging functions are available to make sure your logs get these custom statuses as well.
See LOGGING section.

The alert_text output is a more detailed message indicating what the actual jobs that failed were.

An example query and output is:

    select r.error_text || c.alert_text as alert_status from jobmon.check_job_status('3 days') c 
        join jobmon.job_alert_nagios r on c.alert_code = r.error_code;

            alert_status          
    -------------------------------
    OK(All jobs run successfully)


**Monitoring Tables:**

*job_check_config*  
*job_check_log*  
*job_alert_nagios*
