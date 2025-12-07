import psycopg2
from psycopg2.extras import execute_values
import pandas as pd
from typing import Optional, Dict, Any, Tuple
import logging

logger = logging.getLogger(__name__)

class DatabaseConnector:
    """Класс для управления подключением к PostgreSQL."""
    
    def __init__(self, config: Dict[str, Any]):
        """
        Инициализирует подключение к БД.
        
        Args:
            config: конфигурация подключения
        """
        self.config = config
        self.connection = None
    
    def connect(self):
        """Устанавливает подключение к БД."""
        try:
            self.connection = psycopg2.connect(**self.config)
            print("Соединение с базой установлено")
        except Exception as e:
            print(f"Ошибка подключения к БД: {e}")
            self.connection = None
            raise
    
    def disconnect(self):
        """Закрывает подключение."""
        if self.connection:
            self.connection.close()
            self.connection = None
            print("Соединение с базой закрыто")
    
    def execute_query(self, query: str, params: Optional[Tuple[Any, ...]] = None):
        """Выполняет SQL-запрос."""
        if self.connection is None:
            raise RuntimeError("Соединение с БД не установлено")
        cursor = self.connection.cursor()
        try:
            cursor.execute(query, params)
            self.connection.commit()
            logger.info(f"Запрос выполнен: {query[:50]}...")
        except Exception as e:
            self.connection.rollback()
            logger.error(f"Ошибка выполнения запроса: {e}")
            raise
        finally:
            cursor.close()
    
    def execute_function(self, function_name: str, params: Optional[Tuple[Any, ...]] = None) -> Any:
        """Выполняет SQL-функцию."""
        if self.connection is None:
            raise RuntimeError("Соединение с БД не установлено")
        cursor = self.connection.cursor()
        try:
            # Формируем вызов функции
            param_str = ','.join(['%s'] * len(params)) if params else ''
            query = f"SELECT {function_name}({param_str})"
            cursor.execute(query, params)
            result = cursor.fetchone()
            self.connection.commit()
            logger.info(f"Функция выполнена: {function_name}")
            return result
        except Exception as e:
            self.connection.rollback()
            logger.error(f"Ошибка выполнения функции: {e}")
            raise
        finally:
            cursor.close()

def load_data_to_db(df: pd.DataFrame, db_config: Dict[str, Any], 
                    schema: str = 's_psql_dds', 
                    table: str = 't_sql_source_unstructured'):
    """
    Загружает данные в неструктурированную таблицу.
    
    Args:
        df: DataFrame для загрузки
        db_config: конфигурация БД
        schema: имя схемы
        table: имя таблицы
    """
    connector = DatabaseConnector(db_config)
    
    try:
        connector.connect()
        if connector.connection is None:
            raise RuntimeError("Соединение с базой не установлено")
        cursor = connector.connection.cursor()

        columns = df.columns.tolist()
        column_names = ', '.join(columns)
        
        # --- ИСПРАВЛЕНО: для execute_values используем просто %s ---
        query = f"INSERT INTO {schema}.{table} ({column_names}) VALUES %s"

        values = [tuple(row) for row in df.values]
        
        # execute_values сам развернет список значений
        execute_values(cursor, query, values, page_size=1000)
        connector.connection.commit()
        
        cursor.close()
        print(f"Загружено {len(df)} записей в {schema}.{table}")
    except Exception as e:
        print(f"Ошибка при загрузке данных: {e}")
        raise
    finally:
        connector.disconnect()
