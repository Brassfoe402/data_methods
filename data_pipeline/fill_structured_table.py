from datetime import datetime, timedelta
from data_pipeline.load_data_to_db import DatabaseConnector
from typing import Optional, Dict, Any
import logging

logger = logging.getLogger(__name__)


def fill_structured_table(db_config: Dict[str, Any],
                         start_date: Optional[datetime] = None,
                         end_date: Optional[datetime] = None,
                         function_name = 's_psql_dds.fn_etl_data_load'):
    if start_date is None:
        start_date = datetime.now() - timedelta(days=90)
    if end_date is None:
        end_date = datetime.now()
    
    connector = DatabaseConnector(db_config)
    
    try:
        connector.connect()
        
        result = connector.execute_function(
            function_name,
            params=(start_date.date(), end_date.date())
        )
        
        logger.info(f"Структурированная таблица заполнена. Результат: {result}")
        
    finally:
        connector.disconnect()
