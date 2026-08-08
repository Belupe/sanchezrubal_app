-- ===============================================================
-- 0033_avisos_push_primero.sql — El push pasa a ser el canal principal
--
-- Hasta ahora el usuario corriente no recibía UN SOLO push: todos los avisos
-- eran correos, y el push estaba reservado al administrador, que es
-- precisamente quien vive dentro de la app. Se le da la vuelta.
--
-- REGLA DE CANAL (la aplica notify-changes, no esta migración):
--   · admin principal  -> correo Y push, siempre.
--   · cualquier otro   -> push si tiene algún dispositivo registrado;
--                         correo SOLO si no lo tiene.
--   · mega admin       -> nada, como se decidió al montar los avisos.
--
-- El correo deja de ser el canal por defecto y pasa a ser la red de seguridad
-- de quien no puede recibir push: Windows y Linux no lo soportan, y en móvil
-- el permiso puede estar denegado. No se puede forzar —iOS, macOS y Android 13+
-- exigen que la persona acepte—, así que hace falta el respaldo.
--
-- Esta migración pone los cimientos: las plantillas dirigidas al USUARIO (las
-- que había estaban escritas para el administrador) y el reordenado de triggers
-- que permite contar la promoción de la cola como UN solo suceso.
-- ===============================================================


-- ---------------------------------------------------------------
-- 1. Plantillas dirigidas a la persona, no al administrador
--
-- Se usan tanto para el correo (cuerpo HTML) como para el push, que toma el
-- asunto como título y el cuerpo sin etiquetas como texto. Por eso conviene
-- que la primera frase se entienda suelta: en el móvil se ve poco más.
-- ---------------------------------------------------------------
insert into public.notification_templates (type, subject, body) values
('USER_RESERVATION_CONFIRMED', 'Reserva confirmada — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Reserva confirmada</h2><p>Tu reserva en <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}} está confirmada.</p></div>'),
('USER_RESERVATION_UPDATED', 'Tu reserva ha cambiado — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Tu reserva ha cambiado</h2><p>Tu reserva en <b>{{PropertyName}}</b> pasa a ser del {{StartDate}} al {{EndDate}} (antes, del {{OldStartDate}} al {{OldEndDate}}).</p></div>'),
('USER_RESERVATION_CANCELLED', 'Tu reserva se ha cancelado — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Tu reserva se ha cancelado</h2><p>Tu reserva en <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}} ya no está activa.</p></div>'),
('USER_WAITLIST_JOINED', 'Estás en la lista de espera — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Estás en la lista de espera</h2><p>Te hemos apuntado para <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}}. Si quien tiene esas fechas las cancela, se te asignarán automáticamente.</p></div>'),
('USER_WAITLIST_BEHIND_YOU', 'Alguien espera tus fechas — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Alguien espera tus fechas</h2><p>Se han apuntado a la lista de espera de <b>{{PropertyName}}</b> para el {{StartDate}} al {{EndDate}}, que ahora mismo son tuyas. No tienes que hacer nada; es solo para que lo sepas por si cambian tus planes.</p></div>'),
('USER_WAITLIST_PROMOTED', '¡Las fechas son tuyas! — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Las fechas son tuyas</h2><p>Se ha liberado <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}} y, como eras quien más tiempo llevaba esperando, la reserva ya está hecha a tu nombre.</p></div>'),
('USER_OUT_REPORT_DONE', 'Formulario recibido — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Formulario recibido</h2><p>Hemos recibido tu formulario de salida de <b>{{PropertyName}}</b>. Gracias.</p></div>'),
('ADMIN_WAITLIST_PROMOTED', 'La cola ha movido una reserva — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>La cola ha movido una reserva</h2><p><b>{{CancelledBy}}</b> ha cancelado <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}}, y las fechas han pasado automáticamente a <b>{{UserName}}</b>, que era el primero de la lista de espera.</p></div>'),
-- Los dos recordatorios del cron pasan a avisar TAMBIÉN al administrador, que
-- hasta ahora no se enteraba ni de las estancias que empiezan ni de los
-- formularios que faltan. Necesitan su propia redacción: las que había están
-- escritas en segunda persona para el interesado.
('ADMIN_INSPECTION_MISSING', 'Falta el formulario de salida — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Falta un formulario de salida</h2><p>La estancia de <b>{{UserName}}</b> en <b>{{PropertyName}}</b> termina hoy y todavía no hay formulario de salida.</p></div>'),
('ADMIN_PRE_STAY', 'Estancia a la vista — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Estancia a la vista</h2><p><b>{{UserName}}</b> entra en <b>{{PropertyName}}</b> el {{StartDate}}.</p></div>')
on conflict (type) do nothing;


