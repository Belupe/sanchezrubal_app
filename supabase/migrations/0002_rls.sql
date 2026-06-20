-- ===============================================================
-- 0002_rls.sql — Helpers de rol + políticas RLS (Portal Familia)
-- ===============================================================
-- Jerarquía:
--   MEGA_ADMIN          -> todo, incluida system_config (SMTP).
--   PRINCIPAL_ADMIN     -> CRUD grupos/domicilios/anuncios/sorteos,
--                          gestiona miembros; ve todo. NO system_config.
--   FAMILY_ADMIN        -> propietario de su grupo; admin de su grupo.
--   FAMILY_SECOND_ADMIN -> coadministrador del mismo grupo.
--   MEMBER              -> lectura + crear reservas.
--
-- Rol (capacidad) es independiente de family_group_id (pertenencia).
--
-- Los helpers son SECURITY DEFINER para leer profiles sin recursión de
-- RLS (corren como owner y saltan RLS). auth.uid() = usuario actual.
-- Edge Functions usan service_role, que SALTA RLS por completo.
-- ===============================================================

create or replace function public.current_user_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.current_user_group()
returns uuid language sql stable security definer set search_path = public as $$
  select family_group_id from public.profiles where id = auth.uid();
$$;

create or replace function public.is_mega()
returns boolean language sql stable security definer set search_path = public as $$
  select public.current_user_role() = 'MEGA_ADMIN';
$$;

-- Admin global (mega o principal).
create or replace function public.is_principal()
returns boolean language sql stable security definer set search_path = public as $$
  select public.current_user_role() in ('MEGA_ADMIN','PRINCIPAL_ADMIN');
$$;

