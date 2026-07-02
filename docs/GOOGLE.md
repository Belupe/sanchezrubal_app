# Google Play — publicación MANUAL (app privada familiar)

Alternativa/añadido al **APK self-hosted** ([ANDROID.md](ANDROID.md)). Aquí se sube la app a
**Google Play a mano**: no hay automatización desde GitHub (hacer `push` **no** sube nada a ninguna
tienda). Compilas un `.aab` y lo subes tú en Play Console.

Para una app **privada** de familia, Google Play **no tiene "no listado"** como Apple. Lo privado se
consigue con una **pista de prueba interna** (hasta ~100 testers por email, sin revisión completa,
casi instantánea) o **cerrada**. Producción = público en la tienda.

## ⚠️ Antes de nada: dos avisos

1. **Auto-update desactivado en la build de Play.** La app self-hosted se actualiza bajando el APK de
   tu servidor; **Play prohíbe eso**. El script `build-aab.ps1` compila con
   `--dart-define=ENABLE_SELF_UPDATE=false`, así que la build de Play **no** hace auto-update (Play
   actualiza a los usuarios por su cuenta). El APK self-hosted sigue igual (flag activo por defecto).
2. **Mismo `applicationId`** (`net.sanchezrubal.portal_familia`) que el APK self-hosted. Un móvil solo
   puede tener **una fuente instalada** a la vez; instalar la de Play sobre la self-hosted (o al revés)
   da conflicto de firma. **Elige un canal por dispositivo** — no mezcles en el mismo móvil.

## Requisitos

- **Cuenta de Google Play Console**: **25 $ pago ÚNICO** (no anual):
  https://play.google.com/console/signup
- **Keystore de subida**: ya lo tienes (`portal-familia-release.jks` + `android/key.properties`, ver
  [ANDROID.md](ANDROID.md)). Play lo usa como *clave de subida*. **Haz copia de seguridad**: si lo
  pierdes no podrás publicar updates.

## Pasos (a mano)

1. **Crea la app** en Play Console → *Crear aplicación*: nombre "Portal Familia", idioma, tipo *App*,
   *Gratuita*. Acepta las políticas.
2. **Sube la versión** en [pubspec.yaml](../app_flutter/pubspec.yaml) (`x.y.z+N`, sube el `+N` en cada
   entrega) y compila el bundle:
   ```powershell
   ./scripts/build-aab.ps1
   ```
   Deja el `.aab` en `dist/googleplay/portal-familia-<versión>-<build>.aab`.
3. **Play App Signing** (recomendado): al crear el primer *release*, deja que Google gestione la clave
   de firma de la app; tú firmas con tu `.jks` (la *clave de subida*). Es lo estándar y ya lo cubre tu
   `key.properties`.
4. **Elige la pista** (menú *Pruebas*):
   - **Prueba interna** → lo más rápido y privado para la familia. Sube el `.aab`, añade los **emails**
     de los testers y comparte el **enlace de aceptación**. Con él instalan desde Play.
   - (Alternativas: *Cerrada* por lista/Grupo de Google, o *Producción* = público.)
5. **Rellena las fichas obligatorias** que Play exige aunque sea privada: *política de privacidad*,
   *content rating*, *data safety* (declara que usas datos de Supabase/almacenamiento propio y push).
6. **Publica en la pista.** Los testers invitados instalan y, a partir de ahí, **Play les auto-actualiza**.
7. **Reparte el enlace de invitación.** En la pista, Play Console te da un **enlace de aceptación/opt-in**
   (`https://play.google.com/apps/internaltest/...`). Pégalo en `DOWNLOAD_ANDROID_PLAY_URL` del `.env` y
   ejecuta `./scripts/release.ps1`: la página de descargas mostrará **"Android — Instalar desde Google
   Play"** y ocultará el botón del APK self-hosted (no se pueden ofrecer los dos a la vez —mismo
   `applicationId`, conflicto de firma). Si vacías `DOWNLOAD_ANDROID_PLAY_URL`, Android vuelve al APK.

## Actualizaciones

Sube el `+N` en `pubspec.yaml`, ejecuta `./scripts/build-aab.ps1`, crea un *release* nuevo en la misma
pista con el `.aab` y publícalo. **Play actualiza solo** a los dispositivos. No interviene tu servidor
ni el auto-updater interno.

## ¿Hace falta algo de Google en el `.env`?

**No.** Para subir a mano no se necesita ningún secreto de Google en `.env`. El único "sistema de
Google" que ya usas es **FCM** (push), que sí está en `.env` (`FCM_SERVICE_ACCOUNT_FILE`) y es
independiente de Play.

Solo necesitarías credenciales de Google en `.env` si algún día **automatizas** la publicación
(GitHub Actions/fastlane subiendo el `.aab` por la API de Play), lo que requiere un **JSON de service
account** de Play. Eso es un desarrollo aparte que hoy no está montado.
