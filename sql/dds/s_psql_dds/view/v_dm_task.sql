drop view if exists s_psql_dds.v_dm_task cascade;

create view s_psql_dds.v_dm_task as
select 
    t.id,
    t.id_source,
    t.source_id,
    t.category_id,
    t.status_id,
    t.region_id,
    t.amount,
    t.duration,
    t.count,
    t.created_at,
    t.updated_at,
    t.load_dttm
from s_psql_dds.t_dm_task t;

comment on view s_psql_dds.v_dm_task is 'Витрина данных на основе таблицы t_dm_task';