-- Admin del grupo gid: admin global, o family/second admin de ESE grupo.
create or replace function public.is_group_admin(gid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select
    public.current_user_role() in ('MEGA_ADMIN','PRINCIPAL_ADMIN')
    or (
      public.current_user_role() in ('FAMILY_ADMIN','FAMILY_SECOND_ADMIN')
      and public.current_user_group() is not distinct from gid
    );
$$;

-- ---------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------
create policy profiles_select on public.profiles for select to authenticated
  using ( id = auth.uid() or public.is_principal() or family_group_id = public.current_user_group() );
-- Update: uno mismo (un trigger en 0003 impide auto-escalar rol/grupo),
-- o un principal sobre cualquiera.
create policy profiles_update_self on public.profiles for update to authenticated
  using ( id = auth.uid() ) with check ( id = auth.uid() );
create policy profiles_update_principal on public.profiles for update to authenticated
  using ( public.is_principal() ) with check ( public.is_principal() );
create policy profiles_delete on public.profiles for delete to authenticated
  using ( public.is_principal() );
-- INSERT: sin política -> solo el trigger handle_new_user (definer) y el
-- service_role pueden crear filas. El alta de usuarios va por Auth invite.

-- ---------------------------------------------------------------
-- family_groups
-- ---------------------------------------------------------------
create policy family_groups_select on public.family_groups for select to authenticated
  using ( public.is_principal() or id = public.current_user_group() );
create policy family_groups_insert on public.family_groups for insert to authenticated
  with check ( public.is_principal() );
create policy family_groups_update on public.family_groups for update to authenticated
  using ( public.is_principal() ) with check ( public.is_principal() );
create policy family_groups_delete on public.family_groups for delete to authenticated
  using ( public.is_principal() );

-- ---------------------------------------------------------------
-- properties (domicilios) — visibles para todos; CRUD principal+
-- ---------------------------------------------------------------
create policy properties_select on public.properties for select to authenticated
  using ( true );
create policy properties_write on public.properties for all to authenticated
  using ( public.is_principal() ) with check ( public.is_principal() );

-- ---------------------------------------------------------------
-- reservations — calendario compartido visible para todos.
--   insert: cualquiera crea su propia reserva; mantenimiento solo principal.
--   update/delete: creador o admin del grupo (trigger 0003 bloquea que el
--                  creador cambie fechas).
-- ---------------------------------------------------------------
create policy reservations_select on public.reservations for select to authenticated
  using ( true );
create policy reservations_insert on public.reservations for insert to authenticated
  with check (
    created_by_id = auth.uid()
    and ( is_maintenance = false or public.is_principal() )
  );
create policy reservations_update on public.reservations for update to authenticated
  using ( created_by_id = auth.uid() or public.is_group_admin(family_group_id) )
  with check ( created_by_id = auth.uid() or public.is_group_admin(family_group_id) );
create policy reservations_delete on public.reservations for delete to authenticated
  using ( created_by_id = auth.uid() or public.is_group_admin(family_group_id) );

-- ---------------------------------------------------------------
-- out_reports (inspecciones) — creador de la reserva o admin del grupo.
-- ---------------------------------------------------------------
create policy out_reports_select on public.out_reports for select to authenticated
  using (
    public.is_principal()
    or exists (
      select 1 from public.reservations r
      where r.id = out_reports.reservation_id
        and ( r.created_by_id = auth.uid() or public.is_group_admin(r.family_group_id) )
    )
  );
create policy out_reports_insert on public.out_reports for insert to authenticated
  with check (
    exists (
      select 1 from public.reservations r
      where r.id = out_reports.reservation_id
        and ( r.created_by_id = auth.uid() or public.is_group_admin(r.family_group_id) )
    )
  );
create policy out_reports_update on public.out_reports for update to authenticated
  using (
    public.is_principal()
    or exists (
      select 1 from public.reservations r
      where r.id = out_reports.reservation_id
        and ( r.created_by_id = auth.uid() or public.is_group_admin(r.family_group_id) )
    )
  );
create policy out_reports_delete on public.out_reports for delete to authenticated
  using ( public.is_principal() );

-- ---------------------------------------------------------------
-- system_config — SOLO mega (contiene credenciales SMTP)
-- ---------------------------------------------------------------
create policy system_config_all on public.system_config for all to authenticated
  using ( public.is_mega() ) with check ( public.is_mega() );

-- ---------------------------------------------------------------
-- announcements (+ join) — todos leen; CRUD principal+
-- ---------------------------------------------------------------
create policy announcements_select on public.announcements for select to authenticated
  using ( true );
create policy announcements_insert on public.announcements for insert to authenticated
  with check ( public.is_principal() and author_id = auth.uid() );
create policy announcements_update on public.announcements for update to authenticated
  using ( public.is_principal() ) with check ( public.is_principal() );
create policy announcements_delete on public.announcements for delete to authenticated
  using ( public.is_principal() );

create policy announcement_properties_select on public.announcement_properties for select to authenticated
  using ( true );
create policy announcement_properties_write on public.announcement_properties for all to authenticated
  using ( public.is_principal() ) with check ( public.is_principal() );

-- ---------------------------------------------------------------
-- audit_logs — principal ve todo; el resto ve logs de reservas que le
-- atañen (creador o admin de su grupo). INSERT solo vía triggers/service.
-- ---------------------------------------------------------------
create policy audit_logs_select on public.audit_logs for select to authenticated
  using (
    public.is_principal()
    or (
      entity_type = 'reservation'
      and exists (
        select 1 from public.reservations r
        where r.id = audit_logs.entity_id
          and ( r.created_by_id = auth.uid() or public.is_group_admin(r.family_group_id) )
      )
    )
  );

-- ---------------------------------------------------------------
-- notification_templates — gestionadas por principal+
-- ---------------------------------------------------------------
create policy notification_templates_select on public.notification_templates for select to authenticated
  using ( public.is_principal() );
create policy notification_templates_write on public.notification_templates for all to authenticated
  using ( public.is_principal() ) with check ( public.is_principal() );

-- ---------------------------------------------------------------
-- notification_settings — propias; principal puede ver/gestionar
-- ---------------------------------------------------------------
create policy notification_settings_select on public.notification_settings for select to authenticated
  using ( user_id = auth.uid() or public.is_principal() );
create policy notification_settings_write on public.notification_settings for all to authenticated
  using ( user_id = auth.uid() or public.is_principal() )
  with check ( user_id = auth.uid() or public.is_principal() );

-- ---------------------------------------------------------------
-- device_tokens — solo el propio usuario
-- ---------------------------------------------------------------
create policy device_tokens_all on public.device_tokens for all to authenticated
  using ( user_id = auth.uid() ) with check ( user_id = auth.uid() );

-- ---------------------------------------------------------------
-- sorteos / resultados — todos leen; CRUD principal+
-- ---------------------------------------------------------------
create policy sorteos_select on public.sorteos for select to authenticated
  using ( true );
create policy sorteos_insert on public.sorteos for insert to authenticated
  with check ( public.is_principal() and created_by_id = auth.uid() );
create policy sorteos_write on public.sorteos for update to authenticated
  using ( public.is_principal() ) with check ( public.is_principal() );
create policy sorteos_delete on public.sorteos for delete to authenticated
  using ( public.is_principal() );

create policy sorteo_resultados_select on public.sorteo_resultados for select to authenticated
  using ( true );
create policy sorteo_resultados_write on public.sorteo_resultados for all to authenticated
  using ( public.is_principal() ) with check ( public.is_principal() );
