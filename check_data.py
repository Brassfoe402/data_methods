import psycopg2
from config import DATABASE_CONFIG

conn = psycopg2.connect(**DATABASE_CONFIG)
cur = conn.cursor()

# 1. Проверяем количество записей
cur.execute("SELECT COUNT(*) FROM s_psql_dds.t_sql_source_unstructured")
raw_count = cur.fetchone()[0]

cur.execute("SELECT COUNT(*) FROM s_psql_dds.t_sql_source_structured")
clean_count = cur.fetchone()[0]

print(f"Записей в сырой таблице: {raw_count}")
print(f"Записей в чистой таблице: {clean_count}")
print(f"Отфильтровано (дубликаты/мусор): {raw_count - clean_count}")

# 2. Проверяем, остались ли отрицательные суммы в чистой таблице (не должно быть)
cur.execute("SELECT COUNT(*) FROM s_psql_dds.t_sql_source_structured WHERE amount < 0")
neg_errors = cur.fetchone()[0]
print(f"Ошибок с отрицательной суммой: {neg_errors} (должно быть 0)")

cur.close()
conn.close()
