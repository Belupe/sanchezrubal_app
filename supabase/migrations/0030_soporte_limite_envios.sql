-- ===============================================================
-- 0030_soporte_limite_envios.sql — Freno duradero para send-log
--
-- send-log llevaba un Map en memoria para evitar el doble envío, copiado del
-- que usa send-email. NO FUNCIONA: cada isolate de la Edge Function tiene el
-- suyo, y basta con que la segunda petición caiga en otro para que el freno no
-- exista. Comprobado en producción — dos llamadas seguidas mandaron dos
-- correos, cuando la segunda debía rebotar.
--
-- Aquí el coste de fallar no es cosmético: el SMTP tiene un tope mensual de
-- 1000 correos y cada registro puede pesar medio mega. El estado se mueve a la
-- base de datos, que sí es común a todos los isolates.
--
-- Además del anti-doble-toque hay un tope diario por usuario. Nadie manda
-- cinco registros legítimos el mismo día; quien lo intente es un botón atascado
-- o alguien probando, y en ambos casos conviene cortar.
--
-- Sin políticas RLS a propósito: solo la Edge Function (service_role, que lleva
-- BYPASSRLS) escribe y lee aquí. Ningún cliente tiene por qué verla.
-- ===============================================================

create table public.support_log_sends (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  es_fallo   boolean not null default false,
  bytes      integer,
  created_at timestamptz not null default now()
);

-- El índice sirve exactamente a la consulta que hace la función: el último
-- envío de un usuario y cuántos lleva hoy.
create index support_log_sends_user_created_idx
  on public.support_log_sends(user_id, created_at desc);

alter table public.support_log_sends enable row level security;
alter table public.support_log_sends force row level security;
