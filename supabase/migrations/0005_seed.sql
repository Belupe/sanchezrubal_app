-- ===============================================================
-- 0005_seed.sql — Datos semilla
-- ===============================================================
-- Fila única de configuración global (SMTP, base_url, límites).
-- La rellenará el MEGA_ADMIN desde la app. base_url debe ser el DOMINIO
-- público para que los enlaces de los correos no muestren la IP local.
-- ===============================================================

insert into public.system_config (id)
values ('global')
on conflict (id) do nothing;
