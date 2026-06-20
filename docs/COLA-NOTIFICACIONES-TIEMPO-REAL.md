# Cola de reservas + Notificaciones (Push/Email) + Tiempo real

Guía de puesta en marcha de tres piezas que van juntas:

1. **Lista de espera (cola)** de reservas con promoción automática al cancelar.
2. **Notificaciones** de la cola por **push (FCM)** y **email**.
3. **Tiempo real** in-app (Supabase Realtime): calendario, reservas, cola y anuncios se
   actualizan solos en todos los dispositivos.

> El código ya está implementado y `flutter analyze` pasa limpio.
>
> **Estado actual (hecho automáticamente):**
> - ✅ Migraciones `0013`, `0014`, `0015` **aplicadas** a Supabase Cloud.
> - ✅ Edge Functions `send-push` y `notify-waitlist` **desplegadas** (ACTIVE, `verify_jwt=false`).
> - ✅ Realtime habilitado; `get_advisors` security sin avisos nuevos.
>
> **Lo que falta (solo lo puede hacer el usuario):** crear Firebase, `flutterfire configure`,
> fijar los valores de los secrets (`CRON_SECRET`, `FCM_SERVICE_ACCOUNT`) y recompilar las apps.
> Sin esto, la **cola y el tiempo real ya funcionan**; el **email** de la cola funciona en cuanto
> se fije `CRON_SECRET`; el **push** cuando se complete Firebase + secrets.

---

## Resumen de lo implementado

| Pieza | Archivos |
|---|---|
| Tabla cola + RLS + trigger de promoción | `supabase/migrations/0013_waitlist.sql` |
| Plantillas de email de la cola | `supabase/migrations/0014_waitlist_templates.sql` |
| Realtime (publicación) | `supabase/migrations/0015_realtime.sql` |
| Envío push FCM (reutilizable) | `supabase/functions/send-push/` |
| Aviso de la cola (2 notif.) | `supabase/functions/notify-waitlist/` |
| Cliente Flutter | `models/waitlist_entry.dart`, `services/realtime_service.dart`, `services/push_service.dart`, `services/data_service.dart`, pantallas `reservation_form.dart` / `property_calendar_screen.dart` / `anuncios_screen.dart` / `casas_screen.dart`, `home_shell.dart`, `pubspec.yaml` |

**Cómo funciona la cola:** al intentar reservar unas fechas ocupadas, la app ofrece *apuntarse a
la lista de espera*. Si quien tiene la reserva la **cancela** (borra), un trigger `AFTER DELETE`
en `reservations` (`promote_waitlist_on_cancel`) toma al **primero de la cola** (orden FIFO) cuyas
fechas encajen, **le crea la reserva** y llama a la Edge Function `notify-waitlist`, que envía al
promovido **2 avisos** (push + email): «X ha cancelado» y «las fechas son tuyas».

---

## Paso 1 — Migraciones a Supabase Cloud ✅ HECHO

Aplicadas `0013_waitlist`, `0014_waitlist_templates`, `0015_realtime` (proyecto `SanchezRubal`,
ref `pjceyplciujtrnxptwbx`). Verificado: tabla `reservation_waitlist` con RLS y políticas, triggers
`trg_promote_waitlist` y `trg_enforce_waitlist_rules`, Realtime habilitado, `get_advisors` security
sin avisos nuevos.

> (Si tuvieras que reaplicarlas en otro entorno: ejecuta el contenido de esos ficheros de
> `supabase/migrations/` en orden, vía MCP / SQL Editor / `supabase db push`.)

---

## Paso 2 — Firebase (necesario para el push)

### 2.1 Crear proyecto y registrar las apps
1. Crea un proyecto en <https://console.firebase.google.com>.
2. **Android**: añade una app con package `net.sanchezrubal.portal_familia`.
3. **iOS**: añade una app con bundle id `net.sanchezrubal.portalFamilia`.
4. (Opcional) **Web** si quieres push en el navegador.

### 2.2 Configurar el cliente Flutter
```powershell
# Una vez (instala la CLI de FlutterFire):
dart pub global activate flutterfire_cli

cd app_flutter
flutterfire configure
```
Esto genera `lib/firebase_options.dart` y coloca:
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

Asegúrate de que el plugin de Google Services está en Gradle (lo añade FlutterFire; si no:
`com.google.gms.google-services` en `android/settings.gradle.kts` o `android/app/build.gradle.kts`).

