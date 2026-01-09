drop function if exists s_psql_dds.fn_dq_checks_load(date, date) cascade;

create function s_psql_dds.fn_dq_checks_load(p_start_dt date, p_end_dt date)
returns void as $$
declare
    v_check_result integer;
    v_error_message text;
    v_total_records integer;
    v_null_records integer;
    v_duplicate_count integer;
    v_invalid_fk_count integer;
    v_source_sum numeric;
    v_dm_sum numeric;
    v_category_sum numeric;
    v_total_sum numeric;
begin
    raise notice 'Starting data quality checks: % - %', p_start_dt, p_end_dt;
    
    -- Check 1: Correctness - comparison of sums between source and data mart
    begin
        SELECT COALESCE(SUM(CASE WHEN amount::text = 'NaN' THEN 0 ELSE amount END), 0) INTO v_source_sum
        FROM s_psql_dds.t_sql_source_structured
        WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
        AND amount IS NOT NULL;

        SELECT COALESCE(SUM(CASE WHEN amount::text = 'NaN' THEN 0 ELSE amount END), 0) INTO v_dm_sum
        FROM s_psql_dds.v_dm_task
        WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
        AND amount IS NOT NULL;
        if abs(v_source_sum - v_dm_sum) > 0.01 then
            insert into s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) values (
                'correctness',
                'v_dm_task',
                'failed',
                'Sum mismatch: source = ' || COALESCE(v_source_sum::TEXT, '0') || 
                ', data_mart = ' || COALESCE(v_dm_sum::TEXT, '0') || 
                ', difference = ' || COALESCE(ABS(v_source_sum - v_dm_sum)::TEXT, '0')
            );
        else
            insert into s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) values (
                'correctness',
                'v_dm_task',
                'passed',
                'Sums match: source = ' || COALESCE(v_source_sum::TEXT, '0') || 
                ', data_mart = ' || COALESCE(v_dm_sum::TEXT, '0')
            );
        end if;
    exception when others then
        insert into s_psql_dds.t_dq_check_results (
            check_type, table_name, status, error_message
        ) values (
            'correctness',
            'v_dm_task',
            'error',
            'Error in correctness check: ' || sqlerrm
        );
    end;
    
    -- Check 2: Completeness - checking for missing values in critical fields
    begin
        select count(*) into v_total_records
        from s_psql_dds.v_dm_task
        where date(created_at) between p_start_dt and p_end_dt;
        
        select count(*) into v_null_records
        from s_psql_dds.v_dm_task
        where date(created_at) between p_start_dt and p_end_dt
        and (id_source is null or amount is null or source_id is null 
             or category_id is null or status_id is null or region_id is null);
        
        if v_total_records > 0 then
            if v_null_records > 0 then
                insert into s_psql_dds.t_dq_check_results (
                    check_type, table_name, status, error_message
                ) values (
                    'completeness',
                    'v_dm_task',
                    'failed',
                    format('Found %s records with missing values out of %s (%.2f%%)', 
                           v_null_records, v_total_records, 
                           (v_null_records::numeric / v_total_records::numeric * 100))
                );
            else
                insert into s_psql_dds.t_dq_check_results (
                    check_type, table_name, status, error_message
                ) values (
                    'completeness',
                    'v_dm_task',
                    'passed',
                    format('No missing values found. Total records: %s', v_total_records)
                );
            end if;
        else
            insert into s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) values (
                'completeness',
                'v_dm_task',
                'warning',
                'No data for the specified period'
            );
        end if;
    exception when others then
        insert into s_psql_dds.t_dq_check_results (
            check_type, table_name, status, error_message
        ) values (
            'completeness',
            'v_dm_task',
            'error',
            'Error in completeness check: ' || sqlerrm
        );
    end;
    
    -- Check 3: Consistency - business rules validation
    begin
        -- Check: sum by categories should equal total sum
        select coalesce(sum(case when amount::text = 'NaN' then 0 else amount end), 0) into v_total_sum
        from s_psql_dds.v_dm_task
        where date(created_at) between p_start_dt and p_end_dt
        and amount is not null;
        
        select coalesce(sum(case when category_sum::text = 'NaN' then 0 else category_sum end), 0) into v_category_sum
        from (
            select sum(case when amount::text = 'NaN' then 0 else amount end) as category_sum
            from s_psql_dds.v_dm_task
            where date(created_at) between p_start_dt and p_end_dt
            and amount is not null
            group by category_id
        ) sub;
        
        if abs(v_total_sum - v_category_sum) > 0.01 then
            insert into s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) values (
                'consistency',
                'v_dm_task',
                'failed',
                'Business rule violation: total_sum = ' || COALESCE(v_total_sum::TEXT, '0') || 
                ', sum_by_categories = ' || COALESCE(v_category_sum::TEXT, '0') || 
                ', difference = ' || COALESCE(ABS(v_total_sum - v_category_sum)::TEXT, '0')
            );
        else
            insert into s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) values (
                'consistency',
                'v_dm_task',
                'passed',
                'Business rules satisfied: total_sum = ' || COALESCE(v_total_sum::TEXT, '0') || 
                ', sum_by_categories = ' || COALESCE(v_category_sum::TEXT, '0')
            );
        end if;
    exception when others then
        insert into s_psql_dds.t_dq_check_results (
            check_type, table_name, status, error_message
        ) values (
            'consistency',
            'v_dm_task',
            'error',
            'Error in consistency check: ' || sqlerrm
        );
    end;
    
    -- Check 4: Uniqueness - no duplicates by id_source
    begin
        select count(*) into v_duplicate_count
        from (
            select id_source, count(*) as cnt
            from s_psql_dds.v_dm_task
            where date(created_at) between p_start_dt and p_end_dt
            group by id_source
            having count(*) > 1
        ) duplicates;
        
        if v_duplicate_count > 0 then
            insert into s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) values (
                'uniqueness',
                'v_dm_task',
                'failed',
                format('Found %s duplicates by id_source field', v_duplicate_count)
            );
        else
            insert into s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) values (
                'uniqueness',
                'v_dm_task',
                'passed',
                'No duplicates by id_source found'
            );
        end if;
    exception when others then
        insert into s_psql_dds.t_dq_check_results (
            check_type, table_name, status, error_message
        ) values (
            'uniqueness',
            'v_dm_task',
            'error',
            'Error in uniqueness check: ' || sqlerrm
        );
    end;
    
    -- Check 5: Validity - FK values match reference tables
    begin
        select count(*) into v_invalid_fk_count
        from s_psql_dds.v_dm_task v
        where date(v.created_at) between p_start_dt and p_end_dt
        and (
            not exists (select 1 from s_psql_dds.d_source ds where ds.id = v.source_id)
            or not exists (select 1 from s_psql_dds.d_category dc where dc.id = v.category_id)
            or not exists (select 1 from s_psql_dds.d_status dst where dst.id = v.status_id)
            or not exists (select 1 from s_psql_dds.d_region dr where dr.id = v.region_id)
        );
        
        if v_invalid_fk_count > 0 then
            insert into s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) values (
                'validity',
                'v_dm_task',
                'failed',
                format('Found %s records with invalid foreign keys', v_invalid_fk_count)
            );
        else
            insert into s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) values (
                'validity',
                'v_dm_task',
                'passed',
                'All foreign keys are valid'
            );
        end if;
    exception when others then
        insert into s_psql_dds.t_dq_check_results (
            check_type, table_name, status, error_message
        ) values (
            'validity',
            'v_dm_task',
            'error',
            'Error in validity check: ' || sqlerrm
        );
    end;
    
    raise notice 'Data quality checks completed';
    
exception when others then
    raise notice 'Critical error in fn_dq_checks_load: %', sqlerrm;
    insert into s_psql_dds.t_dq_check_results (
        check_type, table_name, status, error_message
    ) values (
        'system',
        'v_dm_task',
        'error',
        'Critical error: ' || sqlerrm
    );
end;
$$ language plpgsql;

comment on function s_psql_dds.fn_dq_checks_load(date, date) is 'Function for executing data quality checks in v_dm_task data mart';

