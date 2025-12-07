from data_pipeline.etl import etl
import sys


def main():
    """Запускает ETL-пипелайн."""
    try:
        etl()
        sys.exit(0)
    except Exception as e:
        print(f"Критическая ошибка: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()


print("✓ main.py создан")