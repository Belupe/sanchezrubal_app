-- ===============================================================
-- 0026_reservas_por_quincenas.sql — La reserva dura EXACTAMENTE una quincena
--
-- Había dos ajustes, un mínimo y un tope (15 y 31 días), y se podía reservar
-- cualquier cosa entre medias. La familia funciona siempre por quincenas, así
-- que el tope pasa a valer lo mismo que el mínimo: toda reserva dura 15 días.
--
-- No se renombran las columnas (`max_reservation_days` y su `_cap`) para no
-- arrastrar el cambio a media base de datos. El tope se iguala al mínimo, y a
-- partir de ahora la pantalla de configuración escribe los dos a la vez desde un
-- único campo: la duración.
--
-- Se retocan también los mensajes del trigger: con mínimo y tope iguales, decir
-- "debe ser de al menos 15 días" despista, porque 20 tampoco vale.
-- ===============================================================

update public.system_config
   set max_reservation_days_cap = max_reservation_days
 where id = 'global';

create or replace function public.enforce_max_reservation_days()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_min  int;
  v_cap  int;
  v_days int;
begin
  if exists (
    select 1 from public.reservations r
    where r.property_id = new.property_id
      and r.id <> new.id
      and r.start_date < new.end_date
      and r.end_date > new.start_date
  ) then
    raise exception 'Ya existe una reserva para esas fechas en este domicilio.';
  end if;

  if not new.is_maintenance then
    select max_reservation_days, max_reservation_days_cap
      into v_min, v_cap
      from public.system_config
     where id = 'global';

    v_days := ceil(extract(epoch from (new.end_date - new.start_date)) / 86400.0);

    -- Mínimo y tope iguales = duración fija. Se dice así para no confundir.
    if v_min is not null and v_cap is not null and v_min = v_cap then
      if v_days <> v_min then
        raise exception 'La reserva debe ser de exactamente % días.', v_min;
      end if;
      return new;
    end if;

    if v_min is not null and v_days < v_min then
      raise exception 'La reserva debe ser de al menos % días.', v_min;
    end if;
    if v_cap is not null and v_days > v_cap then
      raise exception 'La reserva no puede superar los % días.', v_cap;
    end if;
  end if;

  return new;
end;
$function$;
