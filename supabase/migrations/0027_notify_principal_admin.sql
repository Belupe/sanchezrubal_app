-- ===============================================================
-- 0027_notify_principal_admin.sql — Avisos al administrador principal
--
-- El PRINCIPAL_ADMIN lleva el control directo de los domicilios y no siempre
-- puede consultar los métodos antiguos, así que necesita enterarse por correo
-- y por push de todo lo que pase: reservas (alta, cambio y cancelación),
-- altas en la lista de espera e informes de salida.
--
-- Por qué desde la BD y no desde la app: hasta ahora el correo de la reserva lo
-- disparaba el móvil del que reservaba (DataService.sendReservationEmail), con
-- un catch silencioso. Si esa app se cerraba o perdía la red, no se enteraba
-- nadie — y los cambios y las cancelaciones no lo disparaban siquiera. Un
-- trigger se ejecuta pase lo que pase y venga el cambio de donde venga.
--
-- El reparto de destinatarios NO se decide aquí, sino en la Edge Function
-- notify-changes: aquí solo se describe QUÉ ha pasado. Resumen de a quién va:
--
--   reserva creada/modificada/cancelada  ->  PRINCIPAL_ADMIN (correo + push)
--   bloqueo de mantenimiento             ->  todos menos MEGA_ADMIN (correo)
--                                            + PRINCIPAL_ADMIN (push)
--   alta en la lista de espera           ->  PRINCIPAL_ADMIN (correo + push)
--   informe de salida completado         ->  PRINCIPAL_ADMIN (correo + push)
--
-- Se copia el patrón ya probado de promote_waitlist_on_cancel (0013): pg_net
-- es asíncrono, así que el POST no bloquea ni alarga la transacción, y la
-- llamada se autentica con el mismo cron_secret guardado en Vault.
-- ===============================================================

-- ---------------------------------------------------------------
-- Plantillas. Van en TERCERA persona: las que ya existían están escritas
-- para el propio interesado ("Hola, TU reserva…") y a un administrador que
-- no ha reservado nada le llegarían al revés.
--
-- MAINTENANCE no se toca: ya existe desde 0006 y sirve tal cual. Lo único
-- que cambia para ella es a quién se reparte, y eso vive en la Edge Function.
-- ---------------------------------------------------------------
insert into public.notification_templates (type, subject, body) values
('ADMIN_RESERVATION_CREATED', 'Nueva reserva — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Nueva reserva</h2><p><b>{{UserName}}</b> ha reservado <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}}.</p><p>Personas: {{GuestCount}}</p></div>'),
('ADMIN_RESERVATION_UPDATED', 'Reserva modificada — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Reserva modificada</h2><p>La reserva de <b>{{UserName}}</b> en <b>{{PropertyName}}</b> ha cambiado.</p><p>Antes: del {{OldStartDate}} al {{OldEndDate}}<br>Ahora: del {{StartDate}} al {{EndDate}}</p></div>'),
('ADMIN_RESERVATION_CANCELLED', 'Reserva cancelada — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Reserva cancelada</h2><p><b>{{UserName}}</b> ha cancelado su reserva en <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}}.</p></div>'),
('ADMIN_WAITLIST_JOINED', 'Nueva solicitud en lista de espera — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Lista de espera</h2><p><b>{{UserName}}</b> se ha apuntado a la lista de espera de <b>{{PropertyName}}</b> para el {{StartDate}} al {{EndDate}}.</p><p>Si quien tiene esas fechas las cancela, se le adjudicarán automáticamente.</p></div>'),
('ADMIN_OUT_REPORT', 'Formulario de salida — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Formulario de salida completado</h2><p><b>{{UserName}}</b> ha completado el formulario de salida de <b>{{PropertyName}}</b>.</p><p>Estado general: <b>{{GeneralStatus}}</b><br>Desperfectos: {{Damages}}<br>Cosas que faltan: {{MissingItems}}</p></div>'),
-- La MAINTENANCE que ya existe ("se ha bloqueado…") vale para el alta y para
-- el cambio de fechas, pero leída tras un borrado dice justo lo contrario de
-- lo que ha pasado. De ahí esta segunda.
('MAINTENANCE_CANCELLED', 'Mantenimiento levantado — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Mantenimiento levantado</h2><p>Se ha retirado el bloqueo por mantenimiento de <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}}. Las fechas vuelven a estar libres.</p></div>')
on conflict (type) do nothing;


-- ---------------------------------------------------------------
-- Helper: un único sitio donde vive la URL y el secreto, para no repetir
-- el bloque de cabeceras en los tres triggers.
--
-- SECURITY DEFINER porque lee vault.decrypted_secrets, al que el rol que
-- dispara el trigger no llega. Es el mismo planteamiento de 0013.
-- ---------------------------------------------------------------
create or replace function public.post_notify_changes(payload jsonb)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  perform net.http_post(
    url := 'https://pjceyplciujtrnxptwbx.supabase.co/functions/v1/notify-changes',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := payload
  );
