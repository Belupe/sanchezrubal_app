-- ===============================================================
-- 0001_init.sql — Esquema inicial de Portal Familia para Supabase
-- ===============================================================
-- Traducción del modelo Prisma/SQLite original (prisma/schema.prisma)
-- a PostgreSQL para Supabase Cloud, con los cambios acordados.
--
-- Diseño:
--   * IDs cuid (text) -> uuid (gen_random_uuid()). La migración de
--     datos (cutover) remapea los cuid antiguos a uuid nuevos.
--   * User -> public.profiles, ligada 1:1 a auth.users. passwordHash /
--     resetToken / resetTokenExpiry SE ELIMINAN: auth y reset de
--     contraseña los gestiona Supabase Auth (GoTrue).
--   * 5 roles: MEGA_ADMIN, PRINCIPAL_ADMIN, FAMILY_ADMIN,
--     FAMILY_SECOND_ADMIN, MEMBER. El rol (capacidad global) es
--     INDEPENDIENTE de family_group_id (pertenencia): un PRINCIPAL_ADMIN
--     puede estar en un grupo y conservar sus permisos.
--   * reservations.notes -> comentarios editables por el creador.
--   * audit_logs genérico (entity_type/entity_id) para registrar quién
--     crea/modifica/elimina reservas (y otras entidades).
--   * device_tokens -> push (FCM) para la app móvil.
--   * out_reports.media_urls (jsonb) -> fotos y vídeo en Supabase Storage.
--   * Campos "JSON string" -> jsonb. @updatedAt -> trigger set_updated_at().
--
-- RLS: se ACTIVA aquí en todas las tablas; las políticas van en 0002.
-- ===============================================================

create extension if not exists "pgcrypto";   -- gen_random_uuid()

-- Trigger genérico para mantener updated_at en cada UPDATE.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------
-- family_groups  (antes FamilyGroup)
-- owner_id (propietario = administrador familiar) se liga a profiles
-- con un ALTER al final (FK circular profiles<->family_groups).
-- ---------------------------------------------------------------
create table public.family_groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  color       text not null default '#3b82f6',
  owner_id    uuid,                           -- FK a profiles (ALTER al final)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------
