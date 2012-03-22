SET search_path = jobmon, pg_catalog;

-- v_history is how far into job_log's past the check will go. Don't go further back than your longest job's interval to keep check efficient
CREATE FUNCTION check_job_status(v_history interval) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
    v_jobs RECORD;
    v_job_errors RECORD;
    v_count int = 1;
    v_trouble text[];
    v_bad TEXT := 'BAD(';
    v_warn TEXT := 'WARNING(';
begin

    -- Generic check for jobs without special monitoring. Should error on 3 failures
    FOR v_job_errors IN SELECT l.job_name FROM check_job_log l 
        WHERE l.job_name NOT IN (select c.job_name from job_check_config c where l.job_name <> c.job_name) GROUP BY l.job_name HAVING count(*) > 2
    LOOP
        v_trouble[v_count] := v_job_errors.job_name;
        v_count := v_count+1;
    END LOOP;
    
    IF array_upper(v_trouble,1) > 0 THEN
        v_bad := v_bad || 'Jobs w/ 3 consecutive errors: '||array_to_string(v_trouble,', ')||'; ';
    END IF;
    
    -- Jobs with special monitoring (threshold different than 3 errors, must run within a timeframe, etc)
    for v_jobs in 
                select
                    job_name,
                    status, 
                    current_timestamp,
                    current_timestamp - timestamp as last_run_time,  
                    case
                        when (select count(*) from job_check where job_name = job_check_config.job_name) > sensitivity then 'ERROR'  
                        when timestamp < (current_timestamp - error_threshold) then 'ERROR' 
                        when timestamp < (current_timestamp - warn_threshold) then 'WARNING'
                        else 'OK'
                    end as nagios_code,
                    case
                        when status = 'BAD' then 'BAD' 
                        when status is null then 'MISSING' 
                        when (timestamp < current_timestamp - error_threshold) OR (timestamp < current_timestamp - warn_threshold) then 
                            case 
                                when status = 'OK' then 'MISSING'
                                else status
                            end
                    end as job_status
                from
                    job_check_config 
                    left join (
                                select
                                    job_name,
                                    max(timestamp) as timestamp 
                                from
                                    job_log
                                where
                                    timestamp > now() - v_history
                                group by 
                                    job_name 
                                ) last_job using (job_name)
                    left join (
                                select 
                                    job_name,    
                                    timestamp, 
                                    coalesce(status,
                                    (select case when (select count(*) from pg_locks where not granted and pid = m.pid) > 0 THEN 'BLOCKED' ELSE NULL END),
                                    (select case when (select count(*) from pg_stat_activity where procpid = m.pid) > 0 THEN 'RUNNING' ELSE NULL END),
                                    'FOOBAR') as status
                                from
                                    job_log m 
                                where 
                                    timestamp > now() - v_history
                                ) lj_status using (job_name,timestamp)   
                 where active      
loop

    if v_jobs.nagios_code = 'ERROR' then
        v_bad := v_bad || v_jobs.job_name || ': ' || coalesce(v_jobs.job_status,'null??') || '; ';
    end if;

    if v_jobs.nagios_code = 'WARNING' then
        v_warn := v_warn || v_jobs.job_name || ': Last run ' || coalesce(v_jobs.job_status,'null??') || '; ';
    end if;
    
    if v_jobs.job_status = 'MISSING' AND v_jobs.last_run_time IS NULL then
        v_bad := v_bad || v_jobs.job_name || ': MISSING - Last run over ' || v_history || ' hrs ago. Check job_log for more details;';
    end if;

end loop;

if v_bad <> 'BAD(' then
    v_bad := v_bad || ')'; 
    return v_bad;
end if;

if v_warn <> 'WARNING(' then
    v_warn := v_warn || ')';
    return v_warn;
end if; 

return 'OK(Current job reports looks acceptable)';

end
$$;

