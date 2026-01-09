drop table if exists s_psql_dds.d_category cascade;

create table s_psql_dds.d_category (
    id serial primary key,
    name varchar(50) not null unique
);

comment on table s_psql_dds.d_category is 'Справочник категорий';

