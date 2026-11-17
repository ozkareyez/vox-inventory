alter table public.count_lines
  add column if not exists bodega text,
  add column if not exists vencimiento text;

create index if not exists count_lines_session_activos_idx
  on public.count_lines (session_id, anulado);

select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'count_lines'
  and column_name in ('bodega', 'vencimiento', 'session_id', 'anulado')
order by column_name;

select tablename, policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('cycles', 'sessions', 'products', 'erp_snapshots', 'count_lines')
order by tablename, policyname;
