pg_jobmon
=========

pg_jobmon is an extension to add the capability to log the progress of running functions and provide a limited monitoring capability to those logged functions. 
The logging is done in a NON-TRANSACTIONAL method, so that if your function fails for any reason, all steps up to that point are kept in the log tables. The logging portions of the extension should be stable and ready for production use. The monitoring capability is still fairly new and may require adjusting but it should be usable.
A blog post giving more extensive examples can be found at http://keithf4.com (coming soon)

INSTALLATION
------------

Requirements: dblink extension
Copy the pg_jobmon.control and pg_jobmon--<version>.sql files to your $BASEDIR/share/extension folder. Create schema (not required but recommended) and then install using the PostgreSQL extensions system

    CREATE SCHEMA jobmon;
    CREATE EXTENSION pg_jobmon SCHEMA jobmon;


UPGRADE
-------

Make sure all the upgrade scripts for the version you have installed up to the most recent version are in the $BASEDIR/share/extension folder. 

    ALTER EXTENSION pg_jobmon UPDATE TO '<latest version>';

Please note that until this extension is officially announced and put into the OmniTI github repository, there may not be upgrade scripts available.

LOGGING
-------

By default, the status column updates will use the text values from the job_alert_nagios table in the monitoring section. If you
have a custom set of statuses that you'd like to use, the close, fail or cancel functions that take a custom table name. 

add_job(p_job_name text) RETURNS bigint
    Create a new entry in the job_log table. p_job_name is automatically capitalized. 
    Returns the job_id of the new job.

add_step(p_job_id bigint, p_action text) RETURNS bigint
    Add a new step in the job_detail table to an existing job. Pass it the job_id
    created by add_job() and a description of the step. 
    Returns the step_id of the new step.

update_step(p_job_id bigint, p_step_id bigint, p_status text, p_message text) RETURNS void
    Update the status of the job_id and step_id passed to it. 
    p_message is for further information on the status of the step.

close_job(p_job_id bigint) RETURNS void
    Used to successfully close the given job_id. 
    Defaults to using job_alert_nagios table status text.
    
close_job(p_job_id bigint, p_config_table text) RETURNS void
    Same as above for successfully closing a job but allows you to use custom status 
    text that you set up in another table. See MONITORING section for more info.

fail_job(p_job_id bigint) RETURNS void
    Used to unsuccessfully close the given job_id.
    Defaults to using job_alert_nagios table status text. 
    
fail_job(p_job_id bigint, p_config_table text) RETURNS void
    Same as above for unsuccessfully closing a job but allows you to use custom status 
    text that you set up in another table. See MONITORING section for more info.

cancel_job(v_job_id bigint) RETURNS boolean
    Used to unsuccessfully terminate the given job_id from outside the running job. 
    Calls pg_cancel_backend() on the pid stored for the job in job_log.
    Sets the final step to note that it was manually cancelled in the job_detail table.
    Defaults to using job_alert_nagios table status text. 
    
cancel_job(v_job_id bigint, p_config_table text) RETURNS boolean
    Same as above for unsuccessfully, manually cancelling a job but allows you to use custom 
    status text that you set up in another table. See MONITORING section for more info.

Log Tables:
job_log
    Logs the overall job details associated with a job_id. Recommended to make
    partitioned on start_time if you see high logging traffic or don't 
    need to keep the data indefinitely 
    
job_detail
    Logs the detailed steps of each job_id associated with jobs in job_log. 
    Recommended to make partitioned on start_time if you see high logging traffic 
    or don't need to keep the data indefinitely 
    

MONITORING
----------

check_job_status(p_history interval, OUT alert_code integer, OUT alert_text text)

The above function takes as a parameter the interval of time that you'd like to go backwards to check for bad jobs. It's recommended not to look back any further than the longest interval that a single job runs to help the check run efficiently. For example, if the longest interval between any job is a week, then pass '1 week'.

The alert_code output indicates one of the following 3 statuses:
-- Return code 1 means a successful job run
-- Return code 2 is for use with jobs that support a warning indicator. 
    Not critical, but someone should look into it
-- Return code 3 is for use with a critical job failure 

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


Monitoring Tables:
job_check_config
job_check_log
job_alert_nagios


AUTHOR
------

Keith Fiske
OmniTI, Inc - http://www.omniti.com
keith@omniti.com


LICENSE AND COPYRIGHT
---------------------

PGExtractor is released under the PostgreSQL License, a liberal Open Source license, similar to the BSD or MIT licenses.

Copyright (c) 2012 OmniTI, Inc.

Permission to use, copy, modify, and distribute this software and its documentation for any purpose, without fee, and without a written agreement is hereby granted, provided that the above copyright notice and this paragraph and the following two paragraphs appear in all copies.

IN NO EVENT SHALL THE AUTHOR BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE AUTHOR HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

THE AUTHOR SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS ON AN "AS IS" BASIS, AND THE AUTHOR HAS NO OBLIGATIONS TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
