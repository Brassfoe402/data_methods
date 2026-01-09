DROP SCHEMA IF EXISTS s_psql_dds CASCADE;
CREATE SCHEMA s_psql_dds;

COMMENT ON SCHEMA s_psql_dds IS 'DDS (Detailed Data Store) слой для структурированных и неструктурированных данных';

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

CREATE OR REPLACE FUNCTION s_psql_dds.fn_etl_data_load(
    p_start_date DATE,
    p_end_date DATE
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO s_psql_dds.t_sql_source_structured (
        id_source, source, category, status, region, 
        amount, duration, count, created_at, updated_at
    )
    SELECT DISTINCT ON (id) 
        id,
        COALESCE(source, 'UNKNOWN'),   
        COALESCE(category, 'UNKNOWN'),
        COALESCE(status, 'UNKNOWN'),
        COALESCE(region, 'UNKNOWN'),
        ABS(amount),                   
        ABS(duration),
        count,
        created_at,
        updated_at
    FROM s_psql_dds.t_sql_source_unstructured
    WHERE 
        created_at::DATE BETWEEN p_start_date AND p_end_date
        AND id IS NOT NULL             
        AND amount IS NOT NULL         
        AND created_at <= updated_at   
    
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

-- Создание справочников для категориальных признаков
CREATE TABLE s_psql_dds.d_source (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);

COMMENT ON TABLE s_psql_dds.d_source IS 'Справочник источников данных';

CREATE TABLE s_psql_dds.d_category (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);

COMMENT ON TABLE s_psql_dds.d_category IS 'Справочник категорий';

CREATE TABLE s_psql_dds.d_status (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);

COMMENT ON TABLE s_psql_dds.d_status IS 'Справочник статусов';

CREATE TABLE s_psql_dds.d_region (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);

COMMENT ON TABLE s_psql_dds.d_region IS 'Справочник регионов';

-- Создание таблицы t_dm_task
CREATE TABLE s_psql_dds.t_dm_task (
    id SERIAL PRIMARY KEY,
    id_source INTEGER NOT NULL,
    source_id INTEGER NOT NULL,
    category_id INTEGER NOT NULL,
    status_id INTEGER NOT NULL,
    region_id INTEGER NOT NULL,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    duration INTEGER NOT NULL CHECK (duration > 0),
    count INTEGER NOT NULL CHECK (count >= 0),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    load_dttm TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_dates CHECK (created_at <= updated_at),
    CONSTRAINT fk_source FOREIGN KEY (source_id) REFERENCES s_psql_dds.d_source(id),
    CONSTRAINT fk_category FOREIGN KEY (category_id) REFERENCES s_psql_dds.d_category(id),
    CONSTRAINT fk_status FOREIGN KEY (status_id) REFERENCES s_psql_dds.d_status(id),
    CONSTRAINT fk_region FOREIGN KEY (region_id) REFERENCES s_psql_dds.d_region(id)
);

COMMENT ON TABLE s_psql_dds.t_dm_task IS 'Таблица фактов с идентификаторами справочников';

-- Создание функции fn_dm_data_load
CREATE OR REPLACE FUNCTION s_psql_dds.fn_dm_data_load(
    p_start_dt DATE,
    p_end_dt DATE
)
RETURNS TABLE (
    v_processed_rows INTEGER,
    v_status VARCHAR
) AS $$
DECLARE
    v_inserted_rows INTEGER := 0;
BEGIN
    RAISE NOTICE 'Начало fn_dm_data_load: % - %', p_start_dt, p_end_dt;
    
    -- Заполнение справочника d_source
    INSERT INTO s_psql_dds.d_source (name)
    SELECT DISTINCT source
    FROM s_psql_dds.t_sql_source_structured
    WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
    ON CONFLICT (name) DO NOTHING;
    
    -- Заполнение справочника d_category
    INSERT INTO s_psql_dds.d_category (name)
    SELECT DISTINCT category
    FROM s_psql_dds.t_sql_source_structured
    WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
    ON CONFLICT (name) DO NOTHING;
    
    -- Заполнение справочника d_status
    INSERT INTO s_psql_dds.d_status (name)
    SELECT DISTINCT status
    FROM s_psql_dds.t_sql_source_structured
    WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
    ON CONFLICT (name) DO NOTHING;
    
    -- Заполнение справочника d_region
    INSERT INTO s_psql_dds.d_region (name)
    SELECT DISTINCT region
    FROM s_psql_dds.t_sql_source_structured
    WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
    ON CONFLICT (name) DO NOTHING;
    
    -- Очистка данных за период в целевой таблице
    DELETE FROM s_psql_dds.t_dm_task
    WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt;
    
    -- Загрузка данных в t_dm_task с джойнами на справочники
    INSERT INTO s_psql_dds.t_dm_task (
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
    SELECT 
        s.id_source,
        ds.id AS source_id,
        dc.id AS category_id,
        dst.id AS status_id,
        dr.id AS region_id,
        s.amount,
        s.duration,
        s.count,
        s.created_at,
        s.updated_at
    FROM s_psql_dds.t_sql_source_structured s
    INNER JOIN s_psql_dds.d_source ds ON s.source = ds.name
    INNER JOIN s_psql_dds.d_category dc ON s.category = dc.name
    INNER JOIN s_psql_dds.d_status dst ON s.status = dst.name
    INNER JOIN s_psql_dds.d_region dr ON s.region = dr.name
    WHERE DATE(s.created_at) BETWEEN p_start_dt AND p_end_dt;
    
    GET DIAGNOSTICS v_inserted_rows = ROW_COUNT;
    
    RETURN QUERY
    SELECT v_inserted_rows, 'SUCCESS'::VARCHAR;
    
    RAISE NOTICE 'Завершено fn_dm_data_load. Загружено % записей', v_inserted_rows;
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Ошибка в fn_dm_data_load: %', SQLERRM;
    RETURN QUERY
    SELECT 0, ('ERROR: ' || SQLERRM)::VARCHAR;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION s_psql_dds.fn_dm_data_load(DATE, DATE) IS 'Функция для загрузки данных в таблицу t_dm_task с заполнением справочников';

-- Создание представления v_dm_task
CREATE OR REPLACE VIEW s_psql_dds.v_dm_task AS
SELECT 
    t.id,
    t.id_source,
    t.source_id,
    t.category_id,
    t.status_id,
    t.region_id,
    t.amount,
    t.duration,
    t.count,
    t.created_at,
    t.updated_at,
    t.load_dttm
FROM s_psql_dds.t_dm_task t;

COMMENT ON VIEW s_psql_dds.v_dm_task IS 'Витрина данных на основе таблицы t_dm_task';