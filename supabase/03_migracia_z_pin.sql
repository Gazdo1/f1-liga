-- =====================================================================
--  Migrácia: PIN  →  prihlásenie + role
--  Spusti IBA ak máš staršiu verziu databázy s PIN-om.
--  Potom spusti znova 01_schema.sql (dáta ostanú nedotknuté).
-- =====================================================================
drop function if exists public.verify_pin(text);
drop function if exists public.change_pin(text, text);
drop function if exists public.save_race_results(text, bigint, jsonb);
drop function if exists public.clear_race_results(text, bigint);
drop function if exists public.add_player(text, text);
drop function if exists public.update_player(text, bigint, text, boolean);
drop function if exists public.create_season(text, text, bigint, boolean);
drop function if exists public.update_season(text, bigint, text, int[], int, boolean);
drop function if exists public.add_race(text, bigint, text);
drop function if exists public.update_race(text, bigint, text, date);
drop function if exists public.delete_race(text, bigint);
drop function if exists public.set_postponements(text, bigint, bigint, int);
drop function if exists public._check_pin(text);
drop table if exists public.app_settings;
