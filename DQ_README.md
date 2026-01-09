# Data Quality Pipeline - Документация

## Обзор

Реализован полный Data Quality пайплайн с проверками для PostgreSQL и MySQL, дашбордом, алертингом и автоматическим планировщиком.

## Компоненты

### 1. Проверки качества данных

#### PostgreSQL (`v_dm_task`)
- **Correctness**: Сравнение сумм между источником и витриной
- **Completeness**: Проверка пропусков в критических полях
- **Consistency**: Проверка бизнес-правил
- **Uniqueness**: Отсутствие дубликатов по `id_source`
- **Validity**: Валидность внешних ключей

#### MySQL (`t_dm_task`)
- **Correctness**: Внутренняя согласованность данных
- **Completeness**: Проверка пропусков в критических полях
- **Consistency**: Проверка бизнес-правил
- **Uniqueness**: Отсутствие дубликатов по `id_source`
- **Validity**: Проверка диапазонов данных

### 2. Хранение результатов

- **PostgreSQL**: `s_psql_dds.t_dq_check_results`
- **MySQL**: `t_dq_check_results`

### 3. Дашборд (Streamlit)

Визуализация метрик качества данных в реальном времени.

**Запуск:**
```bash
# Локально
streamlit run dashboard/app.py

# В Docker
docker-compose up dashboard
```

**Доступ:** http://localhost:8501

**Возможности:**
- Метрики по статусам проверок
- Графики по типам проверок
- Детальные результаты проверок
- Фильтрация по времени, типу проверки, статусу
- Автообновление данных

### 4. Алертинг

Механизм уведомлений о критических нарушениях.

**Поддерживаемые каналы:**
- Email (SMTP)
- Slack (Webhook)

**Настройка через переменные окружения:**
```bash
# Email
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-password
SMTP_FROM=noreply@etl-lab.local
ALERT_EMAIL_TO=admin@example.com,team@example.com

# Slack
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

**Интеграция:**
Алерты автоматически отправляются при обнаружении статусов `failed` или `error` в проверках.

### 5. Планировщик (Scheduler)

Автоматический запуск проверок качества данных по расписанию.

**Расписание:** Каждый час в :00

**Запуск:**
```bash
# Локально
python scheduler/dq_scheduler.py

# В Docker
docker-compose up dq_scheduler
```

**Настройка расписания:**
Измените `CronTrigger` в `scheduler/dq_scheduler.py`:
```python
# Каждый час
CronTrigger(minute=0)

# Каждые 6 часов
CronTrigger(hour='*/6', minute=0)

# Каждый день в 2:00
CronTrigger(hour=2, minute=0)
```

## Использование

### Ручной запуск проверок

#### PostgreSQL
```python
from data_pipeline.run_data_quality_checks import run_data_quality_checks
from config import DATABASE_CONFIG
from datetime import datetime, timedelta

start_dt = datetime.now() - timedelta(days=1)
end_dt = datetime.now()

run_data_quality_checks(
    db_config=DATABASE_CONFIG,
    start_dt=start_dt,
    end_dt=end_dt
)
```

#### MySQL
```python
from data_pipeline.run_mysql_dq_checks import run_mysql_data_quality_checks
from config import MYSQL_CONFIG
from datetime import datetime, timedelta

start_dt = datetime.now() - timedelta(days=1)
end_dt = datetime.now()

run_mysql_data_quality_checks(
    mysql_config=MYSQL_CONFIG,
    start_dt=start_dt,
    end_dt=end_dt
)
```

### Интеграция в ETL пайплайн

Проверки автоматически выполняются в шагах 7-9 основного ETL пайплайна:
- Шаг 7: Проверки PostgreSQL
- Шаг 8: Проверки MySQL
- Шаг 9: Проверка критических нарушений и алертинг

### Просмотр результатов

#### PostgreSQL
```sql
SELECT 
    check_type,
    status,
    execution_date,
    error_message
FROM s_psql_dds.t_dq_check_results
ORDER BY execution_date DESC
LIMIT 10;
```

#### MySQL
```sql
SELECT 
    check_type,
    status,
    execution_date,
    error_message
FROM t_dq_check_results
ORDER BY execution_date DESC
LIMIT 10;
```

## Docker Compose

### Запуск всех сервисов
```bash
docker-compose up -d
```

### Отдельные сервисы
```bash
# Только дашборд
docker-compose up dashboard

# Только планировщик
docker-compose up dq_scheduler

# Полный ETL пайплайн
docker-compose run --rm etl_app python main.py
```

## Структура файлов

```
.
├── data_pipeline/
│   ├── run_data_quality_checks.py    # PostgreSQL DQ checks
│   ├── run_mysql_dq_checks.py         # MySQL DQ checks
│   └── alerting.py                    # Alerting mechanism
├── dashboard/
│   └── app.py                         # Streamlit dashboard
├── scheduler/
│   └── dq_scheduler.py                # Scheduled DQ checks
├── sql/
│   ├── dds/s_psql_dds/
│   │   ├── function/
│   │   │   └── fn_dq_checks_load.sql  # PostgreSQL DQ function
│   │   └── table/
│   │       └── t_dq_check_results.sql
│   └── mysql/init.sql                 # MySQL DQ procedure
└── docker-compose.yml                 # Docker services
```

## Требования

- Python 3.12+
- PostgreSQL 15+
- MySQL 8.0+
- Docker & Docker Compose

## Установка зависимостей

```bash
pip install -r requirements.txt
```

## Переменные окружения

Создайте `.env` файл:
```bash
# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=etl_lab
DB_USER=postgres
DB_PASSWORD=postgres

MYSQL_HOST=localhost
MYSQL_PORT=3307
MYSQL_DB=etl_lab
MYSQL_USER=root
MYSQL_PASSWORD=root

# Alerting (опционально)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-password
SMTP_FROM=noreply@etl-lab.local
ALERT_EMAIL_TO=admin@example.com
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

## Troubleshooting

### Дашборд не запускается
- Проверьте, что порт 8501 свободен
- Убедитесь, что базы данных доступны

### Планировщик не работает
- Проверьте логи: `docker-compose logs dq_scheduler`
- Убедитесь, что переменные окружения настроены

### Алерты не отправляются
- Проверьте настройки SMTP/Slack в переменных окружения
- Проверьте логи на наличие ошибок отправки

## Мониторинг

Все результаты проверок сохраняются в таблицах результатов. Используйте дашборд для визуализации или SQL-запросы для детального анализа.

