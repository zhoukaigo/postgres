BEGIN;
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'vchord') then
    create extension if not exists vchord cascade;
  end if;
end $$;
ROLLBACK;
