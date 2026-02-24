create extension if not exists pg_tokenizer cascade;

select extversion from pg_extension where extname = 'pg_tokenizer';

select current_setting('search_path') like '%tokenizer_catalog%' as has_tokenizer_catalog;
