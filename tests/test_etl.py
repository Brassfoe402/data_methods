import pytest
import psycopg2
from datetime import datetime, timedelta
from data_pipeline.get_dataset import get_dataset
from data_pipeline.load_data_to_db import load_data_to_db, DatabaseConnector
from data_pipeline.etl import etl
from data_pipeline.fill_structured_table import fill_structured_table
from config import DATABASE_CONFIG, ETL_CONFIG
import logging

logger = logging.getLogger(__name__)

@pytest.fixture(scope='session')
def db_config():
    return DATABASE_CONFIG

@pytest.fixture
def test_data():
    return get_dataset(num_records=100, seed=42)

class TestGetDataset:
    
    def test_dataset_shape(self):
        df = get_dataset(num_records=100)
        assert len(df) > 0
        assert len(df.columns) == 10
    
    def test_dataset_columns(self):
        df = get_dataset(num_records=100)
        expected_columns = {
            'id', 'source', 'category', 'status', 'region',
            'amount', 'duration', 'count', 'created_at', 'updated_at'
        }
        assert set(df.columns) == expected_columns
    
    def test_dataset_has_anomalies(self):
        df = get_dataset(num_records=1000)
        assert df.isnull().sum().sum() > 0
        has_negative = (df['amount'] < 0).any() or (df['duration'] < 0).any()
        assert has_negative or (df['amount'].isna().any() or df['duration'].isna().any())
    
    def test_dataset_reproducibility(self):
        df1 = get_dataset(num_records=100, seed=42)
        df2 = get_dataset(num_records=100, seed=42)
        assert df1.equals(df2)

class TestDatabaseConnector:
    
    def test_connection(self, db_config):
        connector = DatabaseConnector(db_config)
        connector.connect()
        assert connector.connection is not None
        connector.disconnect()
        assert connector.connection is None

class TestLoadDataToDB:
    
    def test_load_data(self, db_config, test_data):
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
    
    def test_etl_function_execution(self, db_config):
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
    
    def test_dataset_data_types(self):
        df = get_dataset(num_records=100)
        assert df['id'].dtype == 'int64'
        assert df['amount'].dtype == 'float64'
        assert df['duration'].dtype == 'int64'
        assert df['count'].dtype == 'int64'
    
    def test_dataset_no_empty_categories(self):
        df = get_dataset(num_records=1000)
        assert df['source'].notna().any()
        assert df['category'].notna().any()
        assert df['status'].notna().any()
        assert df['region'].notna().any()

class TestIntegration:

    def test_fill_structured_table(self, db_config):
        start_date = datetime.now() - timedelta(days=90)
        end_date = datetime.now()
        
        fill_structured_table(db_config, start_date, end_date)


    def test_full_etl_pipeline(self):
        etl()
