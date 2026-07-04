-- ===============================================================
-- 0018_security_fase3_bd.sql — Remediación de seguridad, Fase 3 (medios BD)
--
-- No se edita ninguna migración aplicada: todo es CREATE OR REPLACE / ALTER /
-- ADD CONSTRAINT / DROP+CREATE POLICY / triggers nuevos. Sin cambio de función
-- visible. reservations/reservation_waitlist NO pasan a FORCE RLS (las vistas
-- de ocupación DEFINER de 0017 dependen de ello).
--
--   [M-03] Doble reserva por carrera (TOCTOU) → constraint EXCLUDE atómica.
--   [M-04] Tope MÁXIMO de días, configurable en caliente (system_config).
--   [M-05] family_group_id sellado en servidor (no lo falsea el cliente).
--   [M-06] Sorteos: barajado CSPRNG + resultados inmutables + auditoría.
-- ===============================================================


-- ===============================================================
-- [M-03] Doble reserva por carrera. El chequeo de solape del trigger (EXISTS)
-- no bloquea filas: dos inserts concurrentes pueden pasar ambos y crear reservas
-- solapadas. Una constraint EXCLUDE lo evalúa ATÓMICAMENTE. El trigger se
-- mantiene (mensaje amable + min/max); la constraint es el backstop de la carrera.
-- ===============================================================
create extension if not exists btree_gist;

-- Semántica half-open [inicio, fin): idéntica al check del trigger
-- (start < new.end AND end > new.start). Reservas contiguas (una acaba el día que
-- empieza otra) NO se consideran solape, igual que hoy. Si existieran filas ya
-- solapadas el ADD CONSTRAINT abortaría, pero el trigger 0012 las impidió.
alter table public.reservations
  drop constraint if exists reservations_no_overlap;
alter table public.reservations
  add constraint reservations_no_overlap
  exclude using gist (
    property_id with =,
    tstzrange(start_date, end_date, '[)') with &&
  );


-- ===============================================================
-- [M-04] Tope MÁXIMO de días. 0012 convirtió enforce_max_reservation_days en un
-- MÍNIMO y quitó la cota superior. Se reintroduce un MÁXIMO configurable en
-- caliente (system_config.max_reservation_days_cap, default 31), conservando el
-- mínimo. La promoción de la cola omite (sin abortar la cancelación) las entradas
-- que superen el cap.
-- ===============================================================
alter table public.system_config
  add column if not exists max_reservation_days_cap integer not null default 31;

update public.system_config
   set max_reservation_days_cap = greatest(
         coalesce(max_reservation_days_cap, 31),
         coalesce(max_reservation_days, 0)
       )
 where id = 'global';

alter table public.system_config
  drop constraint if exists system_config_days_range_chk;
alter table public.system_config
  add constraint system_config_days_range_chk
  check (
    max_reservation_days is null
    or max_reservation_days_cap >= max_reservation_days
  );

create or replace function public.enforce_max_reservation_days()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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

    if v_min is not null and v_days < v_min then
      raise exception 'La reserva debe ser de al menos % días.', v_min;
    end if;
    if v_cap is not null and v_days > v_cap then
      raise exception 'La reserva no puede superar los % días.', v_cap;
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.enforce_waitlist_rules()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_min  int;
  v_cap  int;
  v_days int;
begin
  if new.end_date <= new.start_date then
    raise exception 'La fecha de salida debe ser posterior a la de entrada.';
  end if;

  select max_reservation_days, max_reservation_days_cap
    into v_min, v_cap
    from public.system_config
   where id = 'global';

  v_days := ceil(extract(epoch from (new.end_date - new.start_date)) / 86400.0);

  if v_min is not null and v_days < v_min then
    raise exception 'La solicitud debe ser de al menos % días.', v_min;
  end if;
  if v_cap is not null and v_days > v_cap then
    raise exception 'La solicitud no puede superar los % días.', v_cap;
  end if;

  if exists (
    select 1 from public.reservation_waitlist w
    where w.property_id = new.property_id
      and w.requested_by_id = new.requested_by_id
      and w.status = 'waiting'
      and w.id <> new.id
      and w.start_date < new.end_date
      and w.end_date > new.start_date
  ) then
    raise exception 'Ya estás en la lista de espera para esas fechas en este domicilio.';
  end if;

  return new;
