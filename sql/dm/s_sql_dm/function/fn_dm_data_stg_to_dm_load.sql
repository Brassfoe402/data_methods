drop procedure if exists fn_dm_data_stg_to_dm_load;

delimiter //

create procedure fn_dm_data_stg_to_dm_load(
    in p_start_dt date,
    in p_end_dt date
)
begin
    declare v_inserted_rows int default 0;
    declare v_deleted_rows int default 0;
    declare v_error_msg varchar(255);
    declare exit handler for sqlexception
    begin
        get diagnostics condition 1
            v_error_msg = message_text;
        rollback;
        select 0 as processed_rows, concat('ERROR: ', sqlstate, ' - ', v_error_msg) as status;
    end;
    
    start transaction;
    
    -- Очистка данных за период в целевой таблице
    delete from t_dm_task
    where date(created_at) between p_start_dt and p_end_dt;
    
    set v_deleted_rows = row_count();
    
    -- Перекладка данных из staging в целевую таблицу
    insert into t_dm_task (
        id_source,
        source_id,
        category_id,
        status_id,
        region_id,
        amount,
        duration,
        count,
        created_at,
        updated_at,
        load_dttm
    )
    select 
        id_source,
        source_id,
        category_id,
        status_id,
        region_id,
        amount,
        duration,
        count,
        created_at,
        updated_at,
        load_dttm
    from t_dm_stg_task
    where date(created_at) between p_start_dt and p_end_dt;
    
    set v_inserted_rows = row_count();
    
    commit;
    
    select v_inserted_rows as processed_rows, 'SUCCESS' as status;
    
end //

delimiter ;

