create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users(id) on delete cascade,
  codigo text not null unique,
  nombre text not null default 'Equipo',
  creada_en timestamptz not null default now()
);

create table if not exists public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  email text,
  rol text not null default 'contador' check (rol in ('owner','contador')),
  primary key (team_id, user_id)
);

create index if not exists team_members_user_idx on public.team_members(user_id);

alter table public.cycles add column if not exists team_id uuid references public.teams(id) on delete cascade;
alter table public.sessions add column if not exists team_id uuid references public.teams(id) on delete cascade;
alter table public.products add column if not exists team_id uuid references public.teams(id) on delete cascade;
alter table public.erp_snapshots add column if not exists team_id uuid references public.teams(id) on delete cascade;
alter table public.count_lines add column if not exists team_id uuid references public.teams(id) on delete cascade;
alter table public.count_lines add column if not exists creado_por uuid references auth.users(id);
alter table public.count_lines add column if not exists bodega text;
alter table public.count_lines add column if not exists vencimiento text;

insert into public.teams (owner_id, codigo)
select o.owner_id, upper(substr(replace(gen_random_uuid()::text,'-',''),1,6))
from (
  select owner_id from public.sessions where owner_id is not null
  union
  select owner_id from public.cycles where owner_id is not null
  union
  select owner_id from public.products where owner_id is not null
) o
where not exists (select 1 from public.teams t where t.owner_id = o.owner_id);

insert into public.team_members (team_id, user_id, rol)
select id, owner_id, 'owner' from public.teams
on conflict do nothing;

update public.cycles c set team_id = t.id from public.teams t where t.owner_id = c.owner_id and c.team_id is null;
update public.sessions s set team_id = t.id from public.teams t where t.owner_id = s.owner_id and s.team_id is null;
update public.products p set team_id = t.id from public.teams t where t.owner_id = p.owner_id and p.team_id is null;
update public.erp_snapshots e set team_id = s.team_id from public.sessions s where s.id = e.session_id and e.team_id is null;
update public.count_lines l set team_id = s.team_id from public.sessions s where s.id = l.session_id and l.team_id is null;
update public.count_lines set creado_por = owner_id where creado_por is null and owner_id is not null;

do $$
begin
  alter table public.cycles add constraint cycles_team_semana_key unique (team_id, semana_inicio);
exception when duplicate_object then null; end $$;

do $$
begin
  alter table public.sessions add constraint sessions_team_fecha_key unique (team_id, fecha);
exception when duplicate_object then null; end $$;

do $$
begin
  alter table public.products add constraint products_team_codigo_key unique (team_id, codigo_erp);
exception when duplicate_object then null; end $$;

create or replace function public.user_team_ids()
returns setof uuid language sql stable security definer set search_path=public
as $$ select team_id from public.team_members where user_id = auth.uid() $$;

revoke all on function public.user_team_ids() from public;
grant execute on function public.user_team_ids() to authenticated;

create or replace function public.create_team(p_codigo text, p_email text)
returns public.teams language plpgsql security definer set search_path=public
as $$
declare v public.teams;
begin
  if p_codigo is null or length(trim(p_codigo)) <> 6 then
    raise exception 'El código debe tener 6 caracteres';
  end if;
  insert into public.teams (owner_id, codigo)
  values (auth.uid(), upper(trim(p_codigo)))
  returning * into v;
  insert into public.team_members (team_id, user_id, email, rol)
  values (v.id, auth.uid(), p_email, 'owner');
  return v;
end $$;

create or replace function public.join_team(p_codigo text, p_email text)
returns public.teams language plpgsql security definer set search_path=public
as $$
declare v public.teams;
begin
  select * into v from public.teams where codigo = upper(trim(p_codigo));
  if not found then
    raise exception 'No hay un equipo con ese código';
  end if;
  insert into public.team_members (team_id, user_id, email, rol)
  values (v.id, auth.uid(), p_email, 'contador')
  on conflict (team_id, user_id) do update set email = excluded.email;
  return v;
end $$;

grant execute on function public.create_team(text,text) to authenticated;
grant execute on function public.join_team(text,text) to authenticated;

do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname from pg_policies
    where schemaname = 'public'
      and tablename in ('cycles','sessions','products','erp_snapshots','count_lines','teams','team_members')
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.cycles enable row level security;
alter table public.sessions enable row level security;
alter table public.products enable row level security;
alter table public.erp_snapshots enable row level security;
alter table public.count_lines enable row level security;

create policy teams_sel on public.teams for select to authenticated
  using (owner_id = auth.uid() or id in (select public.user_team_ids()));
create policy teams_ins on public.teams for insert to authenticated
  with check (owner_id = auth.uid());
create policy teams_upd on public.teams for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy members_sel on public.team_members for select to authenticated
  using (team_id in (select public.user_team_ids()));
create policy members_ins on public.team_members for insert to authenticated
  with check (user_id = auth.uid() and team_id in (select public.user_team_ids()));

create policy cycles_all on public.cycles for all to authenticated
  using (team_id in (select public.user_team_ids()))
  with check (team_id in (select public.user_team_ids()));
create policy sessions_all on public.sessions for all to authenticated
  using (team_id in (select public.user_team_ids()))
  with check (team_id in (select public.user_team_ids()));
create policy products_all on public.products for all to authenticated
  using (team_id in (select public.user_team_ids()))
  with check (team_id in (select public.user_team_ids()));
create policy erp_snapshots_all on public.erp_snapshots for all to authenticated
  using (team_id in (select public.user_team_ids()))
  with check (team_id in (select public.user_team_ids()));
create policy count_lines_all on public.count_lines for all to authenticated
  using (team_id in (select public.user_team_ids()))
  with check (team_id in (select public.user_team_ids()));

select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('teams','team_members','cycles','sessions','products','erp_snapshots','count_lines')
  and column_name in ('team_id','codigo','rol','email','creado_por','bodega','vencimiento')
order by table_name, column_name;

select tablename, policyname, cmd from pg_policies
where schemaname = 'public'
  and tablename in ('teams','team_members','cycles','sessions','products','erp_snapshots','count_lines')
order by tablename, policyname;
