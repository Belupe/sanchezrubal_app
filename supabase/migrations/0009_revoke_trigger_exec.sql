-- ===============================================================
-- 0009_revoke_trigger_exec.sql — Endurecimiento
-- ===============================================================
-- La función de trigger enforce_max_reservation_days no debe ser
-- llamable por la API (el trigger se dispara igualmente).
-- run_sorteo SÍ es un RPC intencional (lo llama la app; self-chequea
-- que el usuario es admin principal), así que se deja con execute para
-- authenticated.
-- ===============================================================
revoke execute on function public.enforce_max_reservation_days() from public;
