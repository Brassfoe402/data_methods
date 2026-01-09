create or replace function s_psql_dds.fn_etl_data_load(p_start_date date, p_end_date date)
returns void
language plpgsql
as
$$
begin
    insert into s_psql_dds.t_sql_source_structured (
        id_source,
        source,
        category,
        status,
        region,
        amount,
        duration,
        count,
        created_at,
        updated_at
    )
    select distinct on (u.id)
        u.id as id_source,
        coalesce(nullif(u.source, ''), 'UNKNOWN') as source,
        coalesce(nullif(u.category, ''), 'UNKNOWN') as category,
        coalesce(nullif(u.status, ''), 'UNKNOWN') as status,
        coalesce(nullif(u.region, ''), 'UNKNOWN') as region,

        -- чистим числовые аномалии
        abs(u.amount) as amount,
        abs(u.duration) as duration,
        greatest(u.count, 0) as count,

        -- фикс дат: гарантируем created_at <= updated_at
        least(u.created_at, u.updated_at) as created_at,
        greatest(u.created_at, u.updated_at) as updated_at

    from s_psql_dds.t_sql_source_unstructured u
    where
        u.id is not null
        and u.amount is not null
        and u.created_at is not null
        and u.updated_at is not null
        and least(u.created_at, u.updated_at)::date between p_start_date and p_end_date

    order by u.id, greatest(u.created_at, u.updated_at) desc

    on conflict (id_source) do update
    set
        source   = excluded.source,
        category = excluded.category,
        status   = excluded.status,
        region   = excluded.region,
        amount   = excluded.amount,
        duration = excluded.duration,
        count    = excluded.count,

        -- гарантируем created_at <= updated_at при обновлении
        created_at = least(
            least(excluded.created_at, excluded.updated_at),
            s_psql_dds.t_sql_source_structured.created_at
        ),
        updated_at = greatest(
            greatest(excluded.created_at, excluded.updated_at),
            s_psql_dds.t_sql_source_structured.updated_at
        ),

        load_dttm = current_timestamp;
    
    -- дополнительная проверка: исправляем записи, где created_at > updated_at
    update s_psql_dds.t_sql_source_structured
    set
        created_at = least(created_at, updated_at),
        updated_at = greatest(created_at, updated_at)
    where created_at > updated_at;

end;
$$;
