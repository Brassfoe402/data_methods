import mysql.connector
from mysql.connector import Error
from typing import Dict, Any, Optional
from datetime import datetime
import logging
import math
from decimal import Decimal

logger = logging.getLogger(__name__)


class MySQLConnector:

    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.connection = None

    def connect(self):
        try:
            self.connection = mysql.connector.connect(**self.config)
            logger.info("Соединение с MySQL установлено")
        except Error as e:
            logger.error(f"Ошибка подключения к MySQL: {e}")
            self.connection = None
            raise

    def disconnect(self):
        if self.connection and self.connection.is_connected():
            self.connection.close()
            self.connection = None
            logger.info("Соединение с MySQL закрыто")

    def execute_query(self, query: str, params: Optional[tuple] = None):
        if self.connection is None or not self.connection.is_connected():
            raise RuntimeError("Соединение с MySQL не установлено")
        cursor = self.connection.cursor()
        try:
            cursor.execute(query, params)
            self.connection.commit()
            logger.info(f"Запрос выполнен: {query[:50]}...")
        except Error as e:
            self.connection.rollback()
            logger.error(f"Ошибка выполнения запроса: {e}")
            raise
        finally:
            cursor.close()

    def execute_procedure(self, procedure_name: str, params: Optional[tuple] = None):
        if self.connection is None or not self.connection.is_connected():
            raise RuntimeError("Соединение с MySQL не установлено")
        cursor = self.connection.cursor()
        try:
            cursor.callproc(procedure_name, params)
            result = []
            for result_set in cursor.stored_results():
                result.extend(result_set.fetchall())
            self.connection.commit()
            logger.info(f"Процедура выполнена: {procedure_name}")
            return result
        except Error as e:
            self.connection.rollback()
            logger.error(f"Ошибка выполнения процедуры: {e}")
            raise
        finally:
            cursor.close()

    def fetch_all(self, query: str, params: Optional[tuple] = None):
        if self.connection is None or not self.connection.is_connected():
            raise RuntimeError("Соединение с MySQL не установлено")
        cursor = self.connection.cursor()
        try:
            cursor.execute(query, params)
            return cursor.fetchall()
        except Error as e:
            logger.error(f"Ошибка выполнения запроса: {e}")
            raise
        finally:
            cursor.close()


def _to_none_if_nan(v):
    """
    Превращает любые NaN/Inf-представления в None (чтобы MySQL получил NULL и не упал).
    Поддерживает: float, numpy.float64, Decimal('NaN'), строки 'NaN', 'inf', '-inf'.
    """
    if v is None:
        return None

    # Строки вида "NaN"
    if isinstance(v, str):
        s = v.strip().lower()
        if s in {"nan", "+nan", "-nan", "inf", "+inf", "-inf", "infinity", "+infinity", "-infinity"}:
            return None
        return v

    # Decimal NaN / Infinity
    if isinstance(v, Decimal):
        try:
            if v.is_nan() or v.is_infinite():
                return None
        except Exception:
            pass
        return v

    # numpy.nan / float / любые числа, которые можно безопасно привести к float
    try:
        fv = float(v)
        if math.isnan(fv) or math.isinf(fv):
            return None
    except Exception:
        # Не число (например datetime) — оставляем как есть
        return v

    return v


def load_data_to_mysql_stg(
    pg_connector,
    mysql_config: Dict[str, Any],
    start_dt: Optional[datetime] = None,
    end_dt: Optional[datetime] = None,
):
    """
    Загружает данные из представления v_dm_task PostgreSQL в staging таблицу MySQL
    """
    from datetime import timedelta

    if start_dt is None:
        start_dt = datetime.now() - timedelta(days=90)
    if end_dt is None:
        end_dt = datetime.now()

    mysql_conn = MySQLConnector(mysql_config)

    try:
        # Подключение к PostgreSQL и получение данных
        if pg_connector.connection is None:
            pg_connector.connect()

        pg_cursor = pg_connector.connection.cursor()

        query = """
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
            FROM s_psql_dds.v_dm_task
            WHERE DATE(created_at) BETWEEN %s AND %s
        """

        pg_cursor.execute(query, (start_dt.date(), end_dt.date()))
        rows = pg_cursor.fetchall()
        pg_cursor.close()

        logger.info(f"Получено {len(rows)} записей из PostgreSQL")

        # Нормализация данных: NaN/Inf -> None, плюс подстановки под NOT NULL + CHECK
        clean_rows = []
        for r in rows:
            r = tuple(_to_none_if_nan(v) for v in r)

            (
                id_source,
                source_id,
                category_id,
                status_id,
                region_id,
                amount,
                duration,
                cnt,
                created_at,
                updated_at,
                load_dttm,
            ) = r

            # Подстановки, чтобы не падать на NOT NULL / CHECK в MySQL
            # amount > 0
            if amount is None:
                amount = Decimal("0.01")
            # duration > 0
            if duration is None:
                duration = 1
            # count >= 0
            if cnt is None:
                cnt = 0

            # Таймстемпы обязательны
            if created_at is None:
                created_at = start_dt
            if updated_at is None:
                updated_at = end_dt
            if load_dttm is None:
                load_dttm = datetime.now()

            clean_rows.append(
                (
                    id_source,
                    source_id,
                    category_id,
                    status_id,
                    region_id,
                    amount,
                    duration,
                    cnt,
                    created_at,
                    updated_at,
                    load_dttm,
                )
            )

        rows = clean_rows

        # Подключение к MySQL и загрузка данных
        mysql_conn.connect()

        # Очистка staging таблицы за период
        mysql_conn.execute_query(
            "DELETE FROM t_dm_stg_task WHERE DATE(created_at) BETWEEN %s AND %s",
            (start_dt.date(), end_dt.date()),
        )

        # Вставка данных в staging таблицу
        if rows:
            insert_query = """
                INSERT INTO t_dm_stg_task (
                    id_source, source_id, category_id, status_id, region_id,
                    amount, duration, count, created_at, updated_at, load_dttm
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """
            mysql_cursor = mysql_conn.connection.cursor()
            mysql_cursor.executemany(insert_query, rows)
            mysql_conn.connection.commit()
            mysql_cursor.close()

            logger.info(f"Загружено {len(rows)} записей в MySQL staging таблицу")
        else:
            logger.warning("Нет строк для загрузки в MySQL staging (пустая выборка).")

    finally:
        mysql_conn.disconnect()


def run_mysql_procedure(
    mysql_config: Dict[str, Any],
    start_dt: Optional[datetime] = None,
    end_dt: Optional[datetime] = None,
):
    """
    Запускает процедуру fn_dm_data_stg_to_dm_load в MySQL
    """
    from datetime import timedelta

    if start_dt is None:
        start_dt = datetime.now() - timedelta(days=90)
    if end_dt is None:
        end_dt = datetime.now()

    mysql_conn = MySQLConnector(mysql_config)

    try:
        mysql_conn.connect()
        result = mysql_conn.execute_procedure(
            "fn_dm_data_stg_to_dm_load",
            (start_dt.date(), end_dt.date()),
        )
        logger.info(f"Процедура MySQL выполнена. Результат: {result}")
        return result
    finally:
        mysql_conn.disconnect()

