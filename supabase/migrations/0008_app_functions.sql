-- ===============================================================
-- 0008_app_functions.sql — Funciones de negocio para la app
-- ===============================================================
-- 1) run_sorteo: asigna quincenas/premios a grupos con Fisher-Yates
--    (réplica del comportamiento legacy). Solo admin principal.
-- 2) Trigger que impone max_reservation_days a las reservas (no mantto).
-- ===============================================================

-- ---- 1) Sorteo (Fisher-Yates) ----
create or replace function public.run_sorteo(
  p_name text,
  p_quincenas text[],
  p_group_ids uuid[]
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sorteo_id uuid;
  v_groups uuid[] := p_group_ids;
  n int := array_length(v_groups, 1);
  v_count int;
  i int; j int; tmp uuid;
begin
  if not private.is_principal() then
    raise exception 'Solo un administrador principal puede ejecutar sorteos';
  end if;

  insert into public.sorteos(name, created_by_id)
  values (p_name, auth.uid())
  returning id into v_sorteo_id;

  if n is null or n = 0 then
    return v_sorteo_id;
  end if;

  -- Baraje Fisher-Yates de los grupos
  for i in reverse n..2 loop
    j := 1 + floor(random() * i)::int;
    tmp := v_groups[i];
    v_groups[i] := v_groups[j];
    v_groups[j] := tmp;
  end loop;

  -- Empareja cada quincena con un grupo (hasta agotar el menor de ambos)
  v_count := least(coalesce(array_length(p_quincenas, 1), 0), n);
  for i in 1..v_count loop
    insert into public.sorteo_resultados(sorteo_id, family_group_id, premio)
    values (v_sorteo_id, v_groups[i], p_quincenas[i]);
  end loop;

  return v_sorteo_id;
end;
$$;

revoke execute on function public.run_sorteo(text, text[], uuid[]) from public;
grant execute on function public.run_sorteo(text, text[], uuid[]) to authenticated;

-- ---- 2) Límite de días máximo por reserva ----
create or replace function public.enforce_max_reservation_days()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max int;
  v_days int;
begin
  if new.is_maintenance then
    return new; -- el mantenimiento no tiene límite
  end if;

  select max_reservation_days into v_max from public.system_config where id = 'global';
  if v_max is null then
    return new;
  end if;

  v_days := ceil(extract(epoch from (new.end_date - new.start_date)) / 86400.0);
  if v_days > v_max then
    raise exception 'La reserva supera el máximo de % días permitidos.', v_max;
  end if;

  return new;
end;
$$;

create trigger trg_enforce_max_days
  before insert or update on public.reservations
  for each row execute function public.enforce_max_reservation_days();
