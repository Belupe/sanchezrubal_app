-- ===============================================================
-- reglas_criticas.sql — Las reglas cuyo fallo silencioso saldría caro
--
-- No cubre el esquema entero. Cubre lo que, si una migración futura lo
-- rompiera, NADIE se enteraría hasta que fuera un problema de verdad:
--
--   1. Un miembro normal NO puede tocar la reserva de otro.
--   2. El administrador de la casa SÍ puede (regla de la migración 0024).
--   3. Pero NO las de otra casa. Este es el límite que de verdad importa.
--   4. La cola adjudica al PRIMERO que se apuntó, no a cualquiera.
--
-- Las tres primeras dependen de las políticas RLS y de private.is_group_admin();
-- la cuarta, del trigger promote_waitlist_on_cancel de 0013.
--
-- CADA PRUEBA MONTA SU PROPIO ESCENARIO. La primera versión de este fichero no
-- lo hacía: daba por hecho que dos perfiles con rango global USER son ajenos
-- entre sí, y resultó que los dos que hay son administradores de la MISMA casa.
-- La prueba "fallaba" y el código estaba bien. Una prueba que depende de los
-- datos que haya ese día no vale para nada.
--
-- CÓMO SE EJECUTA
--   Entero, de una vez. Termina en ROLLBACK y no deja rastro, así que se puede
--   lanzar contra producción sin miedo:
--
--     psql "$DATABASE_URL" -f supabase/tests/reglas_criticas.sql
--
--   O pegándolo en el editor SQL de Supabase. Imprime una tabla con el estado
--   de cada regla y aborta si alguna falla.
--
-- POR QUÉ NO pgTAP: haría falta la extensión y un Docker levantado para la base
-- local. Esto corre con lo que ya hay.
-- ===============================================================

begin;

create temp table datos (clave text primary key, valor uuid);
create temp table resultado (n int, prueba text, ok boolean);

-- Dos perfiles cualesquiera que NO sean principales (un MEGA_ADMIN o un
-- PRINCIPAL_ADMIN pasa por encima de todo esto y no sirve para probarlo).
insert into datos
select 'usuario_a', id from public.profiles
 where role not in ('MEGA_ADMIN','PRINCIPAL_ADMIN') order by id limit 1;
insert into datos
select 'usuario_b', id from public.profiles
 where role not in ('MEGA_ADMIN','PRINCIPAL_ADMIN') order by id desc limit 1;

do $$
begin
  if (select count(*) from datos where clave in ('usuario_a','usuario_b')) < 2
     or (select valor from datos where clave='usuario_a')
        = (select valor from datos where clave='usuario_b') then
    raise exception 'Hacen falta AL MENOS DOS perfiles que no sean principales.';
  end if;
end $$;

-- Casa y grupo propios de la prueba.
with c as (insert into public.properties (name) values ('ZZZ casa de prueba (se revierte)') returning id)
insert into datos select 'casa', id from c;
with c as (insert into public.properties (name) values ('ZZZ casa de prueba 2 (se revierte)') returning id)
insert into datos select 'casa2', id from c;
with g as (insert into public.family_groups (name) values ('ZZZ grupo de prueba (se revierte)') returning id)
insert into datos select 'grupo_ajeno', id from g;

-- Se fuerza el escenario: los dos en el MISMO grupo, A miembro raso y B
-- administrador de esa casa. Se revierte al final como todo lo demás.
insert into datos select 'grupo_comun', group_id
  from public.group_members where user_id = (select valor from datos where clave='usuario_b');

update public.group_members set role = 'MEMBER'
 where user_id = (select valor from datos where clave='usuario_a');
update public.group_members set role = 'FAMILY_ADMIN'
 where user_id = (select valor from datos where clave='usuario_b');

-- Reserva de A, sellada automáticamente al grupo común (trigger de 0018/0025).
with r as (
  insert into public.reservations (property_id, created_by_id, start_date, end_date, guest_count)
  select (select valor from datos where clave='casa'),
         (select valor from datos where clave='usuario_a'),
         '2030-03-01T00:00:00Z', '2030-03-16T00:00:00Z', 2
  returning id)
insert into datos select 'reserva_de_a', id from r;

grant select on datos to authenticated;
grant select, insert on resultado to authenticated;


-- ===============================================================
-- 1. Un MIEMBRO normal no puede modificar la reserva de otro
--
-- RLS no lanza error: simplemente no ve la fila. Por eso se cuentan las filas
-- afectadas en vez de esperar una excepción.
-- ===============================================================
update public.group_members set role = 'MEMBER'
 where user_id = (select valor from datos where clave='usuario_b');

set local role authenticated;
select set_config('request.jwt.claims',
       json_build_object('sub', (select valor from datos where clave='usuario_b')::text,
                         'role', 'authenticated')::text, true);

