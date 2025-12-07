drop table if exists s_psql_dds.t_sql_source_unstructured cascade;

create table s_psql_dds.t_sql_source_unstructured (
    id integer,
    source varchar(50),
    category varchar(50),
    status varchar(50),
    region varchar(50),
    amount numeric,
    duration integer,
    count integer,
    created_at timestamp,
    updated_at timestamp
);