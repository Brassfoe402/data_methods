
import logging
import sys
import os
from datetime import datetime, timedelta
from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.triggers.cron import CronTrigger

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from config import DATABASE_CONFIG, MYSQL_CONFIG
from data_pipeline.run_data_quality_checks import run_data_quality_checks
from data_pipeline.run_mysql_dq_checks import run_mysql_data_quality_checks
from data_pipeline.alerting import check_and_alert_critical_issues

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


def run_dq_checks_job():
    try:
        logger.info("=== Starting scheduled data quality checks ===")
        
        # Calculate date range (last 24 hours)
        end_dt = datetime.now()
        start_dt = end_dt - timedelta(days=1)
        
        # Run PostgreSQL checks
        logger.info("Running PostgreSQL DQ checks...")
        pg_results = run_data_quality_checks(
            db_config=DATABASE_CONFIG,
            start_dt=start_dt,
            end_dt=end_dt,
        )
        
        # Get PostgreSQL results for alerting
        from data_pipeline.load_data_to_db import DatabaseConnector
        pg_connector = DatabaseConnector(DATABASE_CONFIG)
        pg_connector.connect()
        cursor = pg_connector.connection.cursor()
        cursor.execute("""
            SELECT check_type, status, error_message, execution_date
            FROM s_psql_dds.t_dq_check_results
            WHERE execution_date >= %s
            ORDER BY execution_date DESC, check_type
            LIMIT 10
        """, (start_dt,))
        pg_results_list = cursor.fetchall()
        cursor.close()
        pg_connector.disconnect()
        
        # Run MySQL checks
        logger.info("Running MySQL DQ checks...")
        mysql_results = run_mysql_data_quality_checks(
            mysql_config=MYSQL_CONFIG,
            start_dt=start_dt,
            end_dt=end_dt,
        )
        
        # Get MySQL results for alerting
        from data_pipeline.load_to_mysql import MySQLConnector
        mysql_connector = MySQLConnector(MYSQL_CONFIG)
        mysql_connector.connect()
        mysql_results_list = mysql_connector.fetch_all("""
            SELECT check_type, status, error_message, execution_date
            FROM t_dq_check_results
            WHERE execution_date >= %s
            ORDER BY execution_date DESC, check_type
            LIMIT 10
        """, (start_dt,)) if mysql_connector else []
        mysql_connector.disconnect()
        
        # Check for critical issues and send alerts
        logger.info("Checking for critical issues...")
        critical_issues = check_and_alert_critical_issues(
            pg_results=pg_results_list,
            mysql_results=mysql_results_list
        )
        
        if critical_issues:
            logger.warning(f"Found {len(critical_issues)} critical issues")
        else:
            logger.info("No critical issues found")
        
        logger.info("=== Scheduled data quality checks completed ===")
        
    except Exception as e:
        logger.error(f"Error in scheduled DQ checks job: {e}", exc_info=True)


def main():
    """Main scheduler function"""
    scheduler = BlockingScheduler()
    
    # Schedule job to run every hour
    scheduler.add_job(
        run_dq_checks_job,
        trigger=CronTrigger(minute=0),  # Run at the start of every hour
        id='dq_checks_job',
        name='Data Quality Checks',
        replace_existing=True
    )
    
    logger.info("Data Quality Scheduler started")
    logger.info("Checks will run every hour at :00")
    
    try:
        scheduler.start()
    except (KeyboardInterrupt, SystemExit):
        logger.info("Scheduler stopped")
        scheduler.shutdown()


if __name__ == "__main__":
    main()

