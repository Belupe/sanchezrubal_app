-- ===============================================================
-- 0022_security_auditoria2.sql — Endurecimiento de la 2ª auditoría (BD)
--
-- Todos los hallazgos verificados contra el código real. No se editan
-- migraciones aplicadas: solo ADD CONSTRAINT / CREATE OR REPLACE / triggers
-- nuevos / revokes / seed / cron. Sin cambio de función visible.
--
--   [2M-02]+[2L-09] CHECKs de tamaño/rango (image, guest_count, jsonb/text).
--   [2M-03]+[2L-15] Auditoría de reservas: sin PII (guests_list/notes) y
--                   atribuida al creador real (arregla la promoción de cola).
--   [2L-07]         Tope de device_tokens por usuario.
--   [2L-08]         Topes holgados de reservas/cola por usuario.
--   [2L-17]         out_reports.property_id derivado de la reserva.
--   [2L-05]         Revoca los default privileges amplios a authenticated.
--   [2I-04]         REVOKE CREATE en el esquema public a PUBLIC.
--   PRE_STAY        Plantilla + cron del correo de pre-estancia.
-- ===============================================================


-- ===============================================================
-- [2M-02]+[2L-09] Límites de tamaño y rango. Ningún cliente legítimo los
-- supera (avatares/notas normales), así que no cambia la función visible;
-- cortan el bloat/DoS de blobs base64 y jsonb sin cota. Las tablas están
-- prácticamente vacías (pre-lanzamiento), así que ADD CONSTRAINT no aborta.
-- ===============================================================

-- Avatares/imagen: text que guarda URL o base64. Se acota el tamaño.
alter table public.profiles
  drop constraint if exists profiles_image_size_chk;
alter table public.profiles
  add constraint profiles_image_size_chk
  check (image is null or length(image) <= 700000);      -- ~512 KB base64

alter table public.properties
  drop constraint if exists properties_image_size_chk;
alter table public.properties
  add constraint properties_image_size_chk
  check (image is null or length(image) <= 1500000);      -- ~1,1 MB base64

alter table public.profiles
  drop constraint if exists profiles_ui_prefs_size_chk;
alter table public.profiles
  add constraint profiles_ui_prefs_size_chk
  check (ui_preferences is null or length(ui_preferences::text) <= 8192);

-- Reservas: cota de nº de invitados y tamaño de jsonb/text.
alter table public.reservations
  drop constraint if exists reservations_guest_count_chk;
alter table public.reservations
  add constraint reservations_guest_count_chk
  check (guest_count between 1 and 50);

alter table public.reservations
  drop constraint if exists reservations_guests_list_size_chk;
alter table public.reservations
  add constraint reservations_guests_list_size_chk
  check (guests_list is null or length(guests_list::text) <= 65536);

alter table public.reservations
  drop constraint if exists reservations_notes_size_chk;
alter table public.reservations
  add constraint reservations_notes_size_chk
  check (notes is null or length(notes) <= 10000);

-- Cola: mismo criterio.
alter table public.reservation_waitlist
  drop constraint if exists waitlist_guest_count_chk;
alter table public.reservation_waitlist
  add constraint waitlist_guest_count_chk
  check (guest_count between 1 and 50);

alter table public.reservation_waitlist
  drop constraint if exists waitlist_notes_size_chk;
alter table public.reservation_waitlist
  add constraint waitlist_notes_size_chk
  check (notes is null or length(notes) <= 10000);

-- Informe de salida: jsonb/text acotados.
alter table public.out_reports
  drop constraint if exists out_reports_media_size_chk;
alter table public.out_reports
  add constraint out_reports_media_size_chk
  check (media_urls is null or length(media_urls::text) <= 65536);

alter table public.out_reports
  drop constraint if exists out_reports_checklist_size_chk;
alter table public.out_reports
  add constraint out_reports_checklist_size_chk
  check (checklist is null or length(checklist::text) <= 65536);