end;
$$;

revoke execute on function public.post_notify_changes(jsonb) from public;


-- ---------------------------------------------------------------
-- Reservas: alta, cambio y cancelación.
--
-- actorId es quien PROVOCA el cambio (auth.uid()), que no tiene por qué ser
-- el dueño de la reserva: un administrador puede mover o borrar la de otro.
-- La Edge Function lo usa para no avisar a alguien de su propio cambio.
-- Puede venir NULL si el cambio lo hace el service role (p. ej. la promoción
-- automática de la lista de espera).
-- ---------------------------------------------------------------
create or replace function public.notify_change_reservation()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  r           public.reservations%rowtype;
  v_evt       text;
  -- Las fechas de ANTES se copian a variables en la rama del UPDATE en vez de
  -- leer old.* dentro del jsonb_build_object: así la expresión que se evalúa
  -- en un INSERT no menciona siquiera a OLD, que ahí no existe.
  v_old_start timestamptz;
  v_old_end   timestamptz;
begin
  if tg_op = 'DELETE' then
    r := old; v_evt := 'reservation_cancelled';
  elsif tg_op = 'UPDATE' then
    r := new; v_evt := 'reservation_updated';
    v_old_start := old.start_date;
    v_old_end   := old.end_date;
  else
    r := new; v_evt := 'reservation_created';
  end if;

  perform public.post_notify_changes(jsonb_build_object(
    'event',         v_evt,
    'reservationId', r.id,
    'propertyId',    r.property_id,
    'createdById',   r.created_by_id,
    'actorId',       auth.uid(),
    'startDate',     r.start_date,
    'endDate',       r.end_date,
    'guestCount',    r.guest_count,
    'isMaintenance', r.is_maintenance,
    -- Solo llevan valor en UPDATE: permiten redactar el "antes / ahora".
    'oldStartDate',  v_old_start,
    'oldEndDate',    v_old_end
  ));

  return coalesce(new, old);
end;
$$;

revoke execute on function public.notify_change_reservation() from public;

create trigger trg_notify_change_reservation_ins_del
  after insert or delete on public.reservations
  for each row execute function public.notify_change_reservation();

-- El UPDATE va aparte porque su WHEN mira OLD, que en un INSERT no existe.
-- Sin este filtro, tocar una nota o que set_updated_at() refresque la fila
-- generaría correo y push por algo que al administrador no le dice nada.
create trigger trg_notify_change_reservation_upd
  after update on public.reservations
  for each row
  when (old.start_date     is distinct from new.start_date
     or old.end_date       is distinct from new.end_date
     or old.property_id    is distinct from new.property_id
     or old.guest_count    is distinct from new.guest_count
     or old.is_maintenance is distinct from new.is_maintenance)
  execute function public.notify_change_reservation();


-- ---------------------------------------------------------------
-- Lista de espera: SOLO el alta.
--
-- Deliberadamente NO se avisa del paso a 'promoted': esa promoción crea una
-- reserva, y esa reserva ya dispara el trigger de arriba. Avisar en los dos
-- sitios daría dos correos por el mismo hecho.
-- ---------------------------------------------------------------
create or replace function public.notify_change_waitlist()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  perform public.post_notify_changes(jsonb_build_object(
    'event',      'waitlist_joined',
    'waitlistId', new.id,
    'propertyId', new.property_id,
    'createdById', new.requested_by_id,
    'actorId',    auth.uid(),
    'startDate',  new.start_date,
    'endDate',    new.end_date,
    'guestCount', new.guest_count
  ));
  return new;
end;
$$;

revoke execute on function public.notify_change_waitlist() from public;

create trigger trg_notify_change_waitlist
  after insert on public.reservation_waitlist
  for each row
  when (new.status = 'waiting')
  execute function public.notify_change_waitlist();


-- ---------------------------------------------------------------
-- Informes de salida.
--
-- La tabla no guarda quién lo rellena: se deduce del creador de la reserva
-- asociada, y de eso se encarga la Edge Function (reservation_id es
-- nullable, así que puede no haber a quién atribuirlo).
-- ---------------------------------------------------------------
create or replace function public.notify_change_out_report()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  perform public.post_notify_changes(jsonb_build_object(
    'event',         'out_report_created',
    'outReportId',   new.id,
    'propertyId',    new.property_id,
    'reservationId', new.reservation_id,
    'actorId',       auth.uid(),
    'startDate',     new.check_in,
    'endDate',       new.check_out,
    'generalStatus', new.general_status,
    'damages',       new.damages,
    'missingItems',  new.missing_items
  ));
  return new;
end;
$$;

revoke execute on function public.notify_change_out_report() from public;

create trigger trg_notify_change_out_report
  after insert on public.out_reports
  for each row execute function public.notify_change_out_report();
