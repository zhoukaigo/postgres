create extension if not exists pg_tokenizer cascade;
create extension if not exists vchord_bm25 cascade;

select extversion from pg_extension where extname = 'vchord_bm25';

select current_setting('search_path') like '%bm25_catalog%' as has_bm25_catalog;
