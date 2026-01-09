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
        GREATEST(count, 0),
        -- гарантируем created_at <= updated_at
        LEAST(created_at, updated_at) as created_at,
        GREATEST(created_at, updated_at) as updated_at
    FROM s_psql_dds.t_sql_source_unstructured
    WHERE 
        LEAST(created_at, updated_at)::DATE BETWEEN p_start_date AND p_end_date
        AND id IS NOT NULL             
        AND amount IS NOT NULL
        AND created_at IS NOT NULL
        AND updated_at IS NOT NULL
    
    ON CONFLICT (id_source) DO UPDATE 
    SET
        source = EXCLUDED.source,
        category = EXCLUDED.category,
        status = EXCLUDED.status,
        region = EXCLUDED.region,
        amount = EXCLUDED.amount,
        duration = EXCLUDED.duration,
        count = EXCLUDED.count,
        -- гарантируем created_at <= updated_at при обновлении
        created_at = LEAST(
            LEAST(EXCLUDED.created_at, EXCLUDED.updated_at),
            s_psql_dds.t_sql_source_structured.created_at
        ),
        updated_at = GREATEST(
            GREATEST(EXCLUDED.created_at, EXCLUDED.updated_at),
            s_psql_dds.t_sql_source_structured.updated_at
        ),
        load_dttm = CURRENT_TIMESTAMP;
    
    -- дополнительная проверка: исправляем записи, где created_at > updated_at
    UPDATE s_psql_dds.t_sql_source_structured
    SET
        created_at = LEAST(created_at, updated_at),
        updated_at = GREATEST(created_at, updated_at)
    WHERE created_at > updated_at;

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

-- Создание таблицы для хранения результатов проверок качества данных
CREATE TABLE s_psql_dds.t_dq_check_results (
    check_id SERIAL PRIMARY KEY,
    check_type VARCHAR(50) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    execution_date TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) NOT NULL,
    error_message TEXT
);

COMMENT ON TABLE s_psql_dds.t_dq_check_results IS 'Таблица для хранения результатов проверок качества данных';

CREATE INDEX idx_dq_check_results_date ON s_psql_dds.t_dq_check_results(execution_date);
CREATE INDEX idx_dq_check_results_status ON s_psql_dds.t_dq_check_results(status);

-- Создание функции для проверок качества данных
CREATE OR REPLACE FUNCTION s_psql_dds.fn_dq_checks_load(p_start_dt DATE, p_end_dt DATE)
RETURNS VOID AS $$
DECLARE
    v_check_result INTEGER;
    v_error_message TEXT;
    v_total_records INTEGER;
    v_null_records INTEGER;
    v_duplicate_count INTEGER;
    v_invalid_fk_count INTEGER;
    v_source_sum NUMERIC;
    v_dm_sum NUMERIC;
    v_category_sum NUMERIC;
    v_total_sum NUMERIC;
