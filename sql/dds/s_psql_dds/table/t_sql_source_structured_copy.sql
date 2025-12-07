drop table if exists s_psql_dds.t_sql_source_structured_copy cascade;

create table s_psql_dds.t_sql_source_structured_copy (
    id serial primary key,
    id_source integer unique not null,
    source varchar(50) not null,
    category varchar(50) not null,
    status varchar(50) not null,
    region varchar(50) not null,
    amount numeric(12,2) not null check (amount > 0),
    duration integer not null check (duration > 0),
    count integer not null check (count >= 0),
    created_at timestamp not null,
    updated_at timestamp not null,
    load_dttm timestamp default current_timestamp,
    constraint chk_dates check (created_at <= updated_at)
);