-- ===============================================================
-- 0010_grant_privileges.sql — Privilegios de tabla para la API
-- ===============================================================
-- Las tablas se crearon vía migración sin los GRANT por defecto de
-- Supabase, así que el rol `authenticated` no tenía privilegio de tabla
-- (el RLS ya estaba, pero el RLS se aplica DESPUÉS del privilegio de
-- tabla). Esto concede los privilegios; el RLS sigue decidiendo QUÉ
-- filas ve/cambia cada usuario.
-- ===============================================================
grant usage on schema public to anon, authenticated;

grant select, insert, update, delete
  on all tables in schema public to authenticated;

-- Tablas futuras creadas por este rol heredan los privilegios:
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
