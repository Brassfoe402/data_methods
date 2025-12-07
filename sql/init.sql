DROP SCHEMA IF EXISTS s_psql_dds CASCADE;
CREATE SCHEMA s_psql_dds;

COMMENT ON SCHEMA s_psql_dds IS 'DDS (Detailed Data Store) слой для структурированных и неструктурированных данных';

-- =============================================
-- 1. Создание таблицы для неструктурированных данных (Source)
-- =============================================
CREATE TABLE s_psql_dds.t_sql_source_unstructured (
    id INTEGER,
    source VARCHAR(50),
    category VARCHAR(50),
    status VARCHAR(50),
    region VARCHAR(50),
    amount NUMERIC,
    duration INTEGER,
    count INTEGER,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

-- =============================================
-- 2. Создание таблицы для структурированных данных (Target)
-- =============================================
CREATE TABLE s_psql_dds.t_sql_source_structured (
    id SERIAL PRIMARY KEY,
    id_source INTEGER UNIQUE NOT NULL,
    source VARCHAR(50) NOT NULL,
    category VARCHAR(50) NOT NULL,
    status VARCHAR(50) NOT NULL,
    region VARCHAR(50) NOT NULL,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    duration INTEGER NOT NULL CHECK (duration > 0),
    count INTEGER NOT NULL CHECK (count >= 0),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    load_dttm TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_dates CHECK (created_at <= updated_at)
);

-- =============================================
-- 3. Создание таблицы для тестирования (Copy)
-- =============================================
CREATE TABLE s_psql_dds.t_sql_source_structured_copy (
    id SERIAL PRIMARY KEY,
    id_source INTEGER UNIQUE NOT NULL,
    source VARCHAR(50) NOT NULL,
    category VARCHAR(50) NOT NULL,
    status VARCHAR(50) NOT NULL,
    region VARCHAR(50) NOT NULL,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    duration INTEGER NOT NULL CHECK (duration > 0),
    count INTEGER NOT NULL CHECK (count >= 0),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    load_dttm TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_dates CHECK (created_at <= updated_at)
);

-- =============================================
-- 4. Создание функции ETL (fn_etl_data_load)
-- =============================================
CREATE OR REPLACE FUNCTION s_psql_dds.fn_etl_data_load(
    p_start_date DATE,
    p_end_date DATE
)
RETURNS VOID AS $$
BEGIN
    -- Вставка данных из неструктурированной таблицы в структурированную
    -- с очисткой и преобразованием
    INSERT INTO s_psql_dds.t_sql_source_structured (
        id_source, source, category, status, region, 
        amount, duration, count, created_at, updated_at
    )
    SELECT DISTINCT ON (id) -- Убираем дубликаты по ID, оставляем первую попавшуюся запись
        id,
        COALESCE(source, 'UNKNOWN'),   -- Заполняем пропуски
        COALESCE(category, 'UNKNOWN'),
        COALESCE(status, 'UNKNOWN'),
        COALESCE(region, 'UNKNOWN'),
        ABS(amount),                   -- Убираем отрицательные значения
        ABS(duration),
        count,
        created_at,
        updated_at
    FROM s_psql_dds.t_sql_source_unstructured
    WHERE 
        created_at::DATE BETWEEN p_start_date AND p_end_date
        AND id IS NOT NULL             -- Отсеиваем записи без ID
        AND amount IS NOT NULL         -- Отсеиваем записи без суммы (можно настроить логику)
        AND created_at <= updated_at   -- Отсеиваем некорректные даты (или можно исправлять)
    
    -- При конфликте ID (если запускаем повторно) обновляем данные
    ON CONFLICT (id_source) DO UPDATE 
    SET
        source = EXCLUDED.source,
        category = EXCLUDED.category,
        status = EXCLUDED.status,
        region = EXCLUDED.region,
        amount = EXCLUDED.amount,
        duration = EXCLUDED.duration,
        count = EXCLUDED.count,
        updated_at = EXCLUDED.updated_at,
        load_dttm = CURRENT_TIMESTAMP;

END;
$$ LANGUAGE plpgsql;
