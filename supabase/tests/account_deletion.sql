begin;

-- The account deletion function deletes auth.users. Every app-owned table
-- with a user_id must disappear through a direct ON DELETE CASCADE reference.
do $$
declare
  v_table record;
  v_user uuid := '00000000-0000-0000-0000-000000000099';
  v_remaining boolean;
begin
  for v_table in
    select table_schema, table_name
      from information_schema.columns
      where table_schema = 'public' and column_name = 'user_id'
        and data_type = 'uuid'
  loop
    if not exists (
      select 1
        from pg_constraint as fk
        join pg_attribute as column_info
          on column_info.attrelid = fk.conrelid
          and column_info.attnum = fk.conkey[1]
        where fk.conrelid = format('%I.%I', v_table.table_schema,
          v_table.table_name)::regclass
          and fk.confrelid = 'auth.users'::regclass
          and fk.contype = 'f'
          and fk.confdeltype = 'c'
          and array_length(fk.conkey, 1) = 1
          and column_info.attname = 'user_id'
    ) then
      raise exception 'account deletion does not cascade to %.%',
        v_table.table_schema, v_table.table_name;
    end if;
  end loop;

  insert into auth.users (id) values (v_user);
  insert into public.user_goal_snapshots (user_id, goal_id, snapshot)
    values (v_user, 'delete-goal',
      '{"id":"delete-goal","completions":{},"restDays":[],"milestones":[]}'::jsonb);
  insert into public.user_daily_snapshots (user_id, snapshot)
    values (v_user, '{"version":1,"tasks":[],"notes":[]}'::jsonb);
  insert into public.game_wallets (user_id) values (v_user);
  delete from auth.users where id = v_user;

  for v_table in
    select table_schema, table_name
      from information_schema.columns
      where table_schema = 'public' and column_name = 'user_id'
        and data_type = 'uuid'
  loop
    execute format('select exists (select 1 from %I.%I where user_id = $1)',
      v_table.table_schema, v_table.table_name)
      into v_remaining using v_user;
    if v_remaining then
      raise exception 'account data remains in %.%',
        v_table.table_schema, v_table.table_name;
    end if;
  end loop;
end;
$$;

rollback;
