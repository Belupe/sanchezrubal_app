-- ===============================================================
-- 0020_security_fase4_bajos.sql — Fase 4 (fallos BAJOS) parte BD
--
-- Agrupa los dos fixes de la Fase 4 que tocan la base de datos:
--   [B-01] FORCE ROW LEVEL SECURITY en las tablas donde es seguro.
--   [B-02] profiles_update_self dejaba al usuario cambiar su propio email
--          (envenenamiento de identidad de admin-users) -> se cierra en
--          profiles_guard y el email legítimo se sincroniza desde auth.users.
--
-- Principio de siempre: NO se editan migraciones ya aplicadas; esto solo
-- añade ALTERs y CREATE OR REPLACE nuevos.
-- ===============================================================


-- ===============================================================
-- [B-01] FORCE ROW LEVEL SECURITY
--
-- 0001:289-302 solo hizo ENABLE: el owner `postgres` sigue SALTANDO el RLS
-- (no es superuser ni BYPASSRLS en Supabase; por eso 0017 se apoya en ello).
-- Aquí forzamos RLS SOLO en las tablas cuyo acceso NO depende de ese bypass
-- del owner vía SECURITY DEFINER / vista DEFINER / pg_cron.
--
-- CLAVE (corregido tras revisión adversarial): las policies son ROLE-SCOPED
-- (`to authenticated`). Un objeto SECURITY DEFINER con owner=postgres corre
-- con current_user=postgres. Bajo FORCE, ese postgres queda sujeto al RLS y
-- NINGUNA policy `to authenticated` le aplica -> deny por defecto. Por eso una
-- tabla escrita/leída por un DEFINER owner NO puede forzarse aunque "tenga una
-- policy": la policy no aplica a postgres. Solo se fuerzan tablas de acceso
-- 100% cliente (donde FORCE es un no-op inocuo de defensa en profundidad).
-- service_role conserva BYPASSRLS (0011), así que FORCE no afecta a las Edge
-- Functions.
-- ===============================================================

-- Tablas de acceso 100% cliente (ningún DEFINER/vista/cron owner las lee o
-- escribe). Las vistas de ocupación (0017:174-204) solo leen reservations/
-- reservation_waitlist, no estas. FORCE-safe (no-op de defensa en profundidad):
alter table public.properties              force row level security;
alter table public.family_groups           force row level security;
alter table public.announcements           force row level security;
alter table public.announcement_properties force row level security;
alter table public.notification_templates  force row level security;
alter table public.notification_settings   force row level security;
alter table public.device_tokens           force row level security;
alter table public.out_reports             force row level security;

-- ---------------------------------------------------------------
-- EXCLUIDAS de FORCE (romperían función visible). NO forzar:
--
--  * public.sorteos
--      Su único escritor es public.run_sorteo (0018:322, SECURITY DEFINER,
--      owner postgres), que hace `insert into public.sorteos` con
--      current_user=postgres (NO 'authenticated'). La policy sorteos_insert
--      (0002:206) es `for insert TO authenticated`. Bajo FORCE, postgres queda
--      sujeto al RLS y ninguna policy le aplica -> el INSERT se DENIEGA ->
--      run_sorteo aborta -> los sorteos dejan de funcionar.
--
--  * public.reservations, public.reservation_waitlist
--      Las vistas de ocupación DEFINER calendar_occupancy / waitlist_occupancy
--      (0017:174-204, owner postgres, security_invoker=false) leen TODAS las
--      filas gracias a que el owner NO está sujeto al RLS -> FORCE rompería el
--      calendario y la cola compartidos. Además promote_waitlist_on_cancel
--      (0018:152), enforce_* y seal_* (DEFINER) leen/escriben aquí como owner.
--
--  * public.profiles
--      private.current_user_role / current_user_group / is_mega / is_principal
--      / is_group_admin (0004, DEFINER owner) hacen `select ... from
--      public.profiles` SALTANDO el RLS: son la espina dorsal de TODAS las
--      policies. Con FORCE ese SELECT interno queda sujeto a profiles_select
--      (0002:54) -> is_principal() -> current_user_role() -> vuelve a leer
--      profiles -> recursión infinita. handle_new_user (0001:264 INSERT) y
--      seal_* (0018 SELECT) también dependen del bypass del owner.
--
--  * public.system_config
--      enforce_max_reservation_days (0018), enforce_waitlist_rules (0018) y
--      promote_waitlist_on_cancel (0018) son DEFINER (owner postgres) y hacen
--      `select ... from public.system_config`. Con FORCE, la policy
--      system_config_all (0002:141, solo is_mega() y `to authenticated`) no
--      aplica a postgres -> v_min/v_cap = NULL -> se saltarían SILENCIOSAMENTE
--      el mínimo y el tope máximo de días (regresión de M-04).
--
--  * public.audit_logs
--      audit_reservations (0003), run_sorteo (0018) y audit_sorteos_delete
--      (0018) INSERTAN como DEFINER owner y NO existe policy de INSERT (0002
--      solo crea audit_logs_select). Con FORCE el INSERT se denegaría -> el
--      trigger aborta -> fallarían TODAS las altas/bajas/ediciones de reservas
--      y la ejecución de sorteos. Además el cron 'purge-audit-logs' (0012,
--      DELETE como postgres) no tiene policy de DELETE -> la purga quedaría
--      silenciosamente inerte.
--
--  * public.sorteo_resultados
--      0018:393 ELIMINÓ la policy sorteo_resultados_write (diseño append-only);
--      ahora SOLO existe policy de SELECT (0002:213). El único alta es
--      run_sorteo (0018:368, DEFINER owner postgres). Con FORCE el INSERT no
--      encontraría ninguna policy aplicable al rol postgres -> run_sorteo
--      abortaría y los sorteos dejarían de funcionar.
-- ---------------------------------------------------------------


