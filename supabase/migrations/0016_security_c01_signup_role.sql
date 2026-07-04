-- ===============================================================
-- 0016_security_c01_signup_role.sql
-- [C-01] Escalada de privilegios a MEGA_ADMIN desde el signup.
--
-- handle_new_user() tomaba el rol de raw_user_meta_data->>'role', que lo
-- controla quien llama a GoTrue /signup. Con el registro por email activo
-- (default de Supabase) cualquiera de Internet podía crearse como MEGA_ADMIN.
--
-- Corrección: el alta fija SIEMPRE role = 'MEMBER'. Los roles elevados los
-- asigna EXCLUSIVAMENTE la Edge Function admin-users (service_role) tras
-- verificar al llamante y aplicar el techo de rol. El nombre se sigue
-- tomando de metadata (no es sensible).
--
-- El trigger on_auth_user_created (0001) ya apunta a esta función; solo se
-- redefine el cuerpo con CREATE OR REPLACE (no se recrea el trigger).
-- ===============================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', new.email),
    'MEMBER'  -- NO se toma de metadata: evita la escalada de rol en el signup
  );
  return new;
end;
$$;
