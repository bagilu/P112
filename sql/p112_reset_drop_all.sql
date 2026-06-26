-- P112 reset script
-- Drops previous p112_ lowercase tables/functions and current TblP112 quoted tables/functions.
-- Use only during development or when you want a clean reinstall.

begin;

-- Drop p112 functions first.
do $$
declare r record;
begin
  for r in
    select n.nspname as schema_name, p.proname as function_name, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'p112\_%' escape '\'
  loop
    execute format('drop function if exists %I.%I(%s) cascade', r.schema_name, r.function_name, r.args);
  end loop;
end $$;

-- Drop prior lowercase p112_ tables.
do $$
declare r record;
begin
  for r in
    select schemaname, tablename
    from pg_tables
    where schemaname = 'public' and tablename like 'p112\_%' escape '\'
  loop
    execute format('drop table if exists %I.%I cascade', r.schemaname, r.tablename);
  end loop;
end $$;

-- Drop current quoted TblP112 tables.
do $$
declare r record;
begin
  for r in
    select schemaname, tablename
    from pg_tables
    where schemaname = 'public' and tablename like 'TblP112%'
  loop
    execute format('drop table if exists %I.%I cascade', r.schemaname, r.tablename);
  end loop;
end $$;

commit;
