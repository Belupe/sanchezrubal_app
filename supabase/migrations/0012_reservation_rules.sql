-- ===============================================================
-- 0012_reservation_rules.sql — Reglas de reserva + purga de registros
-- ===============================================================
-- 1) Una sola reserva por domicilio en un rango (sin solapamientos).
-- 2) Duración MÍNIMA (reutiliza la columna max_reservation_days como
--    "días mínimos"; por defecto 15). El mantenimiento queda exento.
-- 3) Los registros de auditoría se vacían pasados 2 meses (cron diario).
-- ===============================================================

create or replace function public.enforce_max_reservation_days()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_min int;
  v_days int;
begin
  -- Sin solapamientos: solo una reserva por domicilio en esas fechas.
  if exists (
    select 1 from public.reservations r
    where r.property_id = new.property_id
      and r.id <> new.id
      and r.start_date < new.end_date
      and r.end_date > new.start_date
  ) then
    raise exception 'Ya existe una reserva para esas fechas en este domicilio.';
  end if;

  -- Duración mínima (el mantenimiento no tiene mínimo).
  if not new.is_maintenance then
    select max_reservation_days into v_min from public.system_config where id = 'global';
    if v_min is not null then
      v_days := ceil(extract(epoch from (new.end_date - new.start_date)) / 86400.0);
      if v_days < v_min then
        raise exception 'La reserva debe ser de al menos % días.', v_min;
      end if;
    end if;
  end if;

  return new;
end;
$$;

-- Valor por defecto del mínimo: 15 días.
update public.system_config set max_reservation_days = 15 where id = 'global';

-- Purga de registros de auditoría con más de 2 meses (a diario, 03:00 UTC).
create extension if not exists pg_cron;
select cron.schedule(
  'purge-audit-logs',
  '0 3 * * *',
  $$ delete from public.audit_logs where created_at < now() - interval '2 months'; $$
);
