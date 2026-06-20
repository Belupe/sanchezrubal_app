-- ===============================================================
-- 0013_waitlist.sql — Lista de espera (cola) de reservas
-- ===============================================================
-- Cuando unas fechas de un domicilio ya están reservadas, un usuario
-- puede APUNTARSE a la lista de espera para ese rango. Si la reserva que
-- bloquea esas fechas se CANCELA (DELETE), el siguiente de la cola (orden
-- FIFO por created_at) es PROMOVIDO automáticamente: se le crea la reserva
-- y se le envían 2 notificaciones (vía Edge Function notify-waitlist).
-- ===============================================================

-- ---------------------------------------------------------------
-- Tabla de la cola
-- ---------------------------------------------------------------
create table public.reservation_waitlist (
  id              uuid primary key default gen_random_uuid(),
  property_id     uuid not null references public.properties(id) on delete cascade,
  requested_by_id uuid not null references public.profiles(id) on delete cascade,
  family_group_id uuid references public.family_groups(id) on delete set null,
  start_date      timestamptz not null,
  end_date        timestamptz not null,
  guest_count     integer not null default 1,
  notes           text,
  -- waiting   = en cola
  -- promoted  = se le creó la reserva al cancelar la que bloqueaba
  -- cancelled = el usuario (o un admin) retiró su solicitud
  -- expired   = descartada (reservada manualmente por otro, etc.)
  status          text not null default 'waiting'
                    check (status in ('waiting','promoted','cancelled','expired')),
  created_at      timestamptz not null default now(),  -- orden FIFO de la cola
  updated_at      timestamptz not null default now()
);
create index reservation_waitlist_property_id_idx on public.reservation_waitlist(property_id);
create index reservation_waitlist_status_idx      on public.reservation_waitlist(status);
create index reservation_waitlist_created_at_idx  on public.reservation_waitlist(created_at);

create trigger set_reservation_waitlist_updated_at
  before update on public.reservation_waitlist
  for each row execute function public.set_updated_at();

alter table public.reservation_waitlist enable row level security;

-- ---------------------------------------------------------------
-- Privilegios de tabla (las tablas por migración no traen los GRANT por
-- defecto; replica 0010/0011). El RLS decide QUÉ filas.
-- ---------------------------------------------------------------
grant select, insert, update, delete on public.reservation_waitlist to authenticated;
grant all on public.reservation_waitlist to service_role;

-- ---------------------------------------------------------------
-- RLS: calendario compartido (igual que reservations, SELECT abierto a
-- authenticated para poder mostrar la cola y la posición de cada uno).
--   insert: cada uno crea SU propia solicitud.
--   update/delete: el solicitante o un admin del grupo.
-- (La promoción la hace un trigger SECURITY DEFINER, que salta el RLS.)
-- ---------------------------------------------------------------
create policy reservation_waitlist_select on public.reservation_waitlist for select to authenticated
  using ( true );
create policy reservation_waitlist_insert on public.reservation_waitlist for insert to authenticated
  with check ( requested_by_id = auth.uid() );
create policy reservation_waitlist_update on public.reservation_waitlist for update to authenticated
  using ( requested_by_id = auth.uid() or private.is_group_admin(family_group_id) )
  with check ( requested_by_id = auth.uid() or private.is_group_admin(family_group_id) );
create policy reservation_waitlist_delete on public.reservation_waitlist for delete to authenticated
  using ( requested_by_id = auth.uid() or private.is_group_admin(family_group_id) );

-- ---------------------------------------------------------------
-- Validación al apuntarse: fechas coherentes, duración mínima (misma
-- regla que reservations) y sin duplicar una solicitud propia que solape.
-- ---------------------------------------------------------------
create or replace function public.enforce_waitlist_rules()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_min  int;
  v_days int;
begin
  if new.end_date <= new.start_date then
    raise exception 'La fecha de salida debe ser posterior a la de entrada.';
  end if;

  select max_reservation_days into v_min from public.system_config where id = 'global';
  if v_min is not null then
    v_days := ceil(extract(epoch from (new.end_date - new.start_date)) / 86400.0);
    if v_days < v_min then
      raise exception 'La solicitud debe ser de al menos % días.', v_min;
    end if;
  end if;

  -- Evita que el mismo usuario tenga dos solicitudes en cola que se solapen
  -- para el mismo domicilio.
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

create trigger trg_enforce_waitlist_rules
  before insert or update on public.reservation_waitlist
  for each row execute function public.enforce_waitlist_rules();

revoke execute on function public.enforce_waitlist_rules() from public;

-- ---------------------------------------------------------------
-- Promoción automática: al CANCELAR (DELETE) una reserva, se busca el
-- siguiente de la cola (FIFO) cuyas fechas solapen con las liberadas y
-- que YA no choquen con ninguna otra reserva; se le crea la reserva y se
-- disparan las 2 notificaciones vía Edge Function notify-waitlist.
-- ---------------------------------------------------------------
create or replace function public.promote_waitlist_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  w          public.reservation_waitlist%rowtype;
  v_new_id   uuid;
begin
  -- Los bloqueos de mantenimiento no generan cola.
  if old.is_maintenance then
    return old;
  end if;

  for w in
    select * from public.reservation_waitlist
    where property_id = old.property_id
      and status = 'waiting'
      and start_date < old.end_date
      and end_date > old.start_date
    order by created_at asc
  loop
    -- Re-chequeo: que esas fechas no choquen ya con OTRA reserva existente
    -- (la que se acaba de borrar ya no está).
    if not exists (
      select 1 from public.reservations r
      where r.property_id = w.property_id
        and r.start_date < w.end_date
        and r.end_date > w.start_date
    ) then
      -- Crear la reserva a nombre del waitlister. Pasa por
      -- enforce_max_reservation_days() (revalida solape + mínimo) y por
      -- audit_reservations() (deja traza en audit_logs).
      insert into public.reservations
        (property_id, family_group_id, created_by_id, start_date, end_date, guest_count, notes)
      values
        (w.property_id, w.family_group_id, w.requested_by_id, w.start_date, w.end_date,
         w.guest_count, w.notes)
      returning id into v_new_id;

      update public.reservation_waitlist
        set status = 'promoted', updated_at = now()
        where id = w.id;

      -- Dispara las 2 notificaciones (push + email). pg_net es asíncrono:
      -- no bloquea el DELETE. Autenticado con el mismo cron_secret de Vault.
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

create trigger trg_promote_waitlist
  after delete on public.reservations
  for each row execute function public.promote_waitlist_on_cancel();

revoke execute on function public.promote_waitlist_on_cancel() from public;
