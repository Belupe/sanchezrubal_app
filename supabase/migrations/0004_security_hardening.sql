-- ===============================================================
-- 0004_security_hardening.sql — Cierra los avisos del linter de Supabase
-- ===============================================================
-- 1) set_updated_at con search_path fijo.
-- 2) Helpers de RLS movidos a un esquema `private` NO expuesto por la
--    API (PostgREST solo expone `public`). Las políticas los siguen
--    resolviendo por OID; authenticated necesita USAGE sobre `private`
--    para evaluarlos en las policies.
-- 3) Las funciones de trigger no deben ser llamables por la API: se les
--    revoca EXECUTE (los triggers se disparan igualmente).
-- ===============================================================

alter function public.set_updated_at() set search_path = '';

-- ---- Esquema privado para los helpers de RLS --------------------
create schema if not exists private;
grant usage on schema private to authenticated;

alter function public.current_user_role()      set schema private;
alter function public.current_user_group()     set schema private;
alter function public.is_mega()                set schema private;
alter function public.is_principal()           set schema private;
alter function public.is_group_admin(uuid)     set schema private;

-- Corregir las referencias internas (ahora viven en private)
create or replace function private.is_mega()
returns boolean language sql stable security definer set search_path = public as $$
  select private.current_user_role() = 'MEGA_ADMIN';
$$;

create or replace function private.is_principal()
returns boolean language sql stable security definer set search_path = public as $$
  select private.current_user_role() in ('MEGA_ADMIN','PRINCIPAL_ADMIN');
$$;

create or replace function private.is_group_admin(gid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select
    private.current_user_role() in ('MEGA_ADMIN','PRINCIPAL_ADMIN')
    or (
      private.current_user_role() in ('FAMILY_ADMIN','FAMILY_SECOND_ADMIN')
      and private.current_user_group() is not distinct from gid
    );
$$;

-- ---- Trigger functions: actualizar refs a helpers + quitar de la API
create or replace function public.reservations_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not private.is_group_admin(old.family_group_id) then
    if new.start_date    is distinct from old.start_date
       or new.end_date   is distinct from old.end_date
       or new.property_id is distinct from old.property_id
       or new.family_group_id is distinct from old.family_group_id
       or new.created_by_id   is distinct from old.created_by_id
       or new.is_maintenance  is distinct from old.is_maintenance then
      raise exception 'Solo un administrador puede cambiar fechas u otros campos de la reserva. Como creador solo puedes ajustar el numero de personas, la lista de invitados o los comentarios.';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.profiles_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not private.is_principal() then
    new.role := old.role;
    new.family_group_id := old.family_group_id;
  end if;
  return new;
end;
$$;

revoke execute on function public.set_updated_at()     from public;
revoke execute on function public.handle_new_user()    from public;
revoke execute on function public.audit_reservations() from public;
revoke execute on function public.reservations_guard() from public;
revoke execute on function public.profiles_guard()     from public;