-- ---------------------------------------------------------------
-- 2. Que la promoción de la cola sea UN suceso y no tres
--
-- Cuando alguien cancela y la cola promueve a otro, hoy ocurren tres cosas
-- seguidas: se borra una reserva, se crea otra y se promueve a alguien. Con un
-- aviso por cada una, el administrador recibiría tres correos y tres push por
-- un único hecho.
--
-- El obstáculo era el ORDEN: PostgreSQL dispara los triggers de una misma
-- operación por ORDEN ALFABÉTICO, y `trg_notify_change_reservation_ins_del` va
-- antes que `trg_promote_waitlist`. O sea que el aviso de cancelación salía
-- antes de que la promoción hubiera siquiera ocurrido, y ya no había forma de
-- retirarlo.
--
-- Se renombra el de avisos para que vaya el ÚLTIMO. Así la promoción puede
-- dejar una marca en la transacción y el aviso, al llegar después, sabe que
-- este borrado no es una cancelación cualquiera y se calla.
-- ---------------------------------------------------------------
drop trigger if exists trg_notify_change_reservation_ins_del on public.reservations;

create trigger trg_zz_notify_change_reservation
  after insert or delete on public.reservations
  for each row execute function public.notify_change_reservation();


-- ---------------------------------------------------------------
-- 3. El aviso de reservas respeta la marca de promoción
--
-- Si la marca está puesta, este INSERT (la reserva del promovido) o este DELETE
-- (la cancelación que la provocó) forman parte de una promoción, y de esa ya
-- avisa promote_waitlist_on_cancel con un único mensaje que cuenta la historia
-- entera. Aquí solo hay que no duplicarlo.
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
  v_old_start timestamptz;
  v_old_end   timestamptz;
begin
  -- Marca puesta por promote_waitlist_on_cancel: la promoción ya se cuenta
  -- sola. coalesce porque current_setting devuelve NULL la primera vez.
  if coalesce(current_setting('app.promocion_cola', true), '') <> '' then
    return coalesce(new, old);
  end if;

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
    'oldStartDate',  v_old_start,
    'oldEndDate',    v_old_end
  ));

  return coalesce(new, old);
end;
$$;

revoke execute on function public.notify_change_reservation() from public;


-- ---------------------------------------------------------------
-- 4. La promoción marca la transacción y manda el aviso conjunto
--
-- Sustituye la llamada a notify-waitlist, que se retira: su trabajo (avisar al
-- promovido) pasa a formar parte de este único mensaje.
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
    if not exists (
      select 1 from public.reservations r
      where r.property_id = w.property_id
        and r.start_date < w.end_date
        and r.end_date > w.start_date
    ) then
      -- La marca va ANTES del insert: el trigger de avisos de esa inserción se
      -- dispara dentro de esta misma llamada y tiene que verla ya puesta.
      perform set_config('app.promocion_cola', w.id::text, true);

      insert into public.reservations
        (property_id, family_group_id, created_by_id, start_date, end_date, guest_count, notes)
      values
        (w.property_id, w.family_group_id, w.requested_by_id, w.start_date, w.end_date,
         w.guest_count, w.notes)
      returning id into v_new_id;

      update public.reservation_waitlist
        set status = 'promoted', updated_at = now()
        where id = w.id;

      perform public.post_notify_changes(jsonb_build_object(
        'event',             'waitlist_promoted',
        'reservationId',     v_new_id,
        'propertyId',        w.property_id,
        'createdById',       w.requested_by_id,   -- el promovido
        'cancelledByUserId', old.created_by_id,   -- quien liberó las fechas
        'actorId',           auth.uid(),
        'startDate',         w.start_date,
        'endDate',           w.end_date,
        'guestCount',        w.guest_count
      ));

      exit;  -- solo se promueve uno por cancelación.
    end if;
  end loop;

  return old;
end;
$$;

revoke execute on function public.promote_waitlist_on_cancel() from public;


-- ---------------------------------------------------------------
-- 5. Al apuntarse a la cola se avisa también a quien tiene esas fechas
--
-- Se resuelve aquí, en la base de datos, porque es donde está el dato: la
-- reserva que solapa con lo solicitado. La Edge Function no tendría por qué
-- saber cómo se calcula un solape.
-- ---------------------------------------------------------------
create or replace function public.notify_change_waitlist()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_bloqueador uuid;
begin
  select r.created_by_id into v_bloqueador
    from public.reservations r
   where r.property_id = new.property_id
     and r.start_date < new.end_date
     and r.end_date > new.start_date
     and not r.is_maintenance
   limit 1;

  perform public.post_notify_changes(jsonb_build_object(
    'event',        'waitlist_joined',
    'waitlistId',   new.id,
    'propertyId',   new.property_id,
    'createdById',  new.requested_by_id,  -- el que se apunta
    'bloqueadorId', v_bloqueador,         -- el que tiene esas fechas ahora
    'actorId',      auth.uid(),
    'startDate',    new.start_date,
    'endDate',      new.end_date,
    'guestCount',   new.guest_count
  ));
  return new;
end;
$$;

revoke execute on function public.notify_change_waitlist() from public;
