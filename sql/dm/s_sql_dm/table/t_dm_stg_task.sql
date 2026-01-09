drop table if exists t_dm_stg_task;

create table t_dm_stg_task (
    id int auto_increment primary key,
    id_source int not null,
    source_id int not null,
    category_id int not null,
    status_id int not null,
    region_id int not null,
    amount decimal(12,2) not null check (amount > 0),
    duration int not null check (duration > 0),
    count int not null check (count >= 0),
    created_at timestamp not null,
    updated_at timestamp not null,
    load_dttm timestamp default current_timestamp,
    constraint chk_dates check (created_at <= updated_at)
) engine=innodb default charset=utf8mb4 collate=utf8mb4_unicode_ci;

