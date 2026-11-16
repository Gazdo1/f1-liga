-- =====================================================================
--  F1 Liga – databázová schéma pre Supabase
--  Spusti celé v Supabase → SQL Editor → New query → Run.
--  Potom spusti 02_data.sql (prenesené dáta z Excelu).
-- =====================================================================

-- Prístup: súkromná liga. Dáta vidia iba schválení členovia (role viewer,
-- editor, admin). Nový účet čaká na schválenie (pending). PRVÝ zaregistrovaný
-- používateľ sa automaticky stane adminom a ostatných schvaľuje v appke.
-- Posledná časť súboru (zo 04_clenovia.sql) sprísňuje čítanie na členov.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
--  Tabuľky
-- ---------------------------------------------------------------------
create table if not exists public.players (
  id          bigint generated always as identity primary key,
  name        text not null unique check (length(trim(name)) > 0),
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.seasons (
  id                 bigint generated always as identity primary key,
  name               text not null,
  sort_order         int  not null default 0,
  points_scheme      int[] not null default '{25,18,15,12,10,8,6,4,2,1}',
  fastest_lap_bonus  int  not null default 0 check (fastest_lap_bonus >= 0),
  is_current         boolean not null default false,
  created_at         timestamptz not null default now()
);
-- iba jedna "aktuálna" sezóna
create unique index if not exists seasons_one_current on public.seasons (is_current) where is_current;

create table if not exists public.races (
  id          bigint generated always as identity primary key,
  season_id   bigint not null references public.seasons(id) on delete cascade,
  round       int    not null check (round > 0),
  track       text   not null,
  race_date   date,
  unique (season_id, round)
);

create table if not exists public.results (
  id           bigint generated always as identity primary key,
  race_id      bigint not null references public.races(id) on delete cascade,
  player_id    bigint not null references public.players(id) on delete restrict,
  position     int    not null check (position between 1 and 30),
  fastest_lap  boolean not null default false,
  unique (race_id, position),
  unique (race_id, player_id)
);
create index if not exists results_player_idx on public.results(player_id);

-- "Odklady" – počet odložených pretekov hráča v sezóne
create table if not exists public.postponements (
  season_id  bigint not null references public.seasons(id) on delete cascade,
  player_id  bigint not null references public.players(id) on delete cascade,
  count      int    not null default 0 check (count >= 0),
  primary key (season_id, player_id)
);

-- Profily používateľov a ich role
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text not null,
  role          text not null default 'viewer' check (role in ('viewer','editor','admin')),
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
--  Prístupové práva: každý môže ČÍTAŤ, zapisovať sa dá IBA cez funkcie s PIN-om
-- ---------------------------------------------------------------------
alter table public.players       enable row level security;
alter table public.seasons       enable row level security;
alter table public.races         enable row level security;
alter table public.results       enable row level security;
alter table public.postponements enable row level security;
alter table public.profiles      enable row level security;   -- žiadna policy = iba cez funkcie
revoke all on public.profiles from anon, authenticated;

drop policy if exists "public read" on public.players;
drop policy if exists "public read" on public.seasons;
drop policy if exists "public read" on public.races;
drop policy if exists "public read" on public.results;
drop policy if exists "public read" on public.postponements;
create policy "public read" on public.players       for select to anon, authenticated using (true);
create policy "public read" on public.seasons       for select to anon, authenticated using (true);
create policy "public read" on public.races         for select to anon, authenticated using (true);
create policy "public read" on public.results       for select to anon, authenticated using (true);
create policy "public read" on public.postponements for select to anon, authenticated using (true);

grant usage on schema public to anon, authenticated;
revoke all on public.players, public.seasons, public.races, public.results,
              public.postponements from anon, authenticated;
grant select on public.players, public.seasons, public.races, public.results,
                public.postponements to anon, authenticated;

-- ---------------------------------------------------------------------
--  Používatelia a role
-- ---------------------------------------------------------------------
-- Nový používateľ dostane profil. Prvý vôbec = admin, ostatní = viewer.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, role)
  values (new.id,
          coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''), split_part(new.email, '@', 1)),
          case when exists (select 1 from public.profiles where role = 'admin') then 'viewer' else 'admin' end)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select role from profiles where id = auth.uid()), 'anon');
$$;

create or replace function public._require(p_min text)
returns void language plpgsql stable security definer set search_path = public as $$
declare r text := my_role();
begin
  if r = 'anon' then raise exception 'Musíš byť prihlásený' using errcode = '42501'; end if;
  if (p_min = 'editor' and r not in ('editor','admin')) or (p_min = 'admin' and r <> 'admin') then
    raise exception 'Na toto nemáš oprávnenie' using errcode = '42501';
  end if;
