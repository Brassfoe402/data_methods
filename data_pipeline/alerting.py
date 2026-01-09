import logging
import os
from typing import Dict, Any, List, Tuple
from datetime import datetime
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

logger = logging.getLogger(__name__)


def send_email_alert(
    subject: str,
    body: str,
    to_emails: List[str],
    smtp_config: Dict[str, Any] = None
):
    """
    Send email alert
    
    Args:
        subject: Email subject
        body: Email body
        to_emails: List of recipient emails
        smtp_config: SMTP configuration (host, port, user, password, from_email)
    """
    if smtp_config is None:
        smtp_config = {
            'host': os.getenv('SMTP_HOST', 'localhost'),
            'port': int(os.getenv('SMTP_PORT', 587)),
            'user': os.getenv('SMTP_USER', ''),
            'password': os.getenv('SMTP_PASSWORD', ''),
            'from_email': os.getenv('SMTP_FROM', 'noreply@etl-lab.local')
        }
    
    try:
        msg = MIMEMultipart()
        msg['From'] = smtp_config['from_email']
        msg['To'] = ', '.join(to_emails)
        msg['Subject'] = subject
        
        msg.attach(MIMEText(body, 'plain'))
        
        server = smtplib.SMTP(smtp_config['host'], smtp_config['port'])
        if smtp_config.get('user') and smtp_config.get('password'):
            server.starttls()
            server.login(smtp_config['user'], smtp_config['password'])
        
        text = msg.as_string()
        server.sendmail(smtp_config['from_email'], to_emails, text)
        server.quit()
        
        logger.info(f"Email alert sent to {to_emails}")
        return True
    except Exception as e:
        logger.error(f"Failed to send email alert: {e}")
        return False


def send_slack_alert(
    message: str,
    webhook_url: str = None
):
    """
    Send Slack alert via webhook
    
    Args:
        message: Message to send
        webhook_url: Slack webhook URL
    """
    import requests
    
    if webhook_url is None:
        webhook_url = os.getenv('SLACK_WEBHOOK_URL', '')
    
    if not webhook_url:
        logger.warning("Slack webhook URL not configured")
        return False
    
    try:
        payload = {
            'text': message
        }
        response = requests.post(webhook_url, json=payload, timeout=10)
        response.raise_for_status()
        logger.info("Slack alert sent")
        return True
    except Exception as e:
        logger.error(f"Failed to send Slack alert: {e}")
        return False


def check_and_alert_critical_issues(
    pg_results: List[Tuple],
    mysql_results: List[Tuple] = None,
    alert_config: Dict[str, Any] = None
):
    """
    Check for critical data quality issues and send alerts
    
    Args:
        pg_results: PostgreSQL check results (check_type, status, error_message, execution_date)
        mysql_results: MySQL check results (optional)
        alert_config: Alert configuration (email_to, slack_webhook, etc.)
    """
    if alert_config is None:
        alert_config = {
            'email_to': os.getenv('ALERT_EMAIL_TO', '').split(',') if os.getenv('ALERT_EMAIL_TO') else [],
            'slack_webhook': os.getenv('SLACK_WEBHOOK_URL', ''),
            'critical_statuses': ['failed', 'error']
        }
    
    critical_issues = []
    
    # Check PostgreSQL results
    for check_type, status, error_message, exec_date in pg_results:
        if status in alert_config.get('critical_statuses', ['failed', 'error']):
            critical_issues.append({
                'database': 'PostgreSQL',
                'check_type': check_type,
                'status': status,
                'error_message': error_message,
                'execution_date': exec_date
            })
    
    # Check MySQL results if provided
    if mysql_results:
        for check_type, status, error_message, exec_date in mysql_results:
            if status in alert_config.get('critical_statuses', ['failed', 'error']):
                critical_issues.append({
                    'database': 'MySQL',
                    'check_type': check_type,
                    'status': status,
                    'error_message': error_message,
                    'execution_date': exec_date
                })
    
    if critical_issues:
        # Prepare alert message
        subject = f"[Data Quality Alert] {len(critical_issues)} critical issue(s) detected"
        body = f"Critical data quality issues detected at {datetime.now()}\n\n"
        
        for issue in critical_issues:
            body += f"Database: {issue['database']}\n"
            body += f"Check Type: {issue['check_type']}\n"
            body += f"Status: {issue['status']}\n"
            body += f"Error: {issue['error_message']}\n"
            body += f"Execution Date: {issue['execution_date']}\n"
            body += "-" * 50 + "\n"
        
        # Send email alert
        if alert_config.get('email_to'):
            send_email_alert(
                subject=subject,
                body=body,
                to_emails=alert_config['email_to']
            )
        
        # Send Slack alert
        if alert_config.get('slack_webhook'):
            send_slack_alert(
                message=f"🚨 {subject}\n\n{body}",
                webhook_url=alert_config['slack_webhook']
            )
        
        logger.warning(f"Critical issues detected: {len(critical_issues)}")
        return critical_issues
    
    logger.info("No critical issues detected")
    return []

