from datetime import datetime, timedelta
from data_pipeline.load_to_mysql import MySQLConnector
from typing import Optional, Dict, Any
import logging

logger = logging.getLogger(__name__)


def run_mysql_data_quality_checks(mysql_config: Dict[str, Any],
                                 start_dt: Optional[datetime] = None,
                                 end_dt: Optional[datetime] = None,
                                 procedure_name: str = 'fn_dq_checks_mysql_load'):
    """
    Run data quality checks for MySQL target table
    
    Args:
        mysql_config: MySQL connection configuration
        start_dt: Start date for checks
        end_dt: End date for checks
        procedure_name: Name of the MySQL procedure to execute
    """
    if start_dt is None:
        start_dt = datetime.now() - timedelta(days=90)
    if end_dt is None:
        end_dt = datetime.now()
    
    connector = MySQLConnector(mysql_config)
    
    try:
        connector.connect()
        
        logger.info(f"Starting MySQL data quality checks for period {start_dt.date()} - {end_dt.date()}")
        
        connector.execute_procedure(
            procedure_name,
            params=(start_dt.date(), end_dt.date())
        )
        
        # Get check results
        results = connector.fetch_all("""
            SELECT check_type, status, error_message, execution_date
            FROM t_dq_check_results
            WHERE execution_date >= %s
            ORDER BY execution_date DESC, check_type
            LIMIT 10
        """, (start_dt,))
        
        logger.info("=== MySQL Data Quality Check Results ===")
        for check_type, status, error_message, exec_date in results:
            status_icon = "✅" if status == 'passed' else "❌" if status == 'failed' else "⚠️"
            logger.info(f"{status_icon} {check_type}: {status}")
            if error_message:
                logger.info(f"   {error_message}")
        
        logger.info("MySQL data quality checks completed")
        
        return results
        
    finally:
        connector.disconnect()


def get_mysql_dq_summary(mysql_config: Dict[str, Any], 
                         limit: int = 20) -> list:
    """
    Get summary of MySQL data quality check results
    
    Args:
        mysql_config: MySQL connection configuration
        limit: Number of recent checks to display
        
    Returns:
        List of check results
    """
    connector = MySQLConnector(mysql_config)
    
    try:
        connector.connect()
        results = connector.fetch_all("""
            SELECT 
                check_id,
                check_type,
                table_name,
                execution_date,
                status,
                error_message
            FROM t_dq_check_results
            ORDER BY execution_date DESC
            LIMIT %s
        """, (limit,))
        
        return results
        
    finally:
        connector.disconnect()