alter table public.out_reports
  drop constraint if exists out_reports_notes_size_chk;
alter table public.out_reports
  add constraint out_reports_notes_size_chk
  check (notes is null or length(notes) <= 10000);


-- ===============================================================
-- [2M-03]+[2L-15] Auditoría de reservas sin PII + atribución correcta.
-- La versión de 0003 volcaba to_jsonb(old)+to_jsonb(new) COMPLETOS (incluye
-- guests_list/notes) → un admin de grupo podía recuperar de la auditoría datos
-- ya editados/borrados, y con retención de 12 meses. Además atribuía el CREATE
-- con auth.uid(), que en la promoción de cola (DEFINER) es el que CANCELA, no
-- el waitlister. Se redefine: solo campos NO sensibles, y actor = created_by_id
-- en el INSERT (coincide con auth.uid() en el flujo normal por la policy
-- reservations_insert; en la promoción pasa a ser el waitlister real).
-- ===============================================================
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
  v_actor   uuid;
begin
  if tg_op = 'INSERT' then
    v_action := 'CREATE'; v_entity := new.id; v_actor := new.created_by_id;
    v_details := jsonb_build_object(
      'property_id', new.property_id, 'family_group_id', new.family_group_id,
      'start_date', new.start_date, 'end_date', new.end_date,
      'guest_count', new.guest_count, 'is_maintenance', new.is_maintenance);
  elsif tg_op = 'UPDATE' then
    v_action := 'UPDATE'; v_entity := new.id; v_actor := auth.uid();
    v_details := jsonb_build_object(
      'old', jsonb_build_object(
        'property_id', old.property_id, 'family_group_id', old.family_group_id,
        'start_date', old.start_date, 'end_date', old.end_date,
        'guest_count', old.guest_count, 'is_maintenance', old.is_maintenance),
      'new', jsonb_build_object(
        'property_id', new.property_id, 'family_group_id', new.family_group_id,
        'start_date', new.start_date, 'end_date', new.end_date,
        'guest_count', new.guest_count, 'is_maintenance', new.is_maintenance));
  else -- DELETE
    v_action := 'DELETE'; v_entity := old.id; v_actor := auth.uid();
    v_details := jsonb_build_object(
      'property_id', old.property_id, 'family_group_id', old.family_group_id,
      'start_date', old.start_date, 'end_date', old.end_date,
      'guest_count', old.guest_count, 'is_maintenance', old.is_maintenance);
  end if;

  insert into public.audit_logs (action, entity_type, entity_id, details, user_id)
  values (v_action, 'reservation', v_entity, v_details, v_actor);

  return coalesce(new, old);
end;
$$;
revoke execute on function public.audit_reservations() from public;


-- ===============================================================
-- [2L-07] Tope de device_tokens por usuario. Antes de insertar uno nuevo, se
-- conservan los 9 más recientes (con el nuevo, 10 máx). Cierra el registro
-- ilimitado de tokens (bloat + amplificación del fan-out de send-push).
-- ===============================================================
create or replace function public.cap_device_tokens()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.device_tokens
   where user_id = new.user_id
     and id in (
       select id from public.device_tokens
        where user_id = new.user_id
        order by created_at desc
        offset 9
     );
  return new;
end;
$$;
revoke execute on function public.cap_device_tokens() from public;

drop trigger if exists trg_cap_device_tokens on public.device_tokens;
create trigger trg_cap_device_tokens
  before insert on public.device_tokens
  for each row execute function public.cap_device_tokens();


-- ===============================================================
-- [2L-08] Topes HOLGADOS por usuario (nunca se alcanzan en uso legítimo;
-- cortan la creación ilimitada de filas). Prioridad baja; caps generosos.
-- ===============================================================
create or replace function public.cap_reservations_per_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not new.is_maintenance
     and (select count(*) from public.reservations
           where created_by_id = new.created_by_id
             and end_date >= now()) >= 200 then
    raise exception 'Has alcanzado el máximo de reservas activas.'
      using errcode = '54000';
  end if;
  return new;
