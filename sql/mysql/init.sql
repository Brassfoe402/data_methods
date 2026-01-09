-- Создание базы данных (если не существует)
CREATE DATABASE IF NOT EXISTS etl_lab CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE etl_lab;

-- Создание staging таблицы
DROP TABLE IF EXISTS t_dm_stg_task;

CREATE TABLE t_dm_stg_task (
    id INT AUTO_INCREMENT PRIMARY KEY,
    id_source INT NOT NULL,
    source_id INT NOT NULL,
    category_id INT NOT NULL,
    status_id INT NOT NULL,
    region_id INT NOT NULL,
    amount DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    duration INT NOT NULL CHECK (duration > 0),
    count INT NOT NULL CHECK (count >= 0),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    load_dttm TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_dm_stg_task_dates CHECK (created_at <= updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Создание целевой таблицы
DROP TABLE IF EXISTS t_dm_task;

CREATE TABLE t_dm_task (
    id INT AUTO_INCREMENT PRIMARY KEY,
    id_source INT NOT NULL,
    source_id INT NOT NULL,
    category_id INT NOT NULL,
    status_id INT NOT NULL,
    region_id INT NOT NULL,
    amount DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    duration INT NOT NULL CHECK (duration > 0),
    count INT NOT NULL CHECK (count >= 0),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    load_dttm TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_dm_task_dates CHECK (created_at <= updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Создание представления (витрина)
DROP VIEW IF EXISTS v_dm_task;

CREATE VIEW v_dm_task AS
SELECT
    id,
    id_source,
    source_id,
    category_id,
    status_id,
    region_id,
    amount,
    duration,
    count,
    created_at,
    updated_at,
    load_dttm
FROM t_dm_task;

-- Создание процедуры для перекладки данных
DROP PROCEDURE IF EXISTS fn_dm_data_stg_to_dm_load;

DELIMITER //

CREATE PROCEDURE fn_dm_data_stg_to_dm_load(
    IN p_start_dt DATE,
    IN p_end_dt DATE
)
BEGIN
    DECLARE v_inserted_rows INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 0 AS processed_rows, 'ERROR' AS status;
    END;

    START TRANSACTION;

    -- Очистка данных за период в целевой таблице
    DELETE FROM t_dm_task
    WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt;

    -- Перекладка данных из staging в целевую таблицу
    INSERT INTO t_dm_task (
        id_source,
        source_id,
        category_id,
        status_id,
        region_id,
        amount,
        duration,
        count,
        created_at,
        updated_at,
        load_dttm
    )
    SELECT
        id_source,
        source_id,
        category_id,
        status_id,
        region_id,
        amount,
        duration,
        count,
        created_at,
        updated_at,
        load_dttm
    FROM t_dm_stg_task
    WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt;

    SET v_inserted_rows = ROW_COUNT();

    COMMIT;

    SELECT v_inserted_rows AS processed_rows, 'SUCCESS' AS status;
END //

DELIMITER ;
