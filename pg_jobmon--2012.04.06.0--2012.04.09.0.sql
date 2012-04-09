CREATE OR REPLACE FUNCTION check_job_status(v_history interval, OUT alert_code integer, OUT alert_text text) 
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_jobs RECORD;
    v_job_errors RECORD;
    v_count int = 1;
    v_trouble text[];
BEGIN
    
    alert_text := '(';
    alert_code := 1;
    -- Generic check for jobs without special monitoring. Should error on 3 failures
    FOR v_job_errors IN SELECT l.job_name FROM @extschema@.job_check_log l 
        WHERE l.job_name NOT IN (select c.job_name from @extschema@.job_check_config c where l.job_name <> c.job_name) GROUP BY l.job_name HAVING count(*) > 2
    LOOP
        v_trouble[v_count] := v_job_errors.job_name;
        v_count := v_count+1;
    END LOOP;
    
    IF array_upper(v_trouble,1) > 0 THEN
        alert_code = 3;
        alert_text := alert_text || 'Jobs w/ 3 consecutive errors: '||array_to_string(v_trouble,', ')||'; ';
    END IF;
    
    -- Jobs with special monitoring (threshold different than 3 errors; must run within a timeframe; etc)
    for v_jobs in 
                select
                    job_name,
                    status, 
                    current_timestamp,
                    current_timestamp - start_time as last_run_time,  
                    case
                        when (select count(*) from @extschema@.job_check_log where job_name = job_check_config.job_name) > sensitivity then 'ERROR'  
                        when start_time < (current_timestamp - error_threshold) then 'ERROR' 
                        when start_time < (current_timestamp - warn_threshold) then 'WARNING'
                        else 'OK'
                    end as error_code,
                    case
                        when status = 'BAD' then 'BAD' 
                        when status is null then 'MISSING' 
                        when (start_time < current_timestamp - error_threshold) OR (start_time < current_timestamp - warn_threshold) then 
                            case 
                                when status = 'OK' then 'MISSING'
                                else status
                            end
                    end as job_status
                from
                    @extschema@.job_check_config 
                    left join (
                                select
                                    job_name,
                                    max(start_time) as start_time 
                                from
                                    @extschema@.job_log
                                where
                                    start_time > now() - v_history
                                group by 
                                    job_name 
                                ) last_job using (job_name)
                    left join (
                                select 
                                    job_name,    
                                    start_time, 
                                    coalesce(status,
                                    (select case when (select count(*) from pg_locks where not granted and pid = m.pid) > 0 THEN 'BLOCKED' ELSE NULL END),
                                    (select case when (select count(*) from pg_stat_activity where procpid = m.pid) > 0 THEN 'RUNNING' ELSE NULL END),
                                    'FOOBAR') as status
                                from
                                    @extschema@.job_log m 
                                where 
                                    start_time > now() - v_history
                                ) lj_status using (job_name,start_time)   
                 where active      
loop

    if v_jobs.error_code = 'ERROR' then
        alert_code := 3;
        alert_text := alert_text || v_jobs.job_name || ': ' || coalesce(v_jobs.job_status,'null??') || '; ';
    end if;
    
    if v_jobs.job_status = 'MISSING' AND v_jobs.last_run_time IS NULL then
        alert_code := 3;
        alert_text := alert_text || v_jobs.job_name || ': MISSING - Last run over ' || v_history || ' hrs ago. Check job_log for more details;';
    end if;

    if v_jobs.error_code = 'WARNING' then
        IF alert_code <> 3 THEN
            alert_code := 2;
        END IF;
        alert_text := alert_text || v_jobs.job_name || ': ' || coalesce(v_jobs.job_status,'null??') || '; ';
    end if;
    

end loop;

if alert_text = '(' then
    alert_text := alert_text || 'All jobs run successfully';
end if;

alert_text := alert_text || ')';

end
$$;
