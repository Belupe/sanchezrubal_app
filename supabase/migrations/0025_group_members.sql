-- ===============================================================
-- 0025_group_members.sql — Separar el rol GLOBAL del rol DENTRO del grupo
--
-- `profiles.role` hacía dos trabajos a la vez: decía qué eres en toda la app Y
-- qué eres dentro de tu casa. Los cinco valores eran en realidad dos jerarquías
-- distintas metidas en la misma columna:
--
--     globales : MEGA_ADMIN, PRINCIPAL_ADMIN
--     de grupo : FAMILY_ADMIN, FAMILY_SECOND_ADMIN, MEMBER
--
-- Consecuencia: un mega administrador que se apunta a su propia casa tenía que
-- ELEGIR entre las dos, cuando son ortogonales. No había forma de decir "mega
-- administrador globalmente, un miembro más en esta casa".
--
-- A partir de aquí:
--     profiles.role                          MEGA_ADMIN | PRINCIPAL_ADMIN | USER
--     group_members(group_id, user_id, role) FAMILY_ADMIN | FAMILY_SECOND_ADMIN | MEMBER
--
-- POR QUÉ UNIQUE(user_id): la tabla admite de por sí varios grupos por persona,
-- pero eso hoy rompe seal_reservation_group(), que sella a qué casa pertenece
-- una reserva copiando el grupo del que la crea. Con dos grupos esa pregunta no
-- tiene respuesta: habría que preguntar en cada reserva de parte de qué casa se
-- hace. Se deja la restricción hasta decidir eso; quitarla es una línea.
--
-- Gracias a ella, private.current_user_group() conserva la firma (devuelve un
-- uuid), así que las políticas que comparan `family_group_id = current_user_group()`
-- en reservations, reservation_waitlist y family_groups NO se tocan.
--
-- OJO: `family_group_id` sigue existiendo en `reservations` y en
-- `reservation_waitlist`, y ahí es correcto: no es pertenencia, es a qué casa
-- pertenece esa reserva. La que desaparece es SOLO la de `profiles`.
-- ===============================================================

-- ---------------------------------------------------------------------
-- 1) La tabla de pertenencia
-- ---------------------------------------------------------------------
create table if not exists public.group_members (
  group_id   uuid not null references public.family_groups(id) on delete cascade,
  user_id    uuid not null references public.profiles(id)      on delete cascade,
  role       text not null default 'MEMBER'
             check (role in ('FAMILY_ADMIN','FAMILY_SECOND_ADMIN','MEMBER')),
  created_at timestamptz not null default now(),
  primary key (group_id, user_id),
  -- Una persona, un grupo (de momento). Ver la cabecera.
  constraint group_members_un_grupo_por_persona unique (user_id)
);

create index if not exists group_members_group_idx on public.group_members(group_id);

-- ---------------------------------------------------------------------
-- 2) Volcar lo que ya hay
-- ---------------------------------------------------------------------
-- Quien tuviera un rol de grupo lo conserva. A un mega/principal que estuviera
-- en una casa se le pone MEMBER: su poder viene del rol global, que no se toca.
insert into public.group_members (group_id, user_id, role)
select p.family_group_id, p.id,
       case
         when p.role in ('FAMILY_ADMIN','FAMILY_SECOND_ADMIN','MEMBER') then p.role
         else 'MEMBER'
       end
from public.profiles p
where p.family_group_id is not null
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 3) profiles.role pasa a ser SOLO global
-- ---------------------------------------------------------------------
alter table public.profiles drop constraint if exists profiles_role_check;

update public.profiles
   set role = 'USER'
 where role in ('FAMILY_ADMIN','FAMILY_SECOND_ADMIN','MEMBER');

alter table public.profiles
  add constraint profiles_role_check
  check (role in ('MEGA_ADMIN','PRINCIPAL_ADMIN','USER'));

alter table public.profiles alter column role set default 'USER';

-- El trigger de alta creaba los perfiles como 'MEMBER', que ya no es un rol
-- global válido. Sigue SIN leer el rol de la metadata: eso permitiría escalar
-- privilegios en el registro [C-01].
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  insert into public.profiles (id, email, name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', new.email),
    'USER'  -- NO se toma de metadata: evita la escalada de rol en el signup
  );
  return new;
end;
$function$;

-- ---------------------------------------------------------------------
-- 4) Ayudantes
-- ---------------------------------------------------------------------
-- Todos SECURITY DEFINER: leen group_members saltándose el RLS. Es imprescindible
-- — las políticas de group_members los usan, y sin esto habría recursión infinita.

-- Misma firma que antes (un uuid), sostenida por el UNIQUE(user_id).
create or replace function private.current_user_group()
returns uuid
language sql stable security definer set search_path to 'public'
as $function$
  select m.group_id from public.group_members m where m.user_id = auth.uid() limit 1;
$function$;

