-- ===============================================================
-- 0017_security_fase2.sql — Remediación de seguridad, Fase 2 (ALTOS)
--
-- Reúne 4 correcciones (verificadas adversarialmente). No se edita ninguna
-- migración ya aplicada: todo es CREATE OR REPLACE / DROP+CREATE POLICY /
-- CREATE VIEW nuevo. Sin cambio de función visible de la app.
--
--   [A-05] is_group_admin(NULL) dejaba de dar admin a family-admins sin grupo.
--   [A-01] Techo de rol en RLS: un principal no puede escalar a MEGA_ADMIN.
--   [A-03] Cola FIFO: created_at/status los sella el servidor (no el cliente).
--   [A-04] Fuga cross-tenant: SELECT acotado + vistas de ocupación compartida.
-- ===============================================================


-- ===============================================================
-- [A-05] private.is_group_admin(NULL): un FAMILY_ADMIN/SECOND_ADMIN SIN grupo
-- (current_user_group() NULL) se volvía admin de toda reserva/inspección con
-- family_group_id NULL. Se corrige la rama family-admin: gid NULL => FALSE.
-- Se conserva `is not distinct from` (no `=`) para devolver SIEMPRE un booleano
-- estricto: con `= gid` el caso (gid no-nulo, grupo NULL) daría NULL, y ese NULL
-- invierte el IF de reservations_guard() (0003:21 / 0004:50) aflojando la guarda.
-- ===============================================================
create or replace function private.is_group_admin(gid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select
    private.current_user_role() in ('MEGA_ADMIN','PRINCIPAL_ADMIN')
    or (
      private.current_user_role() in ('FAMILY_ADMIN','FAMILY_SECOND_ADMIN')
      and gid is not null
      and private.current_user_group() is not distinct from gid
    );
$$;


-- ===============================================================
-- [A-01] Techo de rol en la BD (mismo límite que la Edge admin-users).
-- profiles_guard() (0004) solo revertía rol/grupo para NO principales; un
-- PRINCIPAL_ADMIN podía UPDATE directo a profiles y ponerse role='MEGA_ADMIN'.
-- El WITH CHECK de una policy no ve OLD, así que el techo (compara old.role,
-- new.role y el rango del actor) vive en el trigger BEFORE UPDATE.
-- El flujo de invitación (admin-users, service_role, auth.uid() NULL) hace
-- bypass y no se ve afectado.
-- ===============================================================
create or replace function private.role_rank(p_role text)
returns int language sql immutable set search_path = public as $$
  select case p_role
    when 'MEGA_ADMIN'          then 5
    when 'PRINCIPAL_ADMIN'     then 4
    when 'FAMILY_ADMIN'        then 3
    when 'FAMILY_SECOND_ADMIN' then 2
    when 'MEMBER'              then 1
    else 0
  end;
$$;

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

  -- No-admins: no pueden tocar su rol ni su grupo (se revierte, como 0003/0004).
  if not private.is_principal() then
    new.role := old.role;
    new.family_group_id := old.family_group_id;
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


-- ===============================================================
-- [A-03] Cola FIFO no falsificable: el servidor sella created_at (orden de la
-- cola) y status en INSERT, y los hace inmutables ante UPDATE del cliente. El
-- camino de confianza (promote_waitlist_on_cancel, SECURITY DEFINER como owner;
-- service_role; postgres) pasa tal cual (current_user != 'authenticated').
-- ===============================================================
create or replace function public.enforce_waitlist_server_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.status     := 'waiting';
    return new;
  end if;

  -- UPDATE del camino de confianza (definer/service_role/postgres): sin tocar.
  if current_user is distinct from 'authenticated' then
    return new;
  end if;

  -- UPDATE de un cliente 'authenticated': created_at y status INMUTABLES.
  new.created_at := old.created_at;
  new.status     := old.status;
  return new;
end;
$$;

drop trigger if exists trg_waitlist_server_fields on public.reservation_waitlist;
create trigger trg_waitlist_server_fields
  before insert or update on public.reservation_waitlist
  for each row execute function public.enforce_waitlist_server_fields();

revoke execute on function public.enforce_waitlist_server_fields() from public;


-- ===============================================================
-- [A-04] Fuga cross-tenant. Decisión: mantener el calendario COMPARTIDO pero
-- ocultar invitados (guests_list) y notas (notes) a otras familias.
--  (1) SELECT de la FILA COMPLETA acotado a creador + su grupo + admins.
--  (2) VISTAS de ocupación (sin guests_list/notes) legibles por todos, para el
--      calendario y la cola compartidos.
-- Las vistas son DEFINER (security_invoker=false): corren como su owner
-- (postgres), que no está sujeto al RLS (activado con ENABLE, no FORCE), así
-- que leen TODAS las filas. IMPORTANTE: por eso reservations/reservation_waitlist
-- NO deben pasar a FORCE ROW LEVEL SECURITY (ver Fase 4 [B-01]).
-- ===============================================================

-- (1) Fila completa solo para creador + grupo + admins.
drop policy if exists reservations_select on public.reservations;
create policy reservations_select on public.reservations
  for select to authenticated
  using (
    created_by_id = auth.uid()
    or private.is_principal()
    or ( family_group_id is not null
         and family_group_id = private.current_user_group() )
  );

drop policy if exists reservation_waitlist_select on public.reservation_waitlist;
create policy reservation_waitlist_select on public.reservation_waitlist
  for select to authenticated
  using (
    requested_by_id = auth.uid()
    or private.is_principal()
    or ( family_group_id is not null
         and family_group_id = private.current_user_group() )
  );

-- (2) Vista de ocupación de reservas (SIN guests_list/notes) para el calendario.
create or replace view public.calendar_occupancy
  with (security_invoker = false, security_barrier = true) as
select
  r.id,
  r.property_id,
  r.family_group_id,
  r.created_by_id,
  r.start_date,
  r.end_date,
  r.guest_count,
  r.is_maintenance
from public.reservations r;

grant select on public.calendar_occupancy to authenticated;

-- Vista de ocupación de la cola (SIN notes) para la cola compartida.
create or replace view public.waitlist_occupancy
  with (security_invoker = false, security_barrier = true) as
select
  w.id,
  w.property_id,
  w.requested_by_id,
  w.family_group_id,
  w.start_date,
  w.end_date,
  w.guest_count,
  w.status,
  w.created_at
from public.reservation_waitlist w;

grant select on public.waitlist_occupancy to authenticated;

-- Nota: el linter de Supabase marcará ambas vistas como `security_definer_view`.
-- Es INTENCIONAL: la exposición está acotada por columnas (sin guests_list/notes)
-- y ese es el mecanismo que sustituye al filtrado por columnas que el RLS no da.