> `push_service.dart` ya es defensivo: si falta la config, el push se desactiva solo y la app
> sigue funcionando.

### 2.3 iOS (APNs) — cuando exista la cuenta Apple
El push iOS necesita una **APNs Authentication Key** subida a Firebase (Project Settings →
Cloud Messaging). Requiere el Apple Developer Program (hoy en pausa). Android y web no lo necesitan.

---

## Paso 3 — Service account de FCM (envío server-side)

1. Firebase Console → **Project settings → Service accounts → Generate new private key**.
   Descarga el JSON (contiene `client_email`, `private_key`, `project_id`).
2. Guarda ese JSON en una ruta local (está en `.gitignore`: nunca se sube) y apunta a ella con
   `FCM_SERVICE_ACCOUNT_FILE` en tu `.env`. El adaptador (Paso 4) sube su contenido como el secret
   `FCM_SERVICE_ACCOUNT` que usa `send-push`. El `project_id` va dentro del propio JSON.

---

## Paso 4 — Secrets de las Edge Functions

Las funciones (`send-push`, `notify-waitlist`) ya están **desplegadas**. Lo único que falta es
**fijar los valores de los secrets**, que se hace desde el `.env` único con el adaptador del repo.

1. En tu `.env` (copia de `.env.example`) rellena:
   - `CRON_SECRET` = el `cron_secret` de Vault (debe COINCIDIR; léelo con
     `select decrypted_secret from vault.decrypted_secrets where name='cron_secret';`).
   - `FCM_SERVICE_ACCOUNT_FILE` = ruta al JSON de la service account (el del Paso 3).
2. Sube los secrets:
   ```powershell
   ./scripts/push-supabase-secrets.ps1     # (o .sh en Linux/Mac)
   ```
   El script lee el `.env`, toma el CONTENIDO del JSON y lo sube como `FCM_SERVICE_ACCOUNT`, junto
   con `CRON_SECRET` y los de MinIO. Los secrets de Supabase son a nivel de proyecto → valen para
   todas las funciones.

> El trigger de BD llama a `notify-waitlist` por HTTPS con `x-cron-secret`; `notify-waitlist` llama
> a `send-push` con el mismo secreto. Por eso **las dos** necesitan `CRON_SECRET`, y `send-push`
> además `FCM_SERVICE_ACCOUNT`. Si necesitas re-desplegar el código:
> `supabase functions deploy send-push notify-waitlist` (ambas con `--no-verify-jwt`).

---

## Paso 5 — Recompilar y distribuir la app

El push y `firebase_*` son cambios **nativos**, así que hay que recompilar y redistribuir por los
canales habituales (Android APK self-hosted / Windows / iOS):
```powershell
cd app_flutter
flutter pub get
flutter analyze
flutter run        # o build apk / build windows / build ipa con los --dart-define de siempre
```

---

## Verificación end-to-end

1. **Cola**: usuario A reserva unas fechas; usuario B intenta las mismas → acepta apuntarse a la
   lista. En el calendario del domicilio aparece B en la lista de espera con su posición.
2. **Promoción**: A cancela su reserva. Comprueba que:
   - se crea la reserva de B (queda traza en `audit_logs`),
   - la fila de la cola pasa a `promoted`,
   - B recibe **2 push** y **2 emails**.
3. **Tiempo real**: con A y B abiertos a la vez, la cancelación/promoción se refleja en ambos
   **sin recargar**.
4. **Push aislado**: inserta un token en `device_tokens` (Android) y llama a `send-push` con
   `x-cron-secret` para confirmar la recepción.

---

## `compose.yaml` — no necesita cambios

Las Edge Functions corren en **Supabase Cloud**, no en Docker. `compose.yaml` solo levanta MinIO y
el nginx de actualizaciones. Las claves de FCM son **secrets de Supabase** (Paso 4), no variables de
contenedor, así que no se toca `compose.yaml`.

## Notas y límites

- **iOS push**: pendiente de la cuenta Apple/APNs (distribución iOS en pausa). El resto funciona en
  Android/web; el email cubre iOS mientras tanto.
- **Borrar un domicilio entero** dispara la cancelación en cascada de sus reservas; la promoción de
  cola en ese caso es irrelevante (la cola del domicilio también se borra en cascada).
- El push usa *notification payload*, por lo que Android lo muestra en bandeja aunque la app esté
  cerrada, sin handler adicional.
