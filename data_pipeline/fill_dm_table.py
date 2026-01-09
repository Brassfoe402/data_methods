from datetime import datetime, timedelta
from data_pipeline.load_data_to_db import DatabaseConnector
from typing import Optional, Dict, Any
import logging

logger = logging.getLogger(__name__)


def fill_dm_table(db_config: Dict[str, Any],
                  start_dt: Optional[datetime] = None,
                  end_dt: Optional[datetime] = None,
                  function_name: str = 's_psql_dds.fn_dm_data_load'):
    """
    Функция для заполнения таблицы t_dm_task через вызов функции fn_dm_data_load
    
    Args:
        db_config: Конфигурация подключения к БД
        start_dt: Начальная дата периода
        end_dt: Конечная дата периода
        function_name: Имя функции для вызова
    """
    if start_dt is None:
        start_dt = datetime.now() - timedelta(days=90)
    if end_dt is None:
        end_dt = datetime.now()
    
    connector = DatabaseConnector(db_config)
    
    try:
        connector.connect()
        
        result = connector.execute_function(
            function_name,
            params=(start_dt.date(), end_dt.date())
        )
        
        logger.info(f"Таблица t_dm_task заполнена. Результат: {result}")
        return result
        
    finally:
        connector.disconnect()

