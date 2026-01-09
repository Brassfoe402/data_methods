drop table if exists s_psql_dds.t_dm_task cascade;

create table s_psql_dds.t_dm_task (
    id serial primary key,
    id_source integer not null,
    source_id integer not null,
    category_id integer not null,
    status_id integer not null,
    region_id integer not null,
    amount numeric(12,2) not null check (amount > 0),
    duration integer not null check (duration > 0),
    count integer not null check (count >= 0),
    created_at timestamp not null,
    updated_at timestamp not null,
    load_dttm timestamp default current_timestamp,
    constraint chk_dates check (created_at <= updated_at),
    constraint fk_source foreign key (source_id) references s_psql_dds.d_source(id),
    constraint fk_category foreign key (category_id) references s_psql_dds.d_category(id),
    constraint fk_status foreign key (status_id) references s_psql_dds.d_status(id),
    constraint fk_region foreign key (region_id) references s_psql_dds.d_region(id)
);

comment on table s_psql_dds.t_dm_task is 'Таблица фактов с идентификаторами справочников';

