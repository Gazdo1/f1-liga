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
