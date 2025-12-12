import psycopg2
from config import DATABASE_CONFIG

try:
    conn = psycopg2.connect(**DATABASE_CONFIG)
    print("✅ Подключение к БД успешно!")
    
    cur = conn.cursor()
    cur.execute('SELECT version();')
    version = cur.fetchone()
    print(f"PostgreSQL версия: {version[0]}")
    
    cur.close()
    conn.close()
except Exception as e:
    print(f"❌ Ошибка подключения: {e}")
