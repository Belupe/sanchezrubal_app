-- ===============================================================
-- 0007_cron.sql — Cron diario de recordatorios de inspección
-- ===============================================================
-- pg_cron invoca la Edge Function send-email cada día. La autentica con
-- un secreto aleatorio guardado en Vault.
--
-- PASO MANUAL tras aplicar: lee el secreto y ponlo como secret
-- CRON_SECRET de la Edge Function send-email:
--   select decrypted_secret from vault.decrypted_secrets where name='cron_secret';
-- ===============================================================
create extension if not exists supabase_vault;

select vault.create_secret(
  encode(gen_random_bytes(24), 'hex'),
  'cron_secret',
  'Secreto para que pg_cron invoque la Edge Function send-email'
);

-- 08:30 UTC todos los días. Ajusta la hora si quieres tu zona local.
select cron.schedule(
  'inspection-reminders',
  '30 8 * * *',
  $job$
  select net.http_post(
    url := 'https://pjceyplciujtrnxptwbx.supabase.co/functions/v1/send-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := jsonb_build_object('type', 'inspection_reminders')
  );
  $job$
);
