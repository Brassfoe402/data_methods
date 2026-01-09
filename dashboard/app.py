import streamlit as st
import sys
import os
from datetime import datetime, timedelta
import pandas as pd

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from config import DATABASE_CONFIG, MYSQL_CONFIG
from data_pipeline.load_data_to_db import DatabaseConnector
from data_pipeline.load_to_mysql import MySQLConnector
from data_pipeline.run_data_quality_checks import get_data_quality_summary
from data_pipeline.run_mysql_dq_checks import get_mysql_dq_summary

st.set_page_config(
    page_title="Data Quality Dashboard",
    page_icon="📊",
    layout="wide"
)

st.title("📊 Data Quality Dashboard")
st.markdown("---")

# Sidebar filters
st.sidebar.header("Filters")
hours_back = st.sidebar.slider("Hours back", 1, 168, 24)
check_type_filter = st.sidebar.multiselect(
    "Check Type",
    ["correctness", "completeness", "consistency", "uniqueness", "validity", "system"],
    default=[]
)
status_filter = st.sidebar.multiselect(
    "Status",
    ["passed", "failed", "error", "warning"],
    default=[]
)

# Get data
@st.cache_data(ttl=300)
def load_pg_dq_data():
    try:
        connector = DatabaseConnector(DATABASE_CONFIG)
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
            WHERE execution_date >= NOW() - INTERVAL '168 hours'
            ORDER BY execution_date DESC
        """)
        results = cursor.fetchall()
        cursor.close()
        connector.disconnect()
        
        df = pd.DataFrame(results, columns=[
            'check_id', 'check_type', 'table_name', 'execution_date', 
            'status', 'error_message'
        ])
        return df
    except Exception as e:
        st.error(f"Error loading PostgreSQL data: {e}")
        return pd.DataFrame()

@st.cache_data(ttl=300)
def load_mysql_dq_data():
    try:
        connector = MySQLConnector(MYSQL_CONFIG)
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
            WHERE execution_date >= DATE_SUB(NOW(), INTERVAL 168 HOUR)
            ORDER BY execution_date DESC
        """, ())
        connector.disconnect()
        
        df = pd.DataFrame(results, columns=[
            'check_id', 'check_type', 'table_name', 'execution_date', 
            'status', 'error_message'
        ])
        return df
    except Exception as e:
        st.error(f"Error loading MySQL data: {e}")
        return pd.DataFrame()

# Load data
pg_df = load_pg_dq_data()
mysql_df = load_mysql_dq_data()

# Filter data
if not pg_df.empty:
    pg_df = pg_df[pg_df['execution_date'] >= datetime.now() - timedelta(hours=hours_back)]
    if check_type_filter:
        pg_df = pg_df[pg_df['check_type'].isin(check_type_filter)]
    if status_filter:
        pg_df = pg_df[pg_df['status'].isin(status_filter)]

if not mysql_df.empty:
    mysql_df = mysql_df[mysql_df['execution_date'] >= datetime.now() - timedelta(hours=hours_back)]
    if check_type_filter:
        mysql_df = mysql_df[mysql_df['check_type'].isin(check_type_filter)]
    if status_filter:
        mysql_df = mysql_df[mysql_df['status'].isin(status_filter)]

# Metrics
col1, col2, col3, col4 = st.columns(4)

if not pg_df.empty:
    pg_passed = len(pg_df[pg_df['status'] == 'passed'])
    pg_failed = len(pg_df[pg_df['status'] == 'failed'])
    pg_error = len(pg_df[pg_df['status'] == 'error'])
    pg_total = len(pg_df)
    
    col1.metric("PostgreSQL Total Checks", pg_total)
    col2.metric("✅ Passed", pg_passed)
    col3.metric("❌ Failed", pg_failed)
    col4.metric("⚠️ Errors", pg_error)
else:
    col1.metric("PostgreSQL Total Checks", 0)
    col2.metric("✅ Passed", 0)
    col3.metric("❌ Failed", 0)
    col4.metric("⚠️ Errors", 0)

st.markdown("---")

# Charts
col1, col2 = st.columns(2)

with col1:
    st.subheader("PostgreSQL Check Status")
    if not pg_df.empty:
        status_counts = pg_df['status'].value_counts()
        st.bar_chart(status_counts)
    else:
        st.info("No PostgreSQL data available")

with col2:
    st.subheader("MySQL Check Status")
    if not mysql_df.empty:
        status_counts = mysql_df['status'].value_counts()
        st.bar_chart(status_counts)
    else:
        st.info("No MySQL data available")

st.markdown("---")

# Detailed results
col1, col2 = st.columns(2)

with col1:
    st.subheader("PostgreSQL Check Results")
    if not pg_df.empty:
        st.dataframe(
            pg_df[['check_type', 'table_name', 'status', 'execution_date', 'error_message']],
            use_container_width=True,
            hide_index=True
        )
    else:
        st.info("No PostgreSQL check results available")

with col2:
    st.subheader("MySQL Check Results")
    if not mysql_df.empty:
        st.dataframe(
            mysql_df[['check_type', 'table_name', 'status', 'execution_date', 'error_message']],
            use_container_width=True,
            hide_index=True
        )
    else:
        st.info("No MySQL check results available")

# Summary by check type
st.markdown("---")
st.subheader("Summary by Check Type")

if not pg_df.empty or not mysql_df.empty:
    summary_data = []
    
    if not pg_df.empty:
        for check_type in pg_df['check_type'].unique():
            type_df = pg_df[pg_df['check_type'] == check_type]
            summary_data.append({
                'Database': 'PostgreSQL',
                'Check Type': check_type,
                'Total': len(type_df),
                'Passed': len(type_df[type_df['status'] == 'passed']),
                'Failed': len(type_df[type_df['status'] == 'failed']),
                'Errors': len(type_df[type_df['status'] == 'error'])
            })
    
    if not mysql_df.empty:
        for check_type in mysql_df['check_type'].unique():
            type_df = mysql_df[mysql_df['check_type'] == check_type]
            summary_data.append({
                'Database': 'MySQL',
                'Check Type': check_type,
                'Total': len(type_df),
                'Passed': len(type_df[type_df['status'] == 'passed']),
                'Failed': len(type_df[type_df['status'] == 'failed']),
                'Errors': len(type_df[type_df['status'] == 'error'])
            })
    
    if summary_data:
        summary_df = pd.DataFrame(summary_data)
        st.dataframe(summary_df, use_container_width=True, hide_index=True)

# Auto-refresh
if st.sidebar.button("🔄 Refresh Data"):
    st.cache_data.clear()
    st.rerun()

# Auto-refresh toggle
auto_refresh = st.sidebar.checkbox("Auto-refresh (30s)", False)
if auto_refresh:
    import time
    time.sleep(30)
    st.rerun()

