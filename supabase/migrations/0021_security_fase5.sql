-- ===============================================================
-- 0021_security_fase5.sql — Fase 5 (higiene) parte BD
--
--   [I-04] revoke EXECUTE de PUBLIC en las funciones del esquema private
--          (dejando el grant justo a `authenticated` en los helpers del RLS).
--   [I-05] ampliar la cobertura de auditoría (roles, system_config, cola) y
--          alargar la retención de los logs de 2 a 12 meses.
--
-- Como siempre: NO se editan migraciones aplicadas; esto solo añade
-- revoke/grant, funciones y triggers nuevos, y re-programa el cron existente.
-- ===============================================================


-- ===============================================================
-- [I-04] Menos superficie: las funciones de `private` no deben ser
-- invocables por cualquiera. Postgres concede EXECUTE a PUBLIC al crear una
-- función, así que hay que revocarlo explícitamente.
--
-- CLAVE (no romper el RLS): para LLAMAR a una función —aunque sea SECURITY
-- DEFINER— hace falta privilegio EXECUTE. Las policies RLS invocan
-- private.is_mega / is_principal / is_group_admin / current_user_group /
-- current_user_role EVALUADAS COMO el rol `authenticated` (0002_rls.sql:55-142,
-- 0013_waitlist.sql:61-64, etc.). Si revocáramos de PUBLIC sin volver a
-- concederlo a `authenticated`, TODAS las consultas bajo RLS fallarían con
-- "permission denied for function". Por eso: revoke de PUBLIC en TODAS, y grant
-- a `authenticated` SOLO en los 5 helpers que el RLS usa.
--
-- private.role_rank(text) y private.secure_rand_int(int) NO se conceden a
-- `authenticated`: solo las llaman funciones SECURITY DEFINER con owner=postgres
-- (role_rank -> profiles_guard 0017/0020; secure_rand_int -> run_sorteo 0018),
-- que se ejecutan como postgres (owner) y no necesitan el privilegio del
-- invocante. (secure_rand_int ya estaba revocada en 0018; se re-afirma aquí.)
-- ===============================================================

revoke execute on all functions in schema private from public;

grant execute on function private.current_user_role()        to authenticated;
grant execute on function private.current_user_group()       to authenticated;
grant execute on function private.is_mega()                  to authenticated;
grant execute on function private.is_principal()             to authenticated;
grant execute on function private.is_group_admin(uuid)       to authenticated;


-- ===============================================================
-- [I-05] Auditoría más completa + retención más larga.
--
-- Hasta ahora solo se auditaban las reservas (audit_reservations, 0003) y los
-- sorteos (run_sorteo/audit_sorteos_delete, 0018). Se añaden:
--   1) cambios de ROL en profiles,
--   2) cambios en system_config (sin volcar secretos),
--   3) movimientos en la cola reservation_waitlist,
-- y se ATRIBUYE la acción a 'service_role' cuando no hay usuario (cron / Edge
-- Functions con service_role / triggers sin JWT). Todo append-only e invisible
-- para los usuarios normales (solo audit_logs_select): no cambia ninguna UX.
--
-- Todas las funciones son SECURITY DEFINER (owner=postgres). B-01 (0020) NO
-- forzó FORCE RLS en audit_logs, así que el owner sigue insertando sin policy
-- de INSERT. Los triggers son AFTER y nunca abortan un write normal.
-- ===============================================================

-- Actor legible cuando no hay auth.uid() (service_role / cron / trigger interno).
create or replace function private.audit_actor()
returns text
language sql stable security definer set search_path = public
as $$
  select case when auth.uid() is null then 'service_role' else 'user' end;
$$;

revoke execute on function private.audit_actor() from public;


-- 1) Cambios de ROL en profiles ---------------------------------
create or replace function public.audit_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_logs (action, entity_type, entity_id, details, user_id)
  values (
    'ROLE_CHANGE', 'profile', new.id,
    jsonb_build_object(
      'old_role', old.role,
      'new_role', new.role,
      'actor', private.audit_actor()
    ),
    auth.uid()
  );
  return new;
end;
$$;

revoke execute on function public.audit_profile_role_change() from public;

drop trigger if exists trg_audit_profile_role on public.profiles;
create trigger trg_audit_profile_role
  after update of role on public.profiles
  for each row
  when (new.role is distinct from old.role)
  execute function public.audit_profile_role_change();


-- 2) Cambios en system_config (SIN secretos) --------------------
-- Registra solo qué claves cambiaron (old/new), excluyendo smtp_pass y
-- updated_at. entity_id queda NULL (system_config.id es el texto 'global').
create or replace function public.audit_system_config()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_changes jsonb;
begin
  select coalesce(
           jsonb_object_agg(
             k, jsonb_build_object('old', to_jsonb(old)->k, 'new', to_jsonb(new)->k)
           ),
           '{}'::jsonb)
    into v_changes
  from jsonb_object_keys(to_jsonb(new)) as k
  where k not in ('smtp_pass', 'updated_at')
    and (to_jsonb(old)->k) is distinct from (to_jsonb(new)->k);

  insert into public.audit_logs (action, entity_type, entity_id, details, user_id)
  values (
    'UPDATE', 'system_config', null,
    jsonb_build_object('id', new.id, 'changed', v_changes, 'actor', private.audit_actor()),
    auth.uid()
  );
  return new;
end;
$$;

revoke execute on function public.audit_system_config() from public;

drop trigger if exists trg_audit_system_config on public.system_config;
create trigger trg_audit_system_config
  after update on public.system_config
  for each row
  execute function public.audit_system_config();


-- 3) Movimientos en la cola reservation_waitlist ----------------
-- Alta y baja siempre; en UPDATE solo cuando cambia el estado (evita ruido de
-- los reordenamientos FIFO que no cambian status).
create or replace function public.audit_waitlist()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action  text;
  v_entity  uuid;
  v_details jsonb;
begin
  if tg_op = 'INSERT' then
    v_action := 'CREATE'; v_entity := new.id;
    v_details := jsonb_build_object('status', new.status);
  elsif tg_op = 'UPDATE' then
    v_action := 'STATUS_CHANGE'; v_entity := new.id;
    v_details := jsonb_build_object('old_status', old.status, 'new_status', new.status);
  else -- DELETE
    v_action := 'DELETE'; v_entity := old.id;
    v_details := jsonb_build_object('status', old.status);
  end if;

  insert into public.audit_logs (action, entity_type, entity_id, details, user_id)
  values (
    v_action, 'waitlist', v_entity,
    v_details || jsonb_build_object('actor', private.audit_actor()),
    auth.uid()
  );
  return coalesce(new, old);
end;
$$;

revoke execute on function public.audit_waitlist() from public;

drop trigger if exists trg_audit_waitlist_ins_del on public.reservation_waitlist;
create trigger trg_audit_waitlist_ins_del
  after insert or delete on public.reservation_waitlist
  for each row execute function public.audit_waitlist();

drop trigger if exists trg_audit_waitlist_status on public.reservation_waitlist;
create trigger trg_audit_waitlist_status
  after update of status on public.reservation_waitlist
  for each row
  when (new.status is distinct from old.status)
  execute function public.audit_waitlist();


-- 4) Retención: de 2 a 12 meses. cron.schedule con el MISMO nombre de job hace
--    upsert, así que re-programarlo aquí sustituye el de 0012 sin editarlo.
select cron.schedule(
  'purge-audit-logs',
  '0 3 * * *',
  $$ delete from public.audit_logs where created_at < now() - interval '12 months'; $$
);
