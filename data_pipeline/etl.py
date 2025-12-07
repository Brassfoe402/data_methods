from data_pipeline.get_dataset import get_dataset
from data_pipeline.load_data_to_db import load_data_to_db
from data_pipeline.fill_structured_table import fill_structured_table
from config import DATABASE_CONFIG, ETL_CONFIG
from datetime import datetime, timedelta
import logging

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def etl():
    """
    Главная функция ETL-пипелайна.
    
    Выполняет:
    1. Генерацию синтетических данных
    2. Загрузку в неструктурированную таблицу
    3. Трансформацию и загрузку в структурированную таблицу
    """
    try:
        logger.info("=== Запуск ETL-пипелайна ===")
        
        # Шаг 1: Генерация данных
        logger.info("Шаг 1: Генерация синтетических данных...")
        df = get_dataset(num_records=1000)
        logger.info(f"Сгенерировано {len(df)} записей")
        
        # Шаг 2: Загрузка в БД (unstructured)
        logger.info("Шаг 2: Загрузка в неструктурированную таблицу...")
        load_data_to_db(
            df,
            DATABASE_CONFIG,
            schema=ETL_CONFIG['schema_unstructured'],
            table=ETL_CONFIG['table_unstructured']
        )
        
        # Шаг 3: Заполнение структурированной таблицы
        logger.info("Шаг 3: Заполнение структурированной таблицы...")
        start_date = datetime.now() - timedelta(days=90)
        end_date = datetime.now()
        fill_structured_table(DATABASE_CONFIG, start_date, end_date)
        
        logger.info("=== ETL-пипелайн успешно завершен ===")
        
    except Exception as e:
        logger.error(f"Ошибка в ETL-пипелайне: {e}", exc_info=True)
        raise


if __name__ == '__main__':
    etl()


print("✓ etl.py создан")