BEGIN
    RAISE NOTICE 'Starting data quality checks: % - %', p_start_dt, p_end_dt;
    
    -- Check 1: Correctness - comparison of sums between source and data mart
    BEGIN
        SELECT COALESCE(SUM(CASE WHEN amount::TEXT = 'NaN' THEN 0 ELSE amount END), 0) INTO v_source_sum
        FROM s_psql_dds.t_sql_source_structured
        WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
        AND amount IS NOT NULL;
        
        SELECT COALESCE(SUM(CASE WHEN amount::TEXT = 'NaN' THEN 0 ELSE amount END), 0) INTO v_dm_sum
        FROM s_psql_dds.v_dm_task
        WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
        AND amount IS NOT NULL;
        
        IF ABS(v_source_sum - v_dm_sum) > 0.01 THEN
            INSERT INTO s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'correctness',
                'v_dm_task',
                'failed',
                'Sum mismatch: source = ' || COALESCE(v_source_sum::TEXT, '0') || 
                ', data_mart = ' || COALESCE(v_dm_sum::TEXT, '0') || 
                ', difference = ' || COALESCE(ABS(v_source_sum - v_dm_sum)::TEXT, '0')
            );
        ELSE
            INSERT INTO s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'correctness',
                'v_dm_task',
                'passed',
                'Sums match: source = ' || COALESCE(v_source_sum::TEXT, '0') || 
                ', data_mart = ' || COALESCE(v_dm_sum::TEXT, '0')
            );
        END IF;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO s_psql_dds.t_dq_check_results (
            check_type, table_name, status, error_message
        ) VALUES (
            'correctness',
            'v_dm_task',
            'error',
            'Error in correctness check: ' || SQLERRM
        );
    END;
    
    -- Check 2: Completeness - checking for missing values in critical fields
    BEGIN
        SELECT COUNT(*) INTO v_total_records
        FROM s_psql_dds.v_dm_task
        WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt;
        
        SELECT COUNT(*) INTO v_null_records
        FROM s_psql_dds.v_dm_task
        WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
        AND (id_source IS NULL OR amount IS NULL OR source_id IS NULL 
             OR category_id IS NULL OR status_id IS NULL OR region_id IS NULL);
        
        IF v_total_records > 0 THEN
            IF v_null_records > 0 THEN
                INSERT INTO s_psql_dds.t_dq_check_results (
                    check_type, table_name, status, error_message
                ) VALUES (
                    'completeness',
                    'v_dm_task',
                    'failed',
                    FORMAT('Found %s records with missing values out of %s (%.2f%%)', 
                           v_null_records, v_total_records, 
                           (v_null_records::NUMERIC / v_total_records::NUMERIC * 100))
                );
            ELSE
                INSERT INTO s_psql_dds.t_dq_check_results (
                    check_type, table_name, status, error_message
                ) VALUES (
                    'completeness',
                    'v_dm_task',
                    'passed',
                    FORMAT('No missing values found. Total records: %s', v_total_records)
                );
            END IF;
        ELSE
            INSERT INTO s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'completeness',
                'v_dm_task',
                'warning',
                'No data for the specified period'
            );
        END IF;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO s_psql_dds.t_dq_check_results (
            check_type, table_name, status, error_message
        ) VALUES (
            'completeness',
            'v_dm_task',
            'error',
            'Error in completeness check: ' || SQLERRM
        );
    END;
    
    -- Check 3: Consistency - business rules validation
    BEGIN
        -- Check: sum by categories should equal total sum
        SELECT COALESCE(SUM(CASE WHEN amount::TEXT = 'NaN' THEN 0 ELSE amount END), 0) INTO v_total_sum
        FROM s_psql_dds.v_dm_task
        WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
        AND amount IS NOT NULL;
        
        SELECT COALESCE(SUM(CASE WHEN category_sum::TEXT = 'NaN' THEN 0 ELSE category_sum END), 0) INTO v_category_sum
        FROM (
            SELECT SUM(CASE WHEN amount::TEXT = 'NaN' THEN 0 ELSE amount END) AS category_sum
            FROM s_psql_dds.v_dm_task
            WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
            AND amount IS NOT NULL
            GROUP BY category_id
        ) sub;
        
        IF ABS(v_total_sum - v_category_sum) > 0.01 THEN
            INSERT INTO s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'consistency',
                'v_dm_task',
                'failed',
                'Business rule violation: total_sum = ' || COALESCE(v_total_sum::TEXT, '0') || 
                ', sum_by_categories = ' || COALESCE(v_category_sum::TEXT, '0') || 
                ', difference = ' || COALESCE(ABS(v_total_sum - v_category_sum)::TEXT, '0')
            );
        ELSE
            INSERT INTO s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'consistency',
                'v_dm_task',
                'passed',
                'Business rules satisfied: total_sum = ' || COALESCE(v_total_sum::TEXT, '0') || 
                ', sum_by_categories = ' || COALESCE(v_category_sum::TEXT, '0')
            );
        END IF;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO s_psql_dds.t_dq_check_results (
            check_type, table_name, status, error_message
        ) VALUES (
            'consistency',
            'v_dm_task',
            'error',
            'Error in consistency check: ' || SQLERRM
        );
    END;
    
    -- Check 4: Uniqueness - no duplicates by id_source
    BEGIN
        SELECT COUNT(*) INTO v_duplicate_count
        FROM (
            SELECT id_source, COUNT(*) AS cnt
            FROM s_psql_dds.v_dm_task
            WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
            GROUP BY id_source
            HAVING COUNT(*) > 1
        ) duplicates;
        
        IF v_duplicate_count > 0 THEN
            INSERT INTO s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'uniqueness',
                'v_dm_task',
                'failed',
                FORMAT('Found %s duplicates by id_source field', v_duplicate_count)
            );
        ELSE
            INSERT INTO s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'uniqueness',
                'v_dm_task',
                'passed',
                'No duplicates by id_source found'
            );
        END IF;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO s_psql_dds.t_dq_check_results (
            check_type, table_name, status, error_message
        ) VALUES (
            'uniqueness',
            'v_dm_task',
            'error',
            'Error in uniqueness check: ' || SQLERRM
        );
    END;
    
    -- Check 5: Validity - FK values match reference tables
    BEGIN
        SELECT COUNT(*) INTO v_invalid_fk_count
        FROM s_psql_dds.v_dm_task v
        WHERE DATE(v.created_at) BETWEEN p_start_dt AND p_end_dt
        AND (
            NOT EXISTS (SELECT 1 FROM s_psql_dds.d_source ds WHERE ds.id = v.source_id)
            OR NOT EXISTS (SELECT 1 FROM s_psql_dds.d_category dc WHERE dc.id = v.category_id)
            OR NOT EXISTS (SELECT 1 FROM s_psql_dds.d_status dst WHERE dst.id = v.status_id)
            OR NOT EXISTS (SELECT 1 FROM s_psql_dds.d_region dr WHERE dr.id = v.region_id)
        );
        
        IF v_invalid_fk_count > 0 THEN
            INSERT INTO s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'validity',
                'v_dm_task',
                'failed',
                FORMAT('Found %s records with invalid foreign keys', v_invalid_fk_count)
            );
        ELSE
            INSERT INTO s_psql_dds.t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'validity',
                'v_dm_task',
                'passed',
                'All foreign keys are valid'
            );
        END IF;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO s_psql_dds.t_dq_check_results (
            check_type, table_name, status, error_message
        ) VALUES (
            'validity',
            'v_dm_task',
            'error',
            'Error in validity check: ' || SQLERRM
        );
    END;
    
    RAISE NOTICE 'Data quality checks completed';
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Critical error in fn_dq_checks_load: %', SQLERRM;
    INSERT INTO s_psql_dds.t_dq_check_results (
        check_type, table_name, status, error_message
    ) VALUES (
        'system',
        'v_dm_task',
        'error',
        'Critical error: ' || SQLERRM
    );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION s_psql_dds.fn_dq_checks_load(DATE, DATE) IS 'Function for executing data quality checks in v_dm_task data mart';