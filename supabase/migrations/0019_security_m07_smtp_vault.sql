-- ===============================================================
-- 0019_security_m07_smtp_vault.sql — [M-07] SMTP: TLS + contraseña en Vault
--
-- La contraseña SMTP se guardaba en texto plano en system_config.smtp_pass y el
-- panel del mega la descargaba al cliente. Se mueve a Supabase Vault (cifrada),
-- se deja de descargar al cliente (grant por columna) y las Edge Functions la
-- leen vía RPC service_role. (El forzado de TLS va en el código de las funciones.)
--
-- NOTA: esta migración va DESPUÉS de 0018 (que añadió max_reservation_days_cap);
-- por eso los grants de columna incluyen esa columna (si no, el panel del tope
-- dejaría de poder leerla/escribirla).
-- ===============================================================

create extension if not exists supabase_vault;

-- 1) Sembrar el secreto en Vault desde el valor actual y borrar la copia en claro.
do $$
declare v_pass text;
begin
  select smtp_pass into v_pass from public.system_config where id = 'global';
  if not exists (select 1 from vault.secrets where name = 'smtp_pass') then
    perform vault.create_secret(
      coalesce(v_pass, ''),
      'smtp_pass',
      'Contraseña SMTP de Portal Familia (antes en system_config.smtp_pass)'
    );
  end if;
end $$;

update public.system_config set smtp_pass = null where id = 'global';

-- 2) Lectura del secreto: SOLO service_role (Edge Functions).
create or replace function public.get_smtp_password()
returns text
language sql
security definer
set search_path = ''
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'smtp_pass';
$$;
revoke all on function public.get_smtp_password() from public;
grant execute on function public.get_smtp_password() to service_role;

-- 3) Escritura del secreto: SOLO el mega (panel), vía RPC.
create or replace function public.set_smtp_password(p_pass text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if not private.is_mega() then
    raise exception 'Solo el mega administrador' using errcode = '42501';
  end if;
  select id into v_id from vault.secrets where name = 'smtp_pass';
  if v_id is null then
    perform vault.create_secret(coalesce(p_pass, ''), 'smtp_pass',
      'Contraseña SMTP de Portal Familia');
  else
    perform vault.update_secret(v_id, coalesce(p_pass, ''));
  end if;
end $$;
revoke all on function public.set_smtp_password(text) from public;
grant execute on function public.set_smtp_password(text) to authenticated;

-- 4) Defensa en profundidad sobre la columna smtp_pass. 0010 concedió a
-- authenticated select/insert/update A NIVEL DE TABLA, así que un revoke de
-- columna sería un NO-OP. Se retira el privilegio de tabla y se reconcede columna
-- a columna dejando smtp_pass FUERA. El cliente ya selecciona columnas explícitas.
-- INCLUYE max_reservation_days_cap (columna añadida en 0018) para no romper el panel.
revoke select, insert, update on public.system_config from authenticated;

grant select
  (id, smtp_host, smtp_port, smtp_user, smtp_secure, base_url,
   max_reservation_days, max_reservation_days_cap, updated_at)
  on public.system_config to authenticated;

grant update
  (smtp_host, smtp_port, smtp_user, smtp_secure, base_url,
   max_reservation_days, max_reservation_days_cap)
  on public.system_config to authenticated;

-- (No se reconcede INSERT: la fila 'global' es única y sembrada por migración;
--  authenticated hace UPDATE, no INSERT. service_role conserva ALL de 0011.)
