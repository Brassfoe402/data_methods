from data_pipeline.etl import etl
import sys


def main():
    try:
        etl()
        return 0
    except Exception as e:
        print(f"Критическая ошибка: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