with intento as (
  update public.reservations set guest_count = 3
   where id = (select valor from datos where clave='reserva_de_a')
  returning 1)
insert into resultado (n, prueba, ok)
select 1, 'Un MIEMBRO no puede modificar la reserva de otro', count(*) = 0 from intento;

reset role;
select set_config('request.jwt.claims', '', true);


-- ===============================================================
-- 2. El administrador de la casa SÍ puede (migración 0024)
--
-- El contrapunto de la anterior. Sin esto, una política demasiado estricta
-- pasaría la prueba 1 y rompería la app sin que nadie lo notara aquí.
-- ===============================================================
update public.group_members set role = 'FAMILY_ADMIN'
 where user_id = (select valor from datos where clave='usuario_b');

set local role authenticated;
select set_config('request.jwt.claims',
       json_build_object('sub', (select valor from datos where clave='usuario_b')::text,
                         'role', 'authenticated')::text, true);

with intento as (
  update public.reservations set guest_count = 4
   where id = (select valor from datos where clave='reserva_de_a')
  returning 1)
insert into resultado (n, prueba, ok)
select 2, 'El admin de la casa sí gestiona las de su grupo', count(*) = 1 from intento;

reset role;
select set_config('request.jwt.claims', '', true);


-- ===============================================================
-- 3. Un administrador NO puede tocar las reservas de OTRA casa
--
-- El límite de verdad. Se mueve a A a un grupo ajeno y se le crea una reserva
-- nueva ahí (el sellado ocurre al insertar, así que hace falta una reserva
-- posterior al cambio, en otra casa para no chocar con el solapamiento).
-- B sigue siendo administrador, pero de su grupo, no de este.
-- ===============================================================
update public.group_members set group_id = (select valor from datos where clave='grupo_ajeno')
 where user_id = (select valor from datos where clave='usuario_a');

with r as (
  insert into public.reservations (property_id, created_by_id, start_date, end_date, guest_count)
  select (select valor from datos where clave='casa2'),
         (select valor from datos where clave='usuario_a'),
         '2030-05-01T00:00:00Z', '2030-05-16T00:00:00Z', 2
  returning id)
insert into datos select 'reserva_ajena', id from r;

set local role authenticated;
select set_config('request.jwt.claims',
       json_build_object('sub', (select valor from datos where clave='usuario_b')::text,
                         'role', 'authenticated')::text, true);

with intento as (
  update public.reservations set guest_count = 5
   where id = (select valor from datos where clave='reserva_ajena')
  returning 1)
insert into resultado (n, prueba, ok)
select 3, 'Un admin NO alcanza las reservas de otra casa', count(*) = 0 from intento;

reset role;
select set_config('request.jwt.claims', '', true);


-- ===============================================================
-- 4. La cola adjudica al PRIMERO que se apuntó
--
-- Se apuntan B y luego A a las mismas fechas. Al cancelar la reserva que las
-- bloquea, el trigger debe crear la reserva a nombre de B (FIFO por
-- created_at). Es la regla más fácil de romper sin querer: basta con tocar el
-- ORDER BY del bucle y la cola pasa a ser una lotería.
-- ===============================================================
insert into public.reservation_waitlist
  (property_id, requested_by_id, start_date, end_date, guest_count, created_at)
values
  ((select valor from datos where clave='casa'),
   (select valor from datos where clave='usuario_b'),
   '2030-03-01T00:00:00Z', '2030-03-16T00:00:00Z', 2, now() - interval '2 hours'),
  ((select valor from datos where clave='casa'),
   (select valor from datos where clave='usuario_a'),
   '2030-03-01T00:00:00Z', '2030-03-16T00:00:00Z', 2, now() - interval '1 hour');

delete from public.reservations
 where id = (select valor from datos where clave='reserva_de_a');

insert into resultado (n, prueba, ok)
select 4, 'La cola adjudica al primero que se apuntó (FIFO)',
       count(*) = 1
       -- bool_and y no min(): Postgres no tiene min() para uuid.
       and bool_and(created_by_id = (select valor from datos where clave='usuario_b'))
  from public.reservations
 where property_id = (select valor from datos where clave='casa');


-- ===============================================================
-- Veredicto
-- ===============================================================
select n, prueba, case when ok then 'PASA' else 'FALLA' end as estado
  from resultado order by n;

do $$
declare fallidas int;
begin
  select count(*) into fallidas from resultado where not ok;
  if fallidas > 0 then
    raise exception '% regla(s) crítica(s) ROTA(S). Mira la tabla de arriba.', fallidas;
  end if;
  raise notice 'Todas las reglas críticas se cumplen.';
end $$;

rollback;
