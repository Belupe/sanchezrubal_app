-- ===============================================================
-- 0015_realtime.sql — Habilita Supabase Realtime en las tablas clave
-- ===============================================================
-- Añade las tablas a la publicación `supabase_realtime` para que el
-- cliente reciba cambios en vivo (INSERT/UPDATE/DELETE). Realtime RESPETA
-- el RLS: cada usuario solo recibe lo que su política SELECT le permite.
--
-- La app usa estos eventos como SEÑAL para re-cargar (las queries con
-- joins se mantienen), de modo que calendario, reservas, cola y anuncios
-- se actualizan solos sin recargar a mano.
-- ===============================================================
alter publication supabase_realtime add table public.reservations;
alter publication supabase_realtime add table public.reservation_waitlist;
alter publication supabase_realtime add table public.announcements;
alter publication supabase_realtime add table public.properties;
