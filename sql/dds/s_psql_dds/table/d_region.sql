drop table if exists s_psql_dds.d_region cascade;

create table s_psql_dds.d_region (
    id serial primary key,
    name varchar(50) not null unique
);

comment on table s_psql_dds.d_region is 'Справочник регионов';