end;
$$;

-- Promoción resiliente: al cancelar, se omite (sin abortar) la entrada que
-- supere el cap; queda en 'waiting' por si el admin sube el cap más adelante.
create or replace function public.promote_waitlist_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  w        public.reservation_waitlist%rowtype;
  v_new_id uuid;
  v_cap    int;
begin
  if old.is_maintenance then
    return old;
  end if;

  select max_reservation_days_cap into v_cap
    from public.system_config where id = 'global';

  for w in
    select * from public.reservation_waitlist
    where property_id = old.property_id
      and status = 'waiting'
      and start_date < old.end_date
      and end_date > old.start_date
    order by created_at asc
  loop
    if v_cap is not null
       and ceil(extract(epoch from (w.end_date - w.start_date)) / 86400.0) > v_cap then
      continue;
    end if;

    if not exists (
      select 1 from public.reservations r
      where r.property_id = w.property_id
        and r.start_date < w.end_date
        and r.end_date > w.start_date
    ) then
      insert into public.reservations
        (property_id, family_group_id, created_by_id, start_date, end_date, guest_count, notes)
      values
        (w.property_id, w.family_group_id, w.requested_by_id, w.start_date, w.end_date,
         w.guest_count, w.notes)
      returning id into v_new_id;

      update public.reservation_waitlist
        set status = 'promoted', updated_at = now()
        where id = w.id;

      perform net.http_post(
        url := 'https://pjceyplciujtrnxptwbx.supabase.co/functions/v1/notify-waitlist',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
        ),
        body := jsonb_build_object(
          'waitlistId',          w.id,
          'newReservationId',    v_new_id,
          'promotedUserId',      w.requested_by_id,
          'cancelledByUserId',   old.created_by_id,
          'propertyId',          w.property_id,
          'startDate',           w.start_date,
          'endDate',             w.end_date
        )
      );

      exit;  -- solo se promueve uno por cancelación.
    end if;
  end loop;

  return old;
end;
$$;


-- ===============================================================
-- [M-05] family_group_id sellado en servidor. El INSERT solo exigía
-- created_by_id/requested_by_id = auth.uid(); el cliente podía sellar el grupo de
-- OTRA familia. Se sella desde el perfil del CREADOR de la fila (no de auth.uid(),
-- para que la promoción DEFINER estampe el grupo del waitlister, no del que canceló).
-- ===============================================================
create or replace function public.seal_reservation_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_maintenance then
    new.family_group_id := null;  -- los bloqueos de mantenimiento no son de nadie
  else
    new.family_group_id := (
      select p.family_group_id from public.profiles p where p.id = new.created_by_id
    );
  end if;
  return new;
end;
$$;
revoke execute on function public.seal_reservation_group() from public;

drop trigger if exists trg_seal_reservation_group on public.reservations;
create trigger trg_seal_reservation_group
  before insert on public.reservations
  for each row execute function public.seal_reservation_group();

create or replace function public.seal_waitlist_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.family_group_id := (
    select p.family_group_id from public.profiles p where p.id = new.requested_by_id
  );
  return new;
end;
$$;
revoke execute on function public.seal_waitlist_group() from public;

drop trigger if exists trg_seal_waitlist_group on public.reservation_waitlist;
create trigger trg_seal_waitlist_group
  before insert on public.reservation_waitlist
  for each row execute function public.seal_waitlist_group();


-- ===============================================================
-- [M-06] Sorteos manipulables: random() (no CSPRNG), resultados escribibles a
-- mano por cualquier principal, sin auditoría. Se corrige: barajado con
-- gen_random_bytes(), resultados append-only (solo vía run_sorteo) e inmutables,
-- y auditoría de ejecución/borrado.
-- ===============================================================

-- (1) Entero uniforme en [1, p_max] con CSPRNG y muestreo por rechazo (sin sesgo).
create or replace function private.secure_rand_int(p_max int)
returns int
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  v_maxv  bigint := 9223372036854775807;  -- 2^63 - 1
  v_range bigint := p_max;
  v_rem   bigint;
  v_bytes bytea;
  v_val   bigint;
  k       int;
