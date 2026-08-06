-- ===============================================================
-- 0024_family_admin_gestiona_su_grupo.sql — El admin familiar gestiona su grupo
--
-- Hasta ahora `profiles` solo se podía modificar siendo principal
-- (profiles_update_principal, con private.is_principal()). Un FAMILY_ADMIN no
-- podía cambiar el rol de nadie ni sacarlo del grupo, así que cada alta o baja
-- dentro de una casa tenía que pasar por un administrador principal.
--
-- Esta política es ADITIVA (las de RLS son permisivas): no toca las que ya hay.
--
-- Lo que permite, y solo eso:
--   - Cambiar el rol de alguien de SU grupo, entre secundario y miembro.
--   - EXPULSARLO, poniéndole family_group_id a NULL. La cuenta sigue viva; dar
--     de baja de verdad es destructivo e irreversible y se queda en manos de un
--     principal (admin-users/delete_user lo comprueba aparte).
--
-- Lo que NO permite:
--   - Tocarse a sí mismo (id <> auth.uid()): no puede ascenderse.
--   - Tocar a otro FAMILY_ADMIN ni a un principal: el USING exige que el rango
--     del destinatario sea INFERIOR a FAMILY_ADMIN.
--   - Ascender a nadie a su altura o por encima: el WITH CHECK exige lo mismo
--     sobre el rol NUEVO. Sin esa segunda mitad podría nombrar principales.
--   - Tocar a nadie de otro grupo, ni llevárselo al suyo: el grupo nuevo solo
--     puede ser NULL (expulsión) o el suyo propio.
--
-- Limitación conocida: RLS es por filas, no por columnas, así que un admin
-- familiar también puede editar `name`/`image` de los suyos. Se acepta: son
-- datos de su propia casa y no dan acceso a nada.
-- ===============================================================

drop policy if exists profiles_update_family_admin on public.profiles;

create policy profiles_update_family_admin on public.profiles
  for update to authenticated
  using (
    private.current_user_role() = 'FAMILY_ADMIN'
    and id <> auth.uid()
    and family_group_id is not null
    and family_group_id = private.current_user_group()
    and private.role_rank(role) < private.role_rank('FAMILY_ADMIN')
  )
  with check (
    private.current_user_role() = 'FAMILY_ADMIN'
    and id <> auth.uid()
    and private.role_rank(role) < private.role_rank('FAMILY_ADMIN')
    and (
      family_group_id is null
      or family_group_id = private.current_user_group()
    )
  );