-- profiles  (antes User) — ligada a auth.users de Supabase
-- ---------------------------------------------------------------
create table public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  email           text unique,
  name            text not null,
  role            text not null default 'MEMBER'
                    check (role in (
                      'MEGA_ADMIN',           -- superusuario del proyecto
                      'PRINCIPAL_ADMIN',      -- administrador principal
                      'FAMILY_ADMIN',         -- propietario de un grupo familiar
                      'FAMILY_SECOND_ADMIN',  -- coadministrador (p.ej. la pareja)
                      'MEMBER'                 -- miembro: lectura + crear reservas
                    )),
  ui_preferences  jsonb,
  image           text,                       -- avatar base64 o url
  family_group_id uuid references public.family_groups(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index profiles_family_group_id_idx on public.profiles(family_group_id);

alter table public.family_groups
  add constraint family_groups_owner_id_fkey
  foreign key (owner_id) references public.profiles(id) on delete set null;
create index family_groups_owner_id_idx on public.family_groups(owner_id);

-- ---------------------------------------------------------------
-- properties  (antes Property) — domicilios
-- ---------------------------------------------------------------
create table public.properties (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  description text,
  image       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------
-- reservations  (antes Reservation)
-- ---------------------------------------------------------------
create table public.reservations (
  id              uuid primary key default gen_random_uuid(),
  property_id     uuid not null references public.properties(id) on delete cascade,
  family_group_id uuid references public.family_groups(id) on delete set null,
  created_by_id   uuid not null references public.profiles(id),
  start_date      timestamptz not null,
  end_date        timestamptz not null,
  guest_count     integer not null default 1,
  guests_list     jsonb,                      -- antes "JSON string"
  notes           text,                       -- comentarios (editables por el creador)
  is_maintenance  boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index reservations_property_id_idx     on public.reservations(property_id);
create index reservations_family_group_id_idx on public.reservations(family_group_id);
create index reservations_created_by_id_idx   on public.reservations(created_by_id);
create index reservations_start_date_idx      on public.reservations(start_date);

-- ---------------------------------------------------------------
-- out_reports  (antes OutReport) — inspección post-estancia
-- media_urls: array jsonb de objetos {type:'photo'|'video', path}
-- apuntando a objetos de Supabase Storage. Solo created_at.
-- ---------------------------------------------------------------
create table public.out_reports (
  id              uuid primary key default gen_random_uuid(),
  property_id     uuid not null references public.properties(id) on delete cascade,
  reservation_id  uuid unique references public.reservations(id) on delete set null,
  check_in        timestamptz not null,
  check_out       timestamptz not null,
  general_status  text not null,
  damages         text,
  missing_items   text,
  notes           text,
  media_urls      jsonb,                      -- fotos y vídeo (Storage)
  rating          integer check (rating between 1 and 5),
  checklist       jsonb,
  created_at      timestamptz not null default now()
);
create index out_reports_property_id_idx on public.out_reports(property_id);

-- ---------------------------------------------------------------
-- system_config  (antes SystemConfig) — fila única 'global'
-- ---------------------------------------------------------------
-- NOTA seguridad: smtp_pass en claro replica el comportamiento actual.
-- Solo accesible por MEGA_ADMIN (ver RLS) y por Edge Functions (service
-- role). Idealmente mover a Supabase Vault más adelante.
create table public.system_config (
  id                    text primary key default 'global' check (id = 'global'),
  smtp_host             text,
  smtp_port             integer,
  smtp_user             text,
  smtp_pass             text,                 -- TODO: mover a Supabase Vault
  smtp_secure           boolean not null default false,
  base_url              text,                 -- dominio público (enlaces de email)
  max_reservation_days  integer not null default 30,
  updated_at            timestamptz not null default now()
);

-- ---------------------------------------------------------------
-- announcements  (antes Announcement) + N:M con properties
-- ---------------------------------------------------------------
create table public.announcements (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  content     text not null,
  author_id   uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now()
);
create index announcements_author_id_idx on public.announcements(author_id);

create table public.announcement_properties (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  property_id     uuid not null references public.properties(id) on delete cascade,
  primary key (announcement_id, property_id)
);

-- ---------------------------------------------------------------
-- audit_logs  (rediseñado, genérico) — registro de acciones
-- entity_id SIN FK para sobrevivir a borrados (auditoría de DELETE).
-- ---------------------------------------------------------------
create table public.audit_logs (
  id          uuid primary key default gen_random_uuid(),
  action      text not null,                  -- 'CREATE' | 'UPDATE' | 'DELETE'
  entity_type text not null,                  -- 'reservation' | 'property' | ...
  entity_id   uuid,                           -- sin FK a propósito
  details     jsonb,                          -- {old, new} o campos cambiados
  user_id     uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index audit_logs_entity_idx  on public.audit_logs(entity_type, entity_id);
create index audit_logs_user_id_idx on public.audit_logs(user_id);

-- ---------------------------------------------------------------
-- notification_templates  (antes NotificationTemplate)
-- ---------------------------------------------------------------
create table public.notification_templates (
  id          uuid primary key default gen_random_uuid(),
  type        text not null unique,
  subject     text not null,
  body        text not null,
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------
-- notification_settings  (antes NotificationSetting)
-- ---------------------------------------------------------------
create table public.notification_settings (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  type        text not null,
  is_active   boolean not null default true,
  custom_text text,
  updated_at  timestamptz not null default now(),
  unique (user_id, type)
);
create index notification_settings_user_id_idx on public.notification_settings(user_id);

-- ---------------------------------------------------------------
-- device_tokens — tokens de push (FCM) por dispositivo/usuario
-- ---------------------------------------------------------------
create table public.device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  token       text not null,
  platform    text check (platform in ('android','ios','web')),
  created_at  timestamptz not null default now(),
  unique (user_id, token)
);
create index device_tokens_user_id_idx on public.device_tokens(user_id);

-- ---------------------------------------------------------------
-- sorteos  (antes Sorteo) + resultados
-- ---------------------------------------------------------------
create table public.sorteos (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  created_by_id uuid not null references public.profiles(id),
  created_at    timestamptz not null default now()
);
create index sorteos_created_by_id_idx on public.sorteos(created_by_id);

create table public.sorteo_resultados (
  id              uuid primary key default gen_random_uuid(),
  sorteo_id       uuid not null references public.sorteos(id) on delete cascade,
  family_group_id uuid not null references public.family_groups(id) on delete cascade,
  premio          text not null               -- p.ej. "1ra Quincena Julio"
);
create index sorteo_resultados_sorteo_id_idx       on public.sorteo_resultados(sorteo_id);
create index sorteo_resultados_family_group_id_idx on public.sorteo_resultados(family_group_id);

-- ---------------------------------------------------------------
-- Triggers updated_at (solo tablas que lo tienen en el modelo)
-- ---------------------------------------------------------------
create trigger trg_family_groups_updated          before update on public.family_groups          for each row execute function public.set_updated_at();
create trigger trg_profiles_updated               before update on public.profiles               for each row execute function public.set_updated_at();
create trigger trg_properties_updated             before update on public.properties             for each row execute function public.set_updated_at();
create trigger trg_reservations_updated           before update on public.reservations           for each row execute function public.set_updated_at();
create trigger trg_system_config_updated          before update on public.system_config          for each row execute function public.set_updated_at();
create trigger trg_notification_templates_updated before update on public.notification_templates for each row execute function public.set_updated_at();
create trigger trg_notification_settings_updated  before update on public.notification_settings  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------
-- Auto-creación de profile al registrarse en auth.users.
-- name/role se leen de raw_user_meta_data (los pasa el admin al invitar);
-- por defecto MEMBER.
-- ---------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', new.email),
    coalesce(new.raw_user_meta_data->>'role', 'MEMBER')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------
-- RLS ON en todo public. Políticas en 0002_rls.sql.
-- ---------------------------------------------------------------
alter table public.family_groups           enable row level security;
alter table public.profiles                enable row level security;
alter table public.properties              enable row level security;
alter table public.reservations            enable row level security;
alter table public.out_reports             enable row level security;
alter table public.system_config           enable row level security;
alter table public.announcements           enable row level security;
alter table public.announcement_properties enable row level security;
alter table public.audit_logs              enable row level security;
alter table public.notification_templates  enable row level security;
alter table public.notification_settings   enable row level security;
alter table public.device_tokens           enable row level security;
alter table public.sorteos                 enable row level security;
alter table public.sorteo_resultados       enable row level security;
