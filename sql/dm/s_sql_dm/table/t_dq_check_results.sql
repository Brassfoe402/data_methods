drop table if exists t_dq_check_results;

create table t_dq_check_results (
    check_id int auto_increment primary key,
    check_type varchar(50) not null,
    table_name varchar(100) not null,
    execution_date datetime(6) default current_timestamp(6),
    status varchar(20) not null,
    error_message text
) engine=innodb default charset=utf8mb4 collate=utf8mb4_unicode_ci;

create index idx_dq_check_results_date on t_dq_check_results(execution_date);
create index idx_dq_check_results_status on t_dq_check_results(status);
create index idx_dq_check_results_type on t_dq_check_results(check_type);

