drop table if exists s_psql_dds.d_status cascade;

create table s_psql_dds.d_status (
    id serial primary key,
    name varchar(50) not null unique
);

comment on table s_psql_dds.d_status is 'Справочник статусов';

