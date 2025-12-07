import pytest
import psycopg2
from datetime import datetime, timedelta
from data_pipeline.get_dataset import get_dataset
from data_pipeline.load_data_to_db import load_data_to_db, DatabaseConnector
from config import DATABASE_CONFIG, ETL_CONFIG
import logging

logger = logging.getLogger(__name__)


@pytest.fixture(scope='session')
def db_config():
    """Конфигурация БД для тестов."""
    return DATABASE_CONFIG


@pytest.fixture
def test_data():
    """Генерирует тестовые данные."""
    return get_dataset(num_records=100, seed=42)


class TestGetDataset:
    """Тесты генератора данных."""
    
    def test_dataset_shape(self):
        """Проверяет размер датасета."""
        df = get_dataset(num_records=100)
        assert len(df) > 0
        assert len(df.columns) == 10
    
    def test_dataset_columns(self):
        """Проверяет наличие всех колонок."""
        df = get_dataset(num_records=100)
        expected_columns = {
            'id', 'source', 'category', 'status', 'region',
            'amount', 'duration', 'count', 'created_at', 'updated_at'
        }
        assert set(df.columns) == expected_columns
    
    def test_dataset_has_anomalies(self):
        """Проверяет наличие аномалий в данных."""
        df = get_dataset(num_records=1000)
        # Проверяем наличие NULL значений
        assert df.isnull().sum().sum() > 0
        # Проверяем наличие отрицательных значений
        has_negative = (df['amount'] < 0).any() or (df['duration'] < 0).any()
        assert has_negative or (df['amount'].isna().any() or df['duration'].isna().any())
    
    def test_dataset_reproducibility(self):
        """Проверяет воспроизводимость данных."""
        df1 = get_dataset(num_records=100, seed=42)
        df2 = get_dataset(num_records=100, seed=42)
        assert df1.equals(df2)


class TestDatabaseConnector:
    """Тесты подключения к БД."""
    
    #@pytest.mark.skip(reason="Требует запущенную БД локально")
    def test_connection(self, db_config):
        """Проверяет подключение к БД."""
        connector = DatabaseConnector(db_config)
        connector.connect()
        assert connector.connection is not None
        connector.disconnect()
        assert connector.connection is None



class TestLoadDataToDB:
    """Тесты загрузки данных в БД."""
    
    #@pytest.mark.skip(reason="Требует запущенную БД локально")
    def test_load_data(self, db_config, test_data):
        """Проверяет загрузку данных в БД."""
        load_data_to_db(
            test_data,
            db_config,
            schema=ETL_CONFIG['schema_unstructured'],
            table=ETL_CONFIG['table_unstructured']
        )
        connector = DatabaseConnector(db_config)
        connector.connect()
        assert connector.connection is not None, "Не удалось установить соединение к базе"
        cursor = connector.connection.cursor()
        cursor.execute(f"SELECT COUNT(*) FROM {ETL_CONFIG['schema_unstructured']}.{ETL_CONFIG['table_unstructured']}")
        count = cursor.fetchone()[0]
        connector.disconnect()
        assert count > 0


class TestETLFunction:
    """Тесты SQL функции ETL."""
    
    #@pytest.mark.skip(reason="Требует запущенную БД локально")
    def test_etl_function_execution(self, db_config):
        """Проверяет выполнение SQL функции ETL."""
        start_date = (datetime.now() - timedelta(days=90)).date()
        end_date = datetime.now().date()
        
        connector = DatabaseConnector(db_config)
        connector.connect()
        
        connector.execute_function(
            's_psql_dds.fn_etl_data_load', 
            params=(start_date, end_date)
        )

        
        connector.disconnect()


class TestDataQuality:
    """Тесты качества данных."""
    
    def test_dataset_data_types(self):
        """Проверяет типы данных в датасете."""
        df = get_dataset(num_records=100)
        # Проверяем типы данных
        assert df['id'].dtype == 'int64'
        assert df['amount'].dtype == 'float64'
        assert df['duration'].dtype == 'int64'
        assert df['count'].dtype == 'int64'
    
    def test_dataset_no_empty_categories(self):
        """Проверяет, что категориальные поля не полностью пусты."""
        df = get_dataset(num_records=1000)
        # Хотя бы одно значение не должно быть NULL для каждого поля
        assert df['source'].notna().any()
        assert df['category'].notna().any()
        assert df['status'].notna().any()
        assert df['region'].notna().any()