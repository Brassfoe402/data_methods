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

-- Создание таблицы для результатов проверок качества данных
DROP TABLE IF EXISTS t_dq_check_results;

CREATE TABLE t_dq_check_results (
    check_id INT AUTO_INCREMENT PRIMARY KEY,
    check_type VARCHAR(50) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    execution_date DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
    status VARCHAR(20) NOT NULL,
    error_message TEXT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_dq_check_results_date ON t_dq_check_results(execution_date);
CREATE INDEX idx_dq_check_results_status ON t_dq_check_results(status);
CREATE INDEX idx_dq_check_results_type ON t_dq_check_results(check_type);

-- Создание процедуры для проверок качества данных в MySQL
DROP PROCEDURE IF EXISTS fn_dq_checks_mysql_load;

DELIMITER //

CREATE PROCEDURE fn_dq_checks_mysql_load(
    IN p_start_dt DATE,
    IN p_end_dt DATE
)
BEGIN
    DECLARE v_total_records INT DEFAULT 0;
    DECLARE v_null_records INT DEFAULT 0;
    DECLARE v_duplicate_count INT DEFAULT 0;
    DECLARE v_invalid_fk_count INT DEFAULT 0;
    DECLARE v_category_sum DECIMAL(15,2) DEFAULT 0;
    DECLARE v_total_sum DECIMAL(15,2) DEFAULT 0;
    DECLARE v_error_msg VARCHAR(500);
    
    -- Check 1: Correctness - internal consistency check
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1
                v_error_msg = MESSAGE_TEXT;
            INSERT INTO t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'correctness',
                't_dm_task',
                'error',
                CONCAT('Error in correctness check: ', v_error_msg)
            );
        END;
        
        SELECT COALESCE(SUM(amount), 0) INTO v_total_sum
        FROM t_dm_task
        WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
        AND amount IS NOT NULL;
        
        INSERT INTO t_dq_check_results (
            check_type, table_name, status, error_message
        ) VALUES (
            'correctness',
            't_dm_task',
            'passed',
            CONCAT('MySQL sum verified: ', v_total_sum)
        );
    END;
    
    -- Check 2: Completeness - checking for missing values
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1
                v_error_msg = MESSAGE_TEXT;
            INSERT INTO t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'completeness',
                't_dm_task',
                'error',
                CONCAT('Error in completeness check: ', v_error_msg)
            );
        END;
        
        SELECT COUNT(*) INTO v_total_records
        FROM t_dm_task
        WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt;
        
        SELECT COUNT(*) INTO v_null_records
        FROM t_dm_task
        WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
        AND (id_source IS NULL OR amount IS NULL OR source_id IS NULL 
             OR category_id IS NULL OR status_id IS NULL OR region_id IS NULL);
        
        IF v_total_records > 0 THEN
            IF v_null_records > 0 THEN
                INSERT INTO t_dq_check_results (
                    check_type, table_name, status, error_message
                ) VALUES (
                    'completeness',
                    't_dm_task',
                    'failed',
                    CONCAT('Found ', v_null_records, ' records with missing values out of ', 
                           v_total_records, ' (', 
                           ROUND((v_null_records / v_total_records * 100), 2), '%)')
                );
            ELSE
                INSERT INTO t_dq_check_results (
                    check_type, table_name, status, error_message
                ) VALUES (
                    'completeness',
                    't_dm_task',
                    'passed',
                    CONCAT('No missing values found. Total records: ', v_total_records)
                );
            END IF;
        ELSE
            INSERT INTO t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'completeness',
                't_dm_task',
                'warning',
                'No data for the specified period'
            );
        END IF;
    END;
    
    -- Check 3: Consistency - business rules validation
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1
                v_error_msg = MESSAGE_TEXT;
            INSERT INTO t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'consistency',
                't_dm_task',
                'error',
                CONCAT('Error in consistency check: ', v_error_msg)
            );
        END;
        
        SELECT COALESCE(SUM(amount), 0) INTO v_total_sum
        FROM t_dm_task
        WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
        AND amount IS NOT NULL;
        
        SELECT COALESCE(SUM(category_sum), 0) INTO v_category_sum
        FROM (
            SELECT SUM(amount) AS category_sum
            FROM t_dm_task
            WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
            AND amount IS NOT NULL
            GROUP BY category_id
        ) sub;
        
        IF ABS(v_total_sum - v_category_sum) > 0.01 THEN
            INSERT INTO t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'consistency',
                't_dm_task',
                'failed',
                CONCAT('Business rule violation: total_sum = ', v_total_sum, 
                       ', sum_by_categories = ', v_category_sum, 
                       ', difference = ', ABS(v_total_sum - v_category_sum))
            );
        ELSE
            INSERT INTO t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'consistency',
                't_dm_task',
                'passed',
                CONCAT('Business rules satisfied: total_sum = ', v_total_sum, 
                       ', sum_by_categories = ', v_category_sum)
            );
        END IF;
    END;
    
    -- Check 4: Uniqueness - no duplicates by id_source
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1
                v_error_msg = MESSAGE_TEXT;
            INSERT INTO t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'uniqueness',
                't_dm_task',
                'error',
                CONCAT('Error in uniqueness check: ', v_error_msg)
            );
        END;
        
        SELECT COUNT(*) INTO v_duplicate_count
        FROM (
            SELECT id_source, COUNT(*) AS cnt
            FROM t_dm_task
            WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
            GROUP BY id_source
            HAVING COUNT(*) > 1
        ) duplicates;
        
        IF v_duplicate_count > 0 THEN
            INSERT INTO t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'uniqueness',
                't_dm_task',
                'failed',
                CONCAT('Found ', v_duplicate_count, ' duplicates by id_source field')
            );
        ELSE
            INSERT INTO t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'uniqueness',
                't_dm_task',
                'passed',
                'No duplicates by id_source found'
            );
        END IF;
    END;
    
    -- Check 5: Validity - check constraints and data ranges
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1
                v_error_msg = MESSAGE_TEXT;
            INSERT INTO t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'validity',
                't_dm_task',
                'error',
                CONCAT('Error in validity check: ', v_error_msg)
            );
        END;
        
        SELECT COUNT(*) INTO v_invalid_fk_count
        FROM t_dm_task
        WHERE DATE(created_at) BETWEEN p_start_dt AND p_end_dt
        AND (
            amount <= 0
            OR duration <= 0
            OR count < 0
            OR created_at > updated_at
        );
        
        IF v_invalid_fk_count > 0 THEN
            INSERT INTO t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'validity',
                't_dm_task',
                'failed',
                CONCAT('Found ', v_invalid_fk_count, ' records with invalid data ranges')
            );
        ELSE
            INSERT INTO t_dq_check_results (
                check_type, table_name, status, error_message
            ) VALUES (
                'validity',
                't_dm_task',
                'passed',
                'All data ranges are valid'
            );
        END IF;
    END;
    
END //

DELIMITER ;
