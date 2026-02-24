BEGIN;
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_tokenizer') then
    create extension if not exists pg_tokenizer cascade;
  end if;
end $$;
ROLLBACK;
