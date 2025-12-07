import os
from datetime import datetime, timedelta

# Database configuration
DATABASE_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': int(os.getenv('DB_PORT', 5455)),
    'database': os.getenv('DB_NAME', 'etl_lab'),
    'user': os.getenv('DB_USER', 'postgres'),
    'password': os.getenv('DB_PASSWORD', 'postgres'),
}

# ETL configuration
ETL_CONFIG = {
    'schema_unstructured': 's_psql_dds',
    'table_unstructured': 't_sql_source_unstructured',
    'table_structured': 't_sql_source_structured',
    'function_etl': 's_psql_dds.fn_etl_data_load',
}

# Date range for ETL
DEFAULT_START_DATE = datetime.now() - timedelta(days=90)
DEFAULT_END_DATE = datetime.now()


print("✓ config.py создан")
print("✓ .gitignore создан")