-- Qué eres DENTRO de tu casa. Nada que ver con private.current_user_role(),
-- que es el rango global.
create or replace function private.current_group_role()
returns text
language sql stable security definer set search_path to 'public'
as $function$
  select m.role from public.group_members m where m.user_id = auth.uid() limit 1;
$function$;

-- El rango global ATRAVIESA: un mega/principal manda en cualquier grupo aunque
-- ahí figure como un miembro más.
create or replace function private.is_group_admin(gid uuid)
returns boolean
language sql stable security definer set search_path to 'public'
as $function$
  select
    private.current_user_role() in ('MEGA_ADMIN','PRINCIPAL_ADMIN')
    or (
      gid is not null
      and exists (
        select 1 from public.group_members m
         where m.user_id = auth.uid()
           and m.group_id = gid
           and m.role in ('FAMILY_ADMIN','FAMILY_SECOND_ADMIN')
      )
    );
$function$;

-- ---------------------------------------------------------------------
-- 5) El sellado de reservas lee de la tabla nueva
-- ---------------------------------------------------------------------
create or replace function public.seal_reservation_group()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.is_maintenance then
    new.family_group_id := null;
  else
    -- El LIMIT 1 es inofensivo mientras exista UNIQUE(user_id). Si algún día se
    -- admiten varios grupos, AQUÍ hay que decidir de parte de cuál se reserva.
    new.family_group_id := (
      select m.group_id from public.group_members m
       where m.user_id = new.created_by_id limit 1
    );
  end if;
  return new;
end;
$function$;

-- ---------------------------------------------------------------------
-- 6) Políticas de profiles que dependían de family_group_id
-- ---------------------------------------------------------------------
-- La pertenencia ya no está en la fila: se mira en group_members.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or private.is_principal()
    or exists (
      select 1 from public.group_members m
       where m.user_id = public.profiles.id
         and m.group_id = private.current_user_group()
    )
  );

-- Sobra: servía para que un admin familiar cambiara el rol y expulsara, y las
-- dos cosas viven ahora en group_members con sus propias políticas (abajo).
-- Además ya no puede tocar `profiles`, así que tampoco puede editar el nombre ni
-- la foto de nadie: la limitación que habíamos aceptado en la 0024 se cierra sola.
drop policy if exists profiles_update_family_admin on public.profiles;

-- ---------------------------------------------------------------------
-- 7) RLS de group_members
-- ---------------------------------------------------------------------
alter table public.group_members enable row level security;

-- Ver: lo tuyo, lo de tu casa, y los principales todo.
drop policy if exists group_members_select on public.group_members;
create policy group_members_select on public.group_members
  for select to authenticated
  using (
    user_id = auth.uid()
    or private.is_principal()
    or group_id = private.current_user_group()
  );

-- Dar de alta a alguien en un grupo. Un admin familiar solo en el suyo y solo
-- por debajo de sí mismo.
drop policy if exists group_members_insert on public.group_members;
create policy group_members_insert on public.group_members
  for insert to authenticated
  with check (
    private.is_principal()
    or (
      private.current_group_role() = 'FAMILY_ADMIN'
      and group_id = private.current_user_group()
      and role in ('FAMILY_SECOND_ADMIN','MEMBER')
    )
  );

-- Cambiar el permiso de alguien. El USING mira la fila vieja y el WITH CHECK la
-- nueva: sin las dos mitades, un admin familiar podría ascender a alguien por
-- encima de sí mismo. Y no puede tocarse a sí mismo, así que no se asciende.
drop policy if exists group_members_update on public.group_members;
create policy group_members_update on public.group_members
  for update to authenticated
  using (
    private.is_principal()
    or (
      private.current_group_role() = 'FAMILY_ADMIN'
      and group_id = private.current_user_group()
      and user_id <> auth.uid()
      and role in ('FAMILY_SECOND_ADMIN','MEMBER')
    )
  )
  with check (
    private.is_principal()
    or (
      private.current_group_role() = 'FAMILY_ADMIN'
      and group_id = private.current_user_group()
      and user_id <> auth.uid()
      and role in ('FAMILY_SECOND_ADMIN','MEMBER')
    )
  );

-- Expulsar. Borrar la FILA saca del grupo; la cuenta no se toca.
drop policy if exists group_members_delete on public.group_members;
create policy group_members_delete on public.group_members
  for delete to authenticated
  using (
    private.is_principal()
    or (
      private.current_group_role() = 'FAMILY_ADMIN'
      and group_id = private.current_user_group()
      and user_id <> auth.uid()
      and role in ('FAMILY_SECOND_ADMIN','MEMBER')
    )
  );

grant select, insert, update, delete on public.group_members to authenticated;
grant all on public.group_members to service_role;

-- ---------------------------------------------------------------------
-- 8) Retirar la columna vieja
-- ---------------------------------------------------------------------
alter table public.profiles drop column if exists family_group_id;
