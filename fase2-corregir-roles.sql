select u.email, t.codigo, tm.rol, t.id as team_id
from auth.users u
left join public.team_members tm on tm.user_id = u.id
left join public.teams t on t.id = tm.team_id
order by u.email;

do $$
declare
  v_resp uuid;
  v_cont uuid;
  v_team_resp uuid;
  v_team_cont uuid;
begin
  select id into v_resp from auth.users where email = 'ozkareyez@gmail.com';
  select id into v_cont from auth.users where email = 'dumartuquerrez@italcol.com';
  select id into v_team_resp from public.teams where owner_id = v_resp limit 1;
  select team_id into v_team_cont from public.team_members where user_id = v_cont limit 1;

  if v_resp is null or v_cont is null or v_team_resp is null then
    raise exception 'Revisa los correos: falta el usuario o el equipo del responsable';
  end if;

  delete from public.team_members where user_id = v_cont;

  insert into public.team_members (team_id, user_id, email, rol)
  values (v_team_resp, v_cont, (select email from auth.users where id = v_cont), 'contador')
  on conflict (team_id, user_id) do update set rol = 'contador';

  if v_team_cont is not null and v_team_cont <> v_team_resp then
    if not exists (select 1 from public.sessions where team_id = v_team_cont)
       and not exists (select 1 from public.count_lines where team_id = v_team_cont)
       and not exists (select 1 from public.products where team_id = v_team_cont)
       and not exists (select 1 from public.erp_snapshots where team_id = v_team_cont) then
      delete from public.teams where id = v_team_cont;
    end if;
  end if;
end $$;

select u.email, t.codigo, tm.rol
from public.team_members tm
join auth.users u on u.id = tm.user_id
join public.teams t on t.id = tm.team_id
order by u.email;
