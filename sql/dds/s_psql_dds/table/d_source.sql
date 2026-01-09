drop table if exists s_psql_dds.d_source cascade;

create table s_psql_dds.d_source (
    id serial primary key,
    name varchar(50) not null unique
);

comment on table s_psql_dds.d_source is 'Справочник источников данных';


