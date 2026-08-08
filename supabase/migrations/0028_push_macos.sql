-- ===============================================================
-- 0028_push_macos.sql — Admitir tokens de push de macOS
--
-- device_tokens.platform llevaba desde 0001 un CHECK con solo
-- ('android','ios','web'). El registro del token en macOS habría fallado
-- contra la base de datos incluso con APNs y Firebase bien configurados, y
-- el fallo se vería como un push que "no funciona" sin más pista: saveToken()
-- se llama sin await desde el listener de onTokenRefresh.
--
-- No se añaden 'windows' ni 'linux': Flutter no tiene push nativo ahí, así
-- que un token de esas plataformas solo podría llegar por error.
-- ===============================================================

alter table public.device_tokens
  drop constraint if exists device_tokens_platform_check;

alter table public.device_tokens
  add constraint device_tokens_platform_check
  check (platform in ('android','ios','macos','web'));
