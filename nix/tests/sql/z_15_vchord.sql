create extension if not exists vector;
create extension if not exists vchord cascade;

select extversion from pg_extension where extname = 'vchord';

select amname from pg_am where amname in ('vchordg', 'vchordrq') order by amname;
