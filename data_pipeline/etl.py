from datetime import datetime, timedelta
import logging

from config import DATABASE_CONFIG, MYSQL_CONFIG, ETL_CONFIG
from data_pipeline.get_dataset import get_dataset
from data_pipeline.load_data_to_db import load_data_to_db, DatabaseConnector
from data_pipeline.fill_structured_table import fill_structured_table
from data_pipeline.fill_dm_table import fill_dm_table
from data_pipeline.transfer_to_mysql import transfer_to_mysql


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


def _get_date_range_from_pg(db_config, schema: str, table: str):
    """
    Берём min/max created_at из таблицы в Postgres, чтобы период всегда совпадал с данными,
    а не зависел от текущей даты.
    """
    connector = DatabaseConnector(db_config)
    try:
        connector.connect()
        cur = connector.connection.cursor()
        cur.execute(f"select min(created_at)::date, max(created_at)::date from {schema}.{table};")
        min_dt, max_dt = cur.fetchone()
        cur.close()

        if min_dt is None or max_dt is None:
            # fallback: последние 90 дней
            start_dt = datetime.now() - timedelta(days=90)
            end_dt = datetime.now()
            return start_dt, end_dt

        # делаем datetime границы
        start_dt = datetime.combine(min_dt, datetime.min.time())
        end_dt = datetime.combine(max_dt, datetime.max.time())
        return start_dt, end_dt

    finally:
        connector.disconnect()


def etl():
    try:
        logger.info("=== Запуск полного пайплайна (ETL -> DM -> MySQL) ===")

        # 1) Генерация
        logger.info("Шаг 1: Генерация синтетических данных...")
        df = get_dataset(num_records=1000)
        logger.info(f"Сгенерировано {len(df)} записей")

        # 2) Загрузка в unstructured
        logger.info("Шаг 2: Загрузка в неструктурированную таблицу...")
        load_data_to_db(
            df,
            DATABASE_CONFIG,
            schema=ETL_CONFIG["schema_unstructured"],
            table=ETL_CONFIG["table_unstructured"],
        )

        # 3) Определяем период по данным
        logger.info("Шаг 3: Определение периода по данным (min/max created_at)...")
        start_dt, end_dt = _get_date_range_from_pg(
            DATABASE_CONFIG,
            ETL_CONFIG["schema_unstructured"],
            ETL_CONFIG["table_unstructured"],
        )
        logger.info(f"Период данных: {start_dt.date()} - {end_dt.date()}")

        # 4) Structured
        logger.info("Шаг 4: Заполнение структурированной таблицы...")
        fill_structured_table(DATABASE_CONFIG, start_dt, end_dt)

        # 5) DM в Postgres
        logger.info("Шаг 5: Заполнение DM таблицы в PostgreSQL...")
        fill_dm_table(
            DATABASE_CONFIG,
            start_dt=start_dt,
            end_dt=end_dt,
            function_name=ETL_CONFIG["function_dm"],
        )

        # 6) Перенос в MySQL (stg -> dm)
        logger.info("Шаг 6: Перекладка витрины в MySQL (stg -> dm)...")
        transfer_to_mysql(
            pg_config=DATABASE_CONFIG,
            mysql_config=MYSQL_CONFIG,
            start_dt=start_dt,
            end_dt=end_dt,
        )

        logger.info("=== Пайплайн успешно завершен ===")

    except Exception as e:
        logger.error(f"Ошибка в пайплайне: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    etl()
