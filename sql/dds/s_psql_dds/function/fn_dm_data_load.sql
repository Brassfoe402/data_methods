drop function if exists s_psql_dds.fn_dm_data_load(date, date) cascade;

create function s_psql_dds.fn_dm_data_load(p_start_dt date, p_end_dt date)
returns table (
    v_processed_rows integer,
    v_status varchar
) as $$
declare
    v_inserted_rows integer := 0;
begin
    raise notice 'Начало fn_dm_data_load: % - %', p_start_dt, p_end_dt;
    
    -- Заполнение справочника d_source
    insert into s_psql_dds.d_source (name)
    select distinct source
    from s_psql_dds.t_sql_source_structured
    where date(created_at) between p_start_dt and p_end_dt
    on conflict (name) do nothing;
    
    -- Заполнение справочника d_category
    insert into s_psql_dds.d_category (name)
    select distinct category
    from s_psql_dds.t_sql_source_structured
    where date(created_at) between p_start_dt and p_end_dt
    on conflict (name) do nothing;
    
    -- Заполнение справочника d_status
    insert into s_psql_dds.d_status (name)
    select distinct status
    from s_psql_dds.t_sql_source_structured
    where date(created_at) between p_start_dt and p_end_dt
    on conflict (name) do nothing;
    
    -- Заполнение справочника d_region
    insert into s_psql_dds.d_region (name)
    select distinct region
    from s_psql_dds.t_sql_source_structured
    where date(created_at) between p_start_dt and p_end_dt
    on conflict (name) do nothing;
    
    -- Очистка данных за период в целевой таблице
    delete from s_psql_dds.t_dm_task
    where date(created_at) between p_start_dt and p_end_dt;
    
    -- Загрузка данных в t_dm_task с джойнами на справочники
    insert into s_psql_dds.t_dm_task (
        id_source,
        source_id,
        category_id,
        status_id,
        region_id,
        amount,
        duration,
        count,
        created_at,
        updated_at
    )
    select 
        s.id_source,
        ds.id as source_id,
        dc.id as category_id,
        dst.id as status_id,
        dr.id as region_id,
        s.amount,
        s.duration,
        s.count,
        s.created_at,
        s.updated_at
    from s_psql_dds.t_sql_source_structured s
    inner join s_psql_dds.d_source ds on s.source = ds.name
    inner join s_psql_dds.d_category dc on s.category = dc.name
    inner join s_psql_dds.d_status dst on s.status = dst.name
    inner join s_psql_dds.d_region dr on s.region = dr.name
    where date(s.created_at) between p_start_dt and p_end_dt;
    
    get diagnostics v_inserted_rows = row_count;
    
    return query
    select v_inserted_rows, 'SUCCESS'::varchar;
    
    raise notice 'Завершено fn_dm_data_load. Загружено % записей', v_inserted_rows;
    
exception when others then
    raise notice 'Ошибка в fn_dm_data_load: %', sqlerrm;
    return query
    select 0, ('ERROR: ' || sqlerrm)::varchar;
end;
$$ language plpgsql;

comment on function s_psql_dds.fn_dm_data_load(date, date) is 'Функция для загрузки данных в таблицу t_dm_task с заполнением справочников';

