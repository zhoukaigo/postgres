BEGIN;
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'vchord_bm25') then
    create extension if not exists pg_tokenizer cascade;
    create extension if not exists vchord_bm25 cascade;
  end if;
end $$;
ROLLBACK;
