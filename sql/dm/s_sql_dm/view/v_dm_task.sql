drop view if exists v_dm_task;

create view v_dm_task as
select 
    id,
    id_source,
    source_id,
    category_id,
    status_id,
    region_id,
    amount,
    duration,
    count,
    created_at,
    updated_at,
    load_dttm
from t_dm_task;

