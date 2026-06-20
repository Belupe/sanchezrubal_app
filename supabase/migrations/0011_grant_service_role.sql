-- ===============================================================
-- 0011_grant_service_role.sql — Privilegios para service_role
-- ===============================================================
-- Las Edge Functions (admin-users, send-email, etc.) usan service_role.
-- Aunque service_role salta el RLS, sigue necesitando el privilegio de
-- TABLA (que no se concedió al crear las tablas por migración). Esto lo
-- arregla; service_role tiene acceso total (es el backend de confianza).
-- ===============================================================
grant usage on schema public to service_role;

grant all on all tables in schema public to service_role;

alter default privileges in schema public
  grant all on tables to service_role;
