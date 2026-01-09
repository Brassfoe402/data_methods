from datetime import datetime, timedelta
from data_pipeline.load_data_to_db import DatabaseConnector
from data_pipeline.load_to_mysql import load_data_to_mysql_stg, run_mysql_procedure
from typing import Optional, Dict, Any
import logging

logger = logging.getLogger(__name__)


def transfer_to_mysql(pg_config: Dict[str, Any],
                     mysql_config: Dict[str, Any],
                     start_dt: Optional[datetime] = None,
                     end_dt: Optional[datetime] = None):
    if start_dt is None:
        start_dt = datetime.now() - timedelta(days=90)
    if end_dt is None:
        end_dt = datetime.now()
    
    pg_connector = DatabaseConnector(pg_config)
    
    try:
        logger.info("=== Начало перекладки данных в MySQL ===")
        
        # Шаг 1: Загрузка данных из PostgreSQL в MySQL staging
        logger.info("Шаг 1: Загрузка данных в MySQL staging таблицу...")
        load_data_to_mysql_stg(pg_connector, mysql_config, start_dt, end_dt)
        
        # Шаг 2: Запуск процедуры перекладки из staging в целевую таблицу
        logger.info("Шаг 2: Запуск процедуры перекладки данных...")
        result = run_mysql_procedure(mysql_config, start_dt, end_dt)
        
        logger.info("=== Перекладка данных в MySQL завершена ===")
        return result
        
    finally:
        pg_connector.disconnect()


