drop function if exists s_psql_dds.fn_etl_data_load(date, date) cascade;

create function s_psql_dds.fn_etl_data_load(p_start_date date, p_end_date date)
returns table (
    v_processed_rows integer,
    v_status varchar
) as $$
declare
    v_deleted_rows integer := 0;
    v_inserted_rows integer := 0;
begin
    -- Логирование начала функции
    raise notice 'Начало fn_etl_data_load: % - %', p_start_date, p_end_date;
    
    -- Очищаем целевую таблицу
    truncate table s_psql_dds.t_sql_source_structured;
    
    -- Основная логика трансформации и загрузки
    insert into s_psql_dds.t_sql_source_structured 
    (id_source, source, category, status, region, amount, duration, count, created_at, updated_at)
    select 
        -- ID (удаляем дубликаты, берем первый)
        row_number() over (partition by id order by id) as id_source,
        -- Source (замена NULL на 'UNKNOWN')
        coalesce(nullif(trim(source), ''), 'UNKNOWN') as source,
        -- Category (валидация, очистка от пустых и некорректных значений)
        case 
            when trim(category) in ('A', 'B', 'C', 'D', 'E') then trim(category)
            else 'UNKNOWN'
        end as category,
        -- Status (валидация статусов)
        case 
            when trim(status) in ('ACTIVE', 'INACTIVE', 'PENDING', 'CANCELLED') then trim(status)
            else 'PENDING'
        end as status,
        -- Region (валидация регионов)
        case 
            when trim(region) in ('RU', 'EU', 'US', 'ASIA', 'OTHER') then trim(region)
            else 'OTHER'
        end as region,
        -- Amount (убираем отрицательные значения, NULL замена на 0)
        case 
            when amount is null or amount <= 0 then 0.01
            else abs(amount)
        end as amount,
        -- Duration (убираем отрицательные, минимум 1 день)
        case 
            when duration is null or duration <= 0 then 1
            else abs(duration)
        end as duration,
        -- Count (убираем отрицательные)
        case 
            when count is null or count < 0 then 0
            else count
        end as count,
        -- Created_at (проверяем корректность даты)
        case 
            when created_at is null then now()
            when date(created_at) > p_end_date then now()
            else created_at
        end as created_at,
        -- Updated_at (проверяем, что позже created_at)
        case 
            when updated_at is null or updated_at < created_at then created_at
            when date(updated_at) > p_end_date then created_at
            else updated_at
        end as updated_at
    from s_psql_dds.t_sql_source_unstructured
    where 
        -- Фильтруем по дате
        date(coalesce(created_at, now())) between p_start_date and p_end_date
    group by
        -- Убираем полные дубликаты
        id, source, category, status, region, amount, duration, count, created_at, updated_at
    having 
        -- Фильтруем невалидные строки
        (amount > 0 or amount is null)
        and (duration > 0 or duration is null)
        and (count >= 0 or count is null);
    
    get diagnostics v_inserted_rows = row_count;
    
    -- Возвращаем результат
    return query
    select v_inserted_rows, 'SUCCESS'::varchar;
    
    -- Логирование завершения
    raise notice 'Завершено fn_etl_data_load. Загружено % записей', v_inserted_rows;
    
exception when others then
    raise notice 'Ошибка в fn_etl_data_load: %', sqlerrm;
    return query
    select 0, ('ERROR: ' || sqlerrm)::varchar;
end;
$$ language plpgsql;

comment on function s_psql_dds.fn_etl_data_load(date, date) is 'ETL функция для трансформации и загрузки данных из неструктурированной в структурированную таблицу';


print("✓ fn_etl_data_load.sql создан")