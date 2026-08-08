-- ===============================================================
-- 0032_arreglar_restos_de_family_group_id.sql
--
-- DOS FALLOS EN PRODUCCIÓN, mismo origen. La migración 0025 movió la
-- pertenencia al grupo de `profiles.family_group_id` a `group_members` y
-- eliminó la columna, pero de las tres funciones que la leían solo actualizó
-- una (seal_reservation_group). Las otras dos se quedaron apuntando a una
-- columna que ya no existe, y en plpgsql eso no falla al desplegar: falla en
-- EJECUCIÓN, la primera vez que alguien pasa por ahí.
--
--   1) seal_waitlist_group()  ->  APUNTARSE A LA LISTA DE ESPERA estaba roto.
--      Cualquier INSERT en reservation_waitlist moría con
--      «column p.family_group_id does not exist». La cola está vacía, así que
--      probablemente nadie lo intentó todavía.
--
--   2) profiles_guard()  ->  UN USUARIO NORMAL NO PODÍA EDITAR SU PROPIO
--      PERFIL (nombre, foto). Moría con «record "new" has no field
--      "family_group_id"». Solo afectaba a los NO principales, porque los
--      principales salen antes por otra rama: por eso pasó desapercibido, la
--      cuenta con la que se prueba todo es la de administrador.
--
-- Lo encontró la batería de supabase/tests/reglas_criticas.sql al intentar
-- montar su escenario. Ninguna de las dos cosas la habría delatado un
-- despliegue ni `flutter analyze`.
-- ===============================================================


-- ---------------------------------------------------------------
-- 1. La cola: se sella con el grupo del solicitante, leído de donde vive
--    ahora. Espeja exactamente a seal_reservation_group().
-- ---------------------------------------------------------------
create or replace function public.seal_waitlist_group()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  -- El LIMIT 1 es inofensivo mientras exista UNIQUE(user_id) en group_members.
  -- Si algún día se admiten varios grupos por persona, AQUÍ hay que decidir en
  -- nombre de cuál se apunta a la cola (misma nota que en las reservas).
  new.family_group_id := (
    select m.group_id from public.group_members m
     where m.user_id = new.requested_by_id limit 1
  );
  return new;
end;
$$;

revoke execute on function public.seal_waitlist_group() from public;


-- ---------------------------------------------------------------
-- 2. El guardián de perfiles: se cae la línea que congelaba el grupo.
--
-- Ya no hay nada que congelar en `profiles`: la pertenencia está en
-- `group_members`, que tiene sus propias políticas. Congelar `role` y `email`
-- sigue teniendo sentido y se mantiene tal cual.
-- ---------------------------------------------------------------
create or replace function public.profiles_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_actor_rank int;
begin
  if auth.uid() is null then
    return new;
  end if;

  if not private.is_principal() then
    new.role := old.role;
    -- Aquí iba `new.family_group_id := old.family_group_id`. La columna se
    -- eliminó en 0025 y la pertenencia vive en group_members, protegida por
    -- sus propias políticas.
    new.email := old.email;   -- [B-02] anti-envenenamiento de admin-users
    return new;
  end if;

  if private.is_mega() then
    return new;
  end if;

  if new.role is distinct from old.role then
    v_actor_rank := private.role_rank(private.current_user_role());
    if private.role_rank(new.role) >= v_actor_rank then
      raise exception 'No puedes asignar un rol igual o superior al tuyo.'
        using errcode = '42501';
    end if;
    if private.role_rank(old.role) >= v_actor_rank then
      raise exception 'No puedes cambiar el rol de un usuario de rango igual o superior al tuyo.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.profiles_guard() from public;
