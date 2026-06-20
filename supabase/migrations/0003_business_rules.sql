-- ===============================================================
-- 0003_business_rules.sql — Triggers de reglas de negocio
-- ===============================================================
-- Todas las guardas hacen bypass cuando auth.uid() IS NULL, es decir,
-- cuando la acción viene del service_role (Edge Functions / admin API),
-- que es de confianza.
-- ===============================================================

-- ---------------------------------------------------------------
-- Reservas: el CREADOR (no admin del grupo) solo puede cambiar
-- guest_count, guests_list y notes. NO fechas, ni domicilio, ni grupo,
-- ni creador, ni el flag de mantenimiento.
-- ---------------------------------------------------------------
create or replace function public.reservations_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.is_group_admin(old.family_group_id) then
    if new.start_date    is distinct from old.start_date
       or new.end_date   is distinct from old.end_date
       or new.property_id is distinct from old.property_id
       or new.family_group_id is distinct from old.family_group_id
       or new.created_by_id   is distinct from old.created_by_id
       or new.is_maintenance  is distinct from old.is_maintenance then
      raise exception 'Solo un administrador puede cambiar fechas u otros campos de la reserva. Como creador solo puedes ajustar el número de personas, la lista de invitados o los comentarios.';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_reservations_guard
  before update on public.reservations
  for each row execute function public.reservations_guard();

-- ---------------------------------------------------------------
-- Reservas: auditoría automática (quién crea/modifica/elimina).
-- Escribe en audit_logs con el usuario actual (null si service_role).
-- ---------------------------------------------------------------
create or replace function public.audit_reservations()
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
    v_details := jsonb_build_object('new', to_jsonb(new));
  elsif tg_op = 'UPDATE' then
    v_action := 'UPDATE'; v_entity := new.id;
    v_details := jsonb_build_object('old', to_jsonb(old), 'new', to_jsonb(new));
  else -- DELETE
    v_action := 'DELETE'; v_entity := old.id;
    v_details := jsonb_build_object('old', to_jsonb(old));
  end if;

  insert into public.audit_logs (action, entity_type, entity_id, details, user_id)
  values (v_action, 'reservation', v_entity, v_details, auth.uid());

  return coalesce(new, old);
end;
$$;

create trigger trg_audit_reservations
  after insert or update or delete on public.reservations
  for each row execute function public.audit_reservations();

-- ---------------------------------------------------------------
-- Perfiles: un no-principal NO puede cambiarse su propio rol ni su
-- grupo (anti escalado de privilegios). Los cambios se ignoran
-- silenciosamente (se revierten a los valores antiguos).
-- ---------------------------------------------------------------
create or replace function public.profiles_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.is_principal() then
    new.role := old.role;
    new.family_group_id := old.family_group_id;
  end if;
  return new;
end;
$$;

create trigger trg_profiles_guard
  before update on public.profiles
  for each row execute function public.profiles_guard();
