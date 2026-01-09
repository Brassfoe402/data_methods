drop table if exists s_psql_dds.t_dq_check_results cascade;

create table s_psql_dds.t_dq_check_results (
    check_id serial primary key,
    check_type varchar(50) not null,
    table_name varchar(100) not null,
    execution_date timestamp(6) default current_timestamp,
    status varchar(20) not null,
    error_message text
);

comment on table s_psql_dds.t_dq_check_results is 'Таблица для хранения результатов проверок качества данных';

create index idx_dq_check_results_date on s_psql_dds.t_dq_check_results(execution_date);
create index idx_dq_check_results_status on s_psql_dds.t_dq_check_results(status);