begin
  if p_max is null or p_max <= 1 then
    return 1;
  end if;

  v_rem := ((v_maxv % v_range) + 1) % v_range;

  loop
    v_bytes := gen_random_bytes(8);
    v_val := (get_byte(v_bytes, 0) & 127)::bigint;
    for k in 1..7 loop
      v_val := (v_val << 8) | get_byte(v_bytes, k);
    end loop;

    if v_val <= v_maxv - v_rem then
      return (v_val % v_range)::int + 1;
    end if;
  end loop;
end;
$$;
revoke execute on function private.secure_rand_int(int) from public;

-- (1)+(3) run_sorteo: baraja con CSPRNG + auditoría + anti-doble-tanda.
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
    insert into public.audit_logs(action, entity_type, entity_id, details, user_id)
    values ('CREATE', 'sorteo', v_sorteo_id,
            jsonb_build_object('name', p_name, 'quincenas', p_quincenas,
                               'group_ids', p_group_ids, 'resultados', '[]'::jsonb),
            auth.uid());
    return v_sorteo_id;
  end if;

  if exists (select 1 from public.sorteo_resultados where sorteo_id = v_sorteo_id) then
    raise exception 'El sorteo % ya tiene resultados; no se puede re-ejecutar.', v_sorteo_id;
  end if;

  for i in reverse n..2 loop
    j := private.secure_rand_int(i);
    tmp := v_groups[i];
    v_groups[i] := v_groups[j];
    v_groups[j] := tmp;
  end loop;

  v_count := least(coalesce(array_length(p_quincenas, 1), 0), n);
  for i in 1..v_count loop
    insert into public.sorteo_resultados(sorteo_id, family_group_id, premio)
    values (v_sorteo_id, v_groups[i], p_quincenas[i]);
  end loop;

  insert into public.audit_logs(action, entity_type, entity_id, details, user_id)
  values ('CREATE', 'sorteo', v_sorteo_id,
          jsonb_build_object(
            'name', p_name, 'quincenas', p_quincenas, 'group_ids', p_group_ids,
            'resultados', (
              select coalesce(jsonb_agg(
                       jsonb_build_object('family_group_id', sr.family_group_id, 'premio', sr.premio)
                       order by sr.premio), '[]'::jsonb)
              from public.sorteo_resultados sr where sr.sorteo_id = v_sorteo_id
            )),
          auth.uid());

  return v_sorteo_id;
end;
$$;
revoke execute on function public.run_sorteo(text, text[], uuid[]) from public;
grant  execute on function public.run_sorteo(text, text[], uuid[]) to authenticated;

-- (2) sorteo_resultados APPEND-ONLY: se retira la escritura directa del principal
-- (0002_rls.sql:215-216). La única alta es run_sorteo (DEFINER). Trigger de
-- inmutabilidad como defensa en profundidad ante UPDATE del cliente.
drop policy if exists sorteo_resultados_write on public.sorteo_resultados;

create or replace function public.sorteo_resultados_immutable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_user is distinct from 'authenticated' then
    return new;  -- service_role / postgres / definer: confianza
  end if;
  raise exception 'Los resultados de un sorteo son inmutables; no se pueden editar a mano.'
    using errcode = '42501';
end;
$$;
revoke execute on function public.sorteo_resultados_immutable() from public;

drop trigger if exists trg_sorteo_resultados_immutable on public.sorteo_resultados;
create trigger trg_sorteo_resultados_immutable
  before update on public.sorteo_resultados
  for each row execute function public.sorteo_resultados_immutable();

-- (3) Auditoría del borrado de sorteos (rastro de re-tiradas por borrado+recreación).
create or replace function public.audit_sorteos_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_logs(action, entity_type, entity_id, details, user_id)
  values ('DELETE', 'sorteo', old.id, jsonb_build_object('old', to_jsonb(old)), auth.uid());
  return old;
end;
$$;
revoke execute on function public.audit_sorteos_delete() from public;

drop trigger if exists trg_audit_sorteos_delete on public.sorteos;
create trigger trg_audit_sorteos_delete
  after delete on public.sorteos
  for each row execute function public.audit_sorteos_delete();
