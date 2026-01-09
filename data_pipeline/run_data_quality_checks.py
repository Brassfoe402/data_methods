from datetime import datetime, timedelta
from data_pipeline.load_data_to_db import DatabaseConnector
from typing import Optional, Dict, Any
import logging

logger = logging.getLogger(__name__)


def run_data_quality_checks(db_config: Dict[str, Any],
                           start_dt: Optional[datetime] = None,
                           end_dt: Optional[datetime] = None,
                           function_name: str = 's_psql_dds.fn_dq_checks_load'):
    
    if start_dt is None:
        start_dt = datetime.now() - timedelta(days=90)
    if end_dt is None:
        end_dt = datetime.now()
    
    connector = DatabaseConnector(db_config)
    
    try:
        connector.connect()
        
        logger.info(f"Starting data quality checks for period {start_dt.date()} - {end_dt.date()}")
        
        connector.execute_function(
            function_name,
            params=(start_dt.date(), end_dt.date())
        )
        
        # Get check results
        cursor = connector.connection.cursor()
        cursor.execute("""
            SELECT check_type, status, error_message, execution_date
            FROM s_psql_dds.t_dq_check_results
            WHERE execution_date >= %s
            ORDER BY execution_date DESC, check_type
            LIMIT 10
        """, (start_dt,))
        
        results = cursor.fetchall()
        cursor.close()
        
        logger.info("=== Data Quality Check Results ===")
        for check_type, status, error_message, exec_date in results:
            status_icon = "✅" if status == 'passed' else "❌" if status == 'failed' else "⚠️"
            logger.info(f"{status_icon} {check_type}: {status}")
            if error_message:
                logger.info(f"   {error_message}")
        
        logger.info("Data quality checks completed")
        
        return results
        
    finally:
        connector.disconnect()


def get_data_quality_summary(db_config: Dict[str, Any], 
                             limit: int = 20) -> list:
    """
    Get summary of data quality check results
    
    Args:
        db_config: Database connection configuration
        limit: Number of recent checks to display
        
    Returns:
        List of check results
    """
    connector = DatabaseConnector(db_config)
    
    try:
        connector.connect()
        cursor = connector.connection.cursor()
        
        cursor.execute("""
            SELECT 
                check_id,
                check_type,
                table_name,
                execution_date,
                status,
                error_message
            FROM s_psql_dds.t_dq_check_results
            ORDER BY execution_date DESC
            LIMIT %s
        """, (limit,))
        
        results = cursor.fetchall()
        cursor.close()
        
        return results
        
    finally:
        connector.disconnect()


