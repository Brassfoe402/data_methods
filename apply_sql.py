import psycopg2
from config import DATABASE_CONFIG

def apply():
    try:
        conn = psycopg2.connect(**DATABASE_CONFIG)
        cur = conn.cursor()
        with open('sql/init.sql', 'r', encoding='utf-8') as f:
            cur.execute(f.read())
        conn.commit()
        print("✅ init.sql успешно применен!")
        cur.close()
        conn.close()
    except Exception as e:
        print(f"❌ Ошибка: {e}")

if __name__ == "__main__":
    apply()
