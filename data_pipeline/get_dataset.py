import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from pandas import DataFrame
import random

def get_dataset(num_records: int = 1000, seed: int = 42) -> pd.DataFrame:
    np.random.seed(seed)
    random.seed(seed)
    
    if seed is not None:
        base_date = datetime(2025, 1, 1)
        current_time_for_anomaly = base_date + timedelta(days=90) 
    else:
        current_time_for_anomaly = datetime.now()
        base_date = current_time_for_anomaly - timedelta(days=90)
    
    data = {
        'id': range(1, num_records + 1),
        'source': [random.choice(['API', 'WEB', 'MOBILE', 'BATCH', None]) for _ in range(num_records)],
        'category': [random.choice(['A', 'B', 'C', 'D', 'E', 'unknown', '']) for _ in range(num_records)],
        'status': [random.choice(['ACTIVE', 'INACTIVE', 'PENDING', 'CANCELLED', 'N/A', None]) for _ in range(num_records)],
        'region': [random.choice(['RU', 'EU', 'US', 'ASIA', 'OTHER', 'UNKNOWN', '']) for _ in range(num_records)],
        'amount': np.random.uniform(10, 10000, num_records).round(2),
        'duration': np.random.randint(1, 365, num_records, dtype=np.int64),
        'count': np.random.randint(0, 1000, num_records, dtype=np.int64),
        'created_at': [base_date + timedelta(days=int(x)) for x in np.random.uniform(0, 90, num_records)],
        'updated_at': [base_date + timedelta(days=int(x)) for x in np.random.uniform(0, 90, num_records)],
    }
    
    df = pd.DataFrame(data)
    
    def to_float_safe(x):
        try:
            return float(x)
        except Exception:
            return 0.0
    
    def to_int_safe(x):
        try:
            return int(x)
        except Exception:
            return 0

    anomaly_indices = np.random.choice(df.index, size=int(num_records * 0.2), replace=False)
    
    for idx in anomaly_indices:
        anomaly_type = random.choice(['null', 'negative', 'wrong_date', 'malformed', 'duplicate_id'])
        
        if anomaly_type == 'null':
            df.loc[idx, 'amount'] = None
        elif anomaly_type == 'negative':
            df.loc[idx, 'amount'] = -abs(to_float_safe(df.loc[idx, 'amount']))
            df.loc[idx, 'duration'] = -abs(to_int_safe(df.loc[idx, 'duration']))
        elif anomaly_type == 'wrong_date':
            df.loc[idx, 'created_at'] = current_time_for_anomaly + timedelta(days=30)
        elif anomaly_type == 'malformed':
            df.loc[idx, 'category'] = 'MALFORMED_VALUE'
        elif anomaly_type == 'duplicate_id':
            df.loc[idx, 'id'] = df.iloc[0]['id']
    
    if len(df) > 10:
        duplicate_rows = df.sample(n=int(num_records * 0.05))
        df = pd.concat([df, duplicate_rows], ignore_index=True)
    
    df = df.sort_values('id', ignore_index=True)
    
    return df
