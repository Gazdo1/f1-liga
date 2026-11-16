-- =====================================================================
--  Farby jazdcov a prepojenie účtu s jazdcom
-- =====================================================================
alter table public.players add column if not exists color text;
alter table public.players drop constraint if exists players_color_check;
alter table public.players add constraint players_color_check check (color is null or color ~ '^#[0-9a-fA-F]{6}$');
alter table public.profiles add column if not exists player_id bigint references public.players(id) on delete set null;
create unique index if not exists profiles_player_unique on public.profiles(player_id) where player_id is not null;

create or replace function public.my_profile()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('id', id, 'display_name', display_name, 'role', role, 'player_id', player_id)
  from profiles where id = auth.uid();
$$;

drop function if exists public.list_profiles();
create function public.list_profiles()
returns table (id uuid, display_name text, email text, role text, created_at timestamptz, player_id bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  perform _require('admin');
  return query select p.id, p.display_name, u.email::text, p.role, p.created_at, p.player_id
               from profiles p join auth.users u on u.id = p.id
               order by case p.role when 'pending' then 0 when 'admin' then 1 when 'editor' then 2 else 3 end, p.created_at;
end $$;

create or replace function public.set_user_player(p_user_id uuid, p_player_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require('admin');
  if p_player_id is not null then update profiles set player_id = null where player_id = p_player_id and id <> p_user_id; end if;
  update profiles set player_id = p_player_id where id = p_user_id;
end $$;

create or replace function public.set_my_color(p_color text)
returns void language plpgsql security definer set search_path = public as $$
declare pid bigint;
begin
  if not exists (select 1 from profiles where id = auth.uid() and role in ('viewer','editor','admin')) then
    raise exception 'Na toto nemáš oprávnenie' using errcode = '42501';
  end if;
  select player_id into pid from profiles where id = auth.uid();
  if pid is null then raise exception 'Tvoj účet ešte nie je priradený k jazdcovi, povedz adminovi'; end if;
  update players set color = p_color where id = pid;
end $$;

create or replace function public.set_player_color(p_player_id bigint, p_color text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require('editor');
  update players set color = p_color where id = p_player_id;
end $$;

revoke execute on function public.list_profiles(), public.set_user_player(uuid, bigint), public.set_my_color(text), public.set_player_color(bigint, text) from public, anon;
grant execute on function public.list_profiles(), public.set_user_player(uuid, bigint), public.set_my_color(text), public.set_player_color(bigint, text) to authenticated;