-- ===============================================================
-- [B-02] Anti-envenenamiento del email del propio perfil
--
-- La policy profiles_update_self (0002_rls.sql:58-59) permite al propio usuario
-- UPDATE de su fila con `using/with check (id = auth.uid())`, sin restringir
-- columnas. El techo de rol/grupo ya lo frena profiles_guard (0017), pero
-- `email` quedaba libre: un MEMBER podía `update profiles set email='<email de
-- un admin>' where id=auth.uid()` por PostgREST directo. Como admin-users
-- enlaza usuarios por email, eso es envenenamiento de identidad.
--
--  (1) Ampliar profiles_guard(): un NO-admin tampoco cambia 'email'
--      (new.email := old.email, en la misma rama que revierte role/grupo).
--  (2) El cambio LEGÍTIMO de email se propaga desde auth.users cuando GoTrue
--      confirma el nuevo correo: trigger DEFINER AFTER UPDATE OF email sobre
--      auth.users que sincroniza public.profiles.email. Corre en el contexto
--      de GoTrue (sin JWT de usuario => auth.uid() NULL), así que profiles_guard
--      hace bypass igual que handle_new_user (0016).
-- ===============================================================

-- (1) profiles_guard AMPLIADO. Se copia íntegro el cuerpo de 0017 y SOLO se
--     añade `new.email := old.email;` en la rama de NO-admin. El techo de rol
--     del PRINCIPAL_ADMIN, el bypass de service_role (auth.uid() NULL) y MEGA
--     sin techo quedan IDÉNTICOS.
create or replace function public.profiles_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_rank int;
begin
  -- service_role / triggers internos (Edge Functions): confianza total.
  if auth.uid() is null then
    return new;
  end if;

  -- No-admins: no pueden tocar su rol, su grupo NI su email (se revierten).
  if not private.is_principal() then
    new.role := old.role;
    new.family_group_id := old.family_group_id;
    new.email := old.email;   -- [B-02] anti-envenenamiento de admin-users
    return new;
  end if;

  -- MEGA_ADMIN: sin techo (gestiona cualquier rol, incl. otro MEGA_ADMIN).
  if private.is_mega() then
    return new;
  end if;

  -- PRINCIPAL_ADMIN: TECHO DE ROL. Solo si el rol cambia realmente.
  if new.role is distinct from old.role then
    v_actor_rank := private.role_rank(private.current_user_role());
    if private.role_rank(new.role) >= v_actor_rank then
      raise exception 'No puedes asignar un rol igual o superior al tuyo.'
        using errcode = '42501';
    end if;
    if private.role_rank(old.role) >= v_actor_rank then
      raise exception 'No puedes cambiar el rol de un usuario de rango igual o superior al tuyo.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.profiles_guard() from public;


-- (2) Sincroniza profiles.email desde auth.users cuando el email cambia de
--     verdad (tras confirmación de GoTrue). DEFINER + trigger sobre auth.users,
--     mismo patrón que handle_new_user (0001/0016). En ese contexto auth.uid()
--     es NULL => profiles_guard deja pasar el nuevo email.
create or replace function public.sync_profile_email_from_auth()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
     set email = new.email
   where id = new.id;
  return new;
end;
$$;

revoke execute on function public.sync_profile_email_from_auth() from public;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row
  when (new.email is distinct from old.email)
  execute function public.sync_profile_email_from_auth();