end;
$$;
revoke execute on function public.cap_reservations_per_user() from public;

drop trigger if exists trg_cap_reservations on public.reservations;
create trigger trg_cap_reservations
  before insert on public.reservations
  for each row execute function public.cap_reservations_per_user();

create or replace function public.cap_waitlist_per_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.reservation_waitlist
       where requested_by_id = new.requested_by_id
         and status = 'waiting') >= 100 then
    raise exception 'Has alcanzado el máximo de solicitudes en lista de espera.'
      using errcode = '54000';
  end if;
  return new;
end;
$$;
revoke execute on function public.cap_waitlist_per_user() from public;

drop trigger if exists trg_cap_waitlist on public.reservation_waitlist;
create trigger trg_cap_waitlist
  before insert on public.reservation_waitlist
  for each row execute function public.cap_waitlist_per_user();


-- ===============================================================
-- [2L-17] out_reports.property_id lo ponía el cliente sin validar contra la
-- reserva enlazada → podía archivar la inspección contra OTRA propiedad. Se
-- deriva SIEMPRE de la reserva cuando hay reservation_id (el cliente legítimo
-- ya manda la coincidente, así que no cambia la función visible).
-- ===============================================================
create or replace function public.seal_out_report_property()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.reservation_id is not null then
    new.property_id := (
      select property_id from public.reservations where id = new.reservation_id
    );
  end if;
  return new;
end;
$$;
revoke execute on function public.seal_out_report_property() from public;

drop trigger if exists trg_seal_out_report_property on public.out_reports;
create trigger trg_seal_out_report_property
  before insert or update on public.out_reports
  for each row execute function public.seal_out_report_property();


-- ===============================================================
-- [2L-05] 0010 hizo `alter default privileges … grant CRUD to authenticated`,
-- así que CUALQUIER tabla futura nacería con CRUD para authenticated y, si se
-- creara sin RLS, quedaría expuesta. Se revoca ese default (solo afecta a
-- tablas FUTURAS creadas por este rol; las actuales conservan su grant
-- explícito de 0010). En adelante se concede por tabla, como ya hace 0013.
-- ===============================================================
alter default privileges in schema public
  revoke select, insert, update, delete on tables from authenticated;


-- ===============================================================
-- [2I-04] Endurecimiento estándar: PUBLIC no debe poder CREATE en el esquema
-- public. En PG15+ (Supabase es PG17) ya es el default, así que es un no-op
-- inofensivo de defensa en profundidad. anon/authenticated solo necesitan
-- USAGE (0010) para resolver objetos vía PostgREST; nunca hacen CREATE.
-- ===============================================================
revoke create on schema public from public;


-- ===============================================================
-- PRE_STAY — correo de "tu estancia se acerca". La feature guardaba
-- custom_text en notification_settings pero ningún backend la enviaba. Se
-- completa: plantilla editable (aparece en el editor de la app) + cron diario
-- que invoca send-email (rama 'pre_stay_reminders').
-- ===============================================================
insert into public.notification_templates (type, subject, body) values
('PRE_STAY', 'Tu estancia se acerca — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Tu estancia se acerca</h2><p>Hola {{UserName}}, tu reserva en <b>{{PropertyName}}</b> empieza el {{StartDate}}.</p><p>{{CustomText}}</p></div>')
on conflict (type) do nothing;

-- 08:00 UTC a diario: avisa de las reservas que empiezan pronto (la ventana de
-- días y el filtro por notification_settings PRE_STAY los resuelve send-email).
select cron.schedule(
  'pre-stay-reminders',
  '0 8 * * *',
  $job$
  select net.http_post(
    url := 'https://pjceyplciujtrnxptwbx.supabase.co/functions/v1/send-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := jsonb_build_object('type', 'pre_stay_reminders')
  );
  $job$
);
