# Pendiente

Lista viva de lo acordado pero **no hecho todavía**. Aquí se acumula todo —cambios,
anotaciones, cosas a tener en cuenta— en vez de ir tocando y compilando por cada
detalle suelto.
---

## 1.5.2

### Notificaciones: un aparato, un dueño

La parte de base de datos **ya está aplicada en producción** (migración
`0048_tokens_push_por_dispositivo.sql`, 31/8/2026). Lo que queda es la app y el
despliegue de la función, que van juntos en esta versión.

**Por qué.** `device_tokens` tenía la unicidad por pareja `(user_id, token)`, así
que un mismo token podía pertenecer a dos usuarios a la vez. Como al cerrar
sesión el token tampoco se borraba, si alguien cerraba sesión en un iPad y
entraba otra persona quedaban las dos filas: los avisos del primero seguían
llegando al aparato que ya usaba el segundo. En una familia que comparte o
hereda aparatos, eso pasa.

**Ya hecho en la BD (no tocar, solo para contexto):**
- `unique (token)` añadida. La vieja `(user_id, token)` **sigue ahí a propósito**
  y no se puede quitar todavía (ver más abajo).
- Columna `last_seen` + índice, rellenada desde `created_at` en las filas viejas.
- `register_device_token(p_token, p_platform)` — alta y refresco en una sola
  llamada, con el reloj del servidor. El `on conflict (token)` es lo que reasigna
  el aparato en vez de duplicarlo.
- `forget_device_token(p_token)` — borrado del token propio al cerrar sesión.
- Cron `purge-device-tokens`, diario a las 03:15, borra lo que lleve **180 días**
  sin dar señales. El plazo es largo aposta: esto va de casas de vacaciones y hay
  quien no abre la app de octubre a marzo; con un plazo corto le borraríamos el
  token justo antes del sorteo de verano, que es el aviso que sí necesita. FCM
  invalida por su cuenta sobre los 270 días.

**Pendiente en la app** (ya escrito en el árbol de trabajo, sin compilar):
- [ ] `push_service.dart` — registro por RPC en vez de `upsert`, y
      `olvidarEsteDispositivo()`.
- [ ] `home_shell.dart` — llamar a `olvidarEsteDispositivo()` **antes** del
      `signOut()`: la función se apoya en `auth.uid()` y después de cerrar sesión
      ya no hay identidad.

**Pendiente de desplegar** (no se ha hecho todavía):
- [ ] `supabase functions deploy send-push` — amplía el catálogo de errores de FCM
      que se consideran "token muerto": añade `SENDER_ID_MISMATCH` y
      `THIRD_PARTY_AUTH_ERROR` (discordancia de entorno de APNs). `INVALID_ARGUMENT`
      queda **deliberadamente acotado**: FCM lo devuelve tanto por token inválido
      como por mensaje mal formado, así que borrarlo a ciegas podría vaciar la
      tabla entera si algún día enviamos un `data` incorrecto; solo cuenta si FCM
      señala explícitamente al campo del token.

### Deuda a saldar cuando toda la familia esté en 1.5.2

- [ ] Quitar la restricción vieja, ya redundante:
      ```sql
      alter table public.device_tokens
        drop constraint device_tokens_user_id_token_key;
      ```
      **No antes.** Las versiones publicadas (1.5.1 incluida) hacen
      `upsert(onConflict: 'user_id,token')`; si se quita, PostgREST deja de
      encontrarla y el registro de tokens falla en todo móvil sin actualizar.

### Limpieza puntual

- [ ] Borrar los 3 tokens de la etapa de pruebas de la cuenta Administrador
      (los 2 de iOS del 5/8 y el de Android del 29/8, que era el emulador).
      Las cuentas reales tienen 1 aparato cada una y están limpias.
