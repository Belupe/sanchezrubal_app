# Google Play — publicación MANUAL (app privada familiar)

Android se distribuye por **Google Play a mano** (el APK self-hosted quedó retirado; el keystore de
[ANDROID.md](ANDROID.md) se reutiliza como *clave de subida*). No hay automatización desde GitHub
(hacer `push` **no** sube nada a ninguna tienda): compilas un `.aab` y lo subes tú en Play Console.

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
   Play"**. Google Play es el **único canal de Android** en la página (ya no se ofrece APK de descarga
   directa). Si dejas `DOWNLOAD_ANDROID_PLAY_URL` vacío, el botón de Android no aparece.


## Política de privacidad

Play la exige **aunque la app sea privada**. Está escrita y vive en
`server/updates/privacidad.html`; se sube por SFTP junto a `index.html` y el
nginx ya la sirve (`try_files $uri`), sin tocar la configuración:

    https://app.sanchezrubal.net/privacidad.html

Está redactada a partir de lo que la app hace **de verdad** (esquema + código),
no de una plantilla. Si cambia lo que se recoge, hay que actualizarla: sus
afirmaciones y el formulario de abajo tienen que seguir cuadrando, porque Play
compara y una contradicción es motivo de rechazo.

## Seguridad de los datos — qué marcar

El formulario más largo y el que más gente rellena mal, casi siempre por
omisión. Esto sale de leer qué guarda cada tabla y qué sube la app.

**Preguntas de cabecera**

| Pregunta | Respuesta |
|---|---|
| ¿Recopila o comparte datos de usuario? | **Sí** |
| ¿Se cifran en tránsito? | **Sí** (todo va por HTTPS) |
| ¿Se pueden solicitar la eliminación? | **Sí** (por correo, y el perfil se edita en la app) |
| ¿Está dirigida a menores? | **No** |

**Tipos de datos: RECOPILADOS y no compartidos.** Ninguno es opcional salvo
donde se indica; ninguno se usa para publicidad ni para seguimiento.

| Categoría | Tipo | Motivo |
|---|---|---|
| Información personal | Nombre | Funciones de la app |
| Información personal | Dirección de correo | Funciones de la app · Gestión de la cuenta |
| Fotos y vídeos | Fotos | Funciones de la app *(opcional: avatar e informes de salida)* |
| Fotos y vídeos | Vídeos | Funciones de la app *(opcional: informes de salida)* |
| Actividad en la app | Otras acciones generadas por el usuario | Funciones de la app *(reservas, cola, informes)* |
| ID de dispositivo | ID de dispositivo o de otro tipo | Funciones de la app *(token de push)* |

**Lo que hay que dejar SIN marcar**, aunque el formulario invite a ello:

- **Ubicación** — no se pide ni se deduce.
- **Contactos**, **agenda**, **SMS**, **archivos y documentos** — la app no accede.
- **Información financiera** — no hay pagos.
- **Publicidad** o **Analíticas** como motivo — no existe ninguna de las dos.
- **Compartido con terceros** — Supabase, el servidor propio y Firebase son
  *encargados del tratamiento*, no terceros con quienes se comparta. Play
  distingue "recopilar" de "compartir"; marcar "compartir" aquí sería falso.

**Sobre los permisos de Android:** el manifiesto solo declara `INTERNET`;
`POST_NOTIFICATIONS` lo aporta el manifiesto de `firebase_messaging` al
fusionarse. **No hay permiso de cámara ni de galería**: `image_picker` usa el
selector del sistema, que devuelve solo el fichero elegido. Conviene saberlo
porque Play cruza los permisos declarados con lo que dices recopilar.

## Clasificación del contenido (content rating)

Cuestionario corto. Para esta app: sin violencia, sin contenido sexual, sin
lenguaje soez, sin sustancias, sin juegos de azar. **Sí** hay interacción entre
usuarios (tablón de anuncios y notas de reserva) y **sí** se comparte
información personal entre ellos (nombres y fechas), que es lo que hay que
declarar con honestidad. Resultado esperable: apto para todos los públicos.

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