end $$;

create or replace function public.my_profile()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('id', id, 'display_name', display_name, 'role', role)
  from profiles where id = auth.uid();
$$;

create or replace function public.update_my_name(p_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require('viewer');
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'Meno nesmie byť prázdne'; end if;
  update profiles set display_name = trim(p_name) where id = auth.uid();
end $$;

create or replace function public.list_profiles()
returns table (id uuid, display_name text, email text, role text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  perform _require('admin');
  return query select p.id, p.display_name, u.email::text, p.role, p.created_at
               from profiles p join auth.users u on u.id = p.id
               order by case p.role when 'admin' then 0 when 'editor' then 1 else 2 end, p.created_at;
end $$;

create or replace function public.set_user_role(p_user_id uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require('admin');
  if p_role not in ('viewer','editor','admin') then raise exception 'Neplatná rola'; end if;
  if p_user_id = auth.uid() then raise exception 'Vlastnú rolu si zmeniť nemôžeš'; end if;
  update profiles set role = p_role where id = p_user_id;
end $$;

-- ---------------------------------------------------------------------
--  Zápis dát (editor / admin)
-- ---------------------------------------------------------------------
-- Uloží (prepíše) kompletné výsledky jedného závodu.
-- p_results = [{"player_id": 1, "position": 1, "fastest_lap": false}, ...]
create or replace function public.save_race_results(p_race_id bigint, p_results jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require('editor');
  if not exists (select 1 from races where id = p_race_id) then raise exception 'Závod neexistuje'; end if;
  if jsonb_typeof(p_results) <> 'array' then raise exception 'Neplatné výsledky'; end if;
  if (select count(*) filter (where (e->>'fastest_lap')::boolean) from jsonb_array_elements(p_results) e) > 1 then
    raise exception 'Najrýchlejšie kolo môže mať iba jeden jazdec';
  end if;
  delete from results where race_id = p_race_id;
  insert into results (race_id, player_id, position, fastest_lap)
  select p_race_id, (e->>'player_id')::bigint, (e->>'position')::int, coalesce((e->>'fastest_lap')::boolean, false)
  from jsonb_array_elements(p_results) e;
end $$;

create or replace function public.clear_race_results(p_race_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require('editor');
  delete from results where race_id = p_race_id;
end $$;

create or replace function public.add_player(p_name text)
returns bigint language plpgsql security definer set search_path = public as $$
declare new_id bigint;
begin
  perform _require('editor');
  insert into players (name) values (trim(p_name)) returning id into new_id;
  return new_id;
end $$;

create or replace function public.update_player(p_player_id bigint, p_name text, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require('editor');
  update players set name = trim(p_name), active = p_active where id = p_player_id;
end $$;

create or replace function public.add_race(p_season_id bigint, p_track text)
returns bigint language plpgsql security definer set search_path = public as $$
declare new_id bigint;
begin
  perform _require('editor');
  insert into races (season_id, round, track)
  values (p_season_id, coalesce((select max(round) from races where season_id = p_season_id), 0) + 1, trim(p_track))
  returning id into new_id;
  return new_id;
end $$;

create or replace function public.update_race(p_race_id bigint, p_track text, p_race_date date)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require('editor');
  update races set track = trim(p_track), race_date = p_race_date where id = p_race_id;
end $$;

create or replace function public.delete_race(p_race_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare s bigint; r int;
begin
  perform _require('editor');
  delete from races where id = p_race_id returning season_id, round into s, r;
  if s is null then return; end if;
  -- prečíslovanie kôl, aby nevznikla diera (cez dočasný posun kvôli unique)
  update races set round = round + 10000 where season_id = s and round > r;
  update races set round = round - 10001 where season_id = s and round > 10000;
end $$;

create or replace function public.set_postponements(p_season_id bigint, p_player_id bigint, p_count int)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require('editor');
  insert into postponements (season_id, player_id, count) values (p_season_id, p_player_id, greatest(p_count, 0))
  on conflict (season_id, player_id) do update set count = excluded.count;
end $$;

-- Sezóny – iba admin
create or replace function public.create_season(p_name text, p_copy_from_season bigint, p_make_current boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare new_id bigint; src seasons%rowtype;
begin
  perform _require('admin');
  select * into src from seasons where id = p_copy_from_season;
  if p_make_current then update seasons set is_current = false where is_current; end if;
  insert into seasons (name, sort_order, points_scheme, fastest_lap_bonus, is_current)
  values (trim(p_name), coalesce((select max(sort_order) from seasons), 0) + 1,
          coalesce(src.points_scheme, '{25,18,15,12,10,8,6,4,2,1}'), coalesce(src.fastest_lap_bonus, 0), p_make_current)
  returning id into new_id;
  if p_copy_from_season is not null then
    insert into races (season_id, round, track) select new_id, round, track from races where season_id = p_copy_from_season;
  end if;
  return new_id;
end $$;

create or replace function public.update_season(p_season_id bigint, p_name text, p_points_scheme int[],
                                                p_fastest_lap_bonus int, p_is_current boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require('admin');
  if p_is_current then update seasons set is_current = false where is_current and id <> p_season_id; end if;
  update seasons set name = trim(p_name), points_scheme = p_points_scheme,
                     fastest_lap_bonus = p_fastest_lap_bonus, is_current = p_is_current
  where id = p_season_id;
end $$;

-- práva na funkcie: anonym nesmie nič, prihlásený volá, funkcia si overí rolu
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public._require(text) from public, anon, authenticated;
revoke execute on function
  public.my_role(), public.my_profile(), public.update_my_name(text), public.list_profiles(),
  public.set_user_role(uuid, text), public.save_race_results(bigint, jsonb), public.clear_race_results(bigint),
  public.add_player(text), public.update_player(bigint, text, boolean), public.add_race(bigint, text),
  public.update_race(bigint, text, date), public.delete_race(bigint), public.set_postponements(bigint, bigint, int),
  public.create_season(text, bigint, boolean), public.update_season(bigint, text, int[], int, boolean)
from public, anon;
grant execute on function
  public.my_role(), public.my_profile(), public.update_my_name(text), public.list_profiles(),
  public.set_user_role(uuid, text), public.save_race_results(bigint, jsonb), public.clear_race_results(bigint),
  public.add_player(text), public.update_player(bigint, text, boolean), public.add_race(bigint, text),
  public.update_race(bigint, text, date), public.delete_race(bigint), public.set_postponements(bigint, bigint, int),
  public.create_season(text, bigint, boolean), public.update_season(bigint, text, int[], int, boolean)
to authenticated;

-- =====================================================================
--  Súkromná liga: dáta vidia iba schválení členovia.
--  Nový účet = "pending" (čaká na schválenie), admin ho schváli v appke.
-- =====================================================================
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('pending','viewer','editor','admin'));
alter table public.profiles alter column role set default 'pending';

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, role)
  values (new.id,
          coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''), split_part(new.email, '@', 1)),
          case when exists (select 1 from public.profiles where role = 'admin') then 'pending' else 'admin' end)
  on conflict (id) do nothing;
  return new;
end $$;

create or replace function public.is_member()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role in ('viewer','editor','admin'));
$$;
revoke execute on function public.is_member() from public, anon;
grant execute on function public.is_member() to authenticated;

-- čítanie iba pre členov
drop policy if exists "public read" on public.players;
drop policy if exists "public read" on public.seasons;
drop policy if exists "public read" on public.races;
drop policy if exists "public read" on public.results;
drop policy if exists "public read" on public.postponements;
drop policy if exists "members read" on public.players;
drop policy if exists "members read" on public.seasons;
drop policy if exists "members read" on public.races;
drop policy if exists "members read" on public.results;
drop policy if exists "members read" on public.postponements;
create policy "members read" on public.players       for select to authenticated using (public.is_member());
create policy "members read" on public.seasons       for select to authenticated using (public.is_member());
create policy "members read" on public.races         for select to authenticated using (public.is_member());
create policy "members read" on public.results       for select to authenticated using (public.is_member());
create policy "members read" on public.postponements for select to authenticated using (public.is_member());
revoke all on public.players, public.seasons, public.races, public.results, public.postponements from anon;
grant select on public.players, public.seasons, public.races, public.results, public.postponements to authenticated;

create or replace function public.list_profiles()
returns table (id uuid, display_name text, email text, role text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  perform _require('admin');
  return query select p.id, p.display_name, u.email::text, p.role, p.created_at
               from profiles p join auth.users u on u.id = p.id
               order by case p.role when 'pending' then 0 when 'admin' then 1 when 'editor' then 2 else 3 end, p.created_at;
end $$;

create or replace function public.set_user_role(p_user_id uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require('admin');
  if p_role not in ('pending','viewer','editor','admin') then raise exception 'Neplatná rola'; end if;
  if p_user_id = auth.uid() then raise exception 'Vlastnú rolu si zmeniť nemôžeš'; end if;
  update profiles set role = p_role where id = p_user_id;
end $$;

-- ===== zo 05_farby.sql =====
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
