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
