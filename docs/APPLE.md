# Apple (iOS) — App Store privado (no listado / *unlisted*)

A diferencia de Android/Windows, **iOS no puede auto-actualizarse desde tu Docker**: Apple no
permite instalar ni actualizar apps nativas fuera de la App Store. Para una app **privada** de
familia la vía elegida es el **App Store de forma NO LISTADA** (*unlisted*): la app está publicada
pero **no es buscable ni pública**, solo se instala con un **enlace directo** que repartes a la
familia.

**Por qué App Store no listado y no TestFlight:**
- **No caduca:** una app publicada no expira (TestFlight caduca cada 90 días).
- **Auto-actualiza** vía App Store como cualquier app.
- **Privada:** invisible en búsquedas y en tu perfil; solo por enlace.
- Precio del "tiempo real": cada **versión nativa** pasa **revisión de Apple** (suele ser rápida en
  apps no listadas). El contenido (anuncios, reservas, cola…) es **datos en Supabase** y cambia al
  instante sin recompilar; ver [COLA-NOTIFICACIONES-TIEMPO-REAL.md](COLA-NOTIFICACIONES-TIEMPO-REAL.md).

> La carpeta `app_flutter/ios/` ya está generada (bundle id `net.sanchezrubal.portalFamilia`).
> El build y la subida se hacen en el **Mac**; este repo no lo compila en Windows.

## Requisitos
- **Mac** con **Xcode** (App Store).
- **Apple Developer Program** activo (99 €/año): https://developer.apple.com/programs/
- En App Store Connect, crea la app (mismo *bundle id*).

## Pasos (en el Mac)
1. Clona el repo y `cd app_flutter && flutter pub get`.
2. Abre `ios/Runner.xcworkspace` en Xcode → *Signing & Capabilities*: elige tu *Team* y deja
   *Automatically manage signing*. Ajusta *Display Name* = "Portal Familia" y el *Bundle Identifier*.
3. Sube la versión en `pubspec.yaml` (`x.y.z+N`) igual que en las otras apps.
4. Compila el archivo subible:
   ```bash
   flutter build ipa --release \
     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
     --dart-define=MEDIA_PUBLIC_URL=...
   ```
   (los mismos valores **públicos** del `.env`).
5. Sube el `.ipa` a **App Store Connect** con **Xcode → Organizer → Distribute App**, o con
   `xcrun altool` / **Transporter**.
6. **Publicar como no listado:** completa la ficha, envía la app a revisión **como app estándar** y,
   una vez **aprobada**, solicita el enlace de distribución no listada en App Store Connect
   (*la app → "Request unlisted app distribution"*, formulario de Apple). Reparte ese **enlace**
   a la familia; con él instalan Portal Familia desde el App Store.
7. **Pega el enlace en `.env`:** pon esa URL (`https://apps.apple.com/...`) en `DOWNLOAD_IOS_URL`
   del `.env` y ejecuta `./scripts/release.ps1`. La página de descargas (`UPDATES_PUBLIC_URL`)
   mostrará entonces el botón **🍏 iPhone / iPad**. Mientras `DOWNLOAD_IOS_URL` esté vacío, el botón
   no aparece. Si algún día hay que cambiarlo por seguridad, editas `.env` y republicas: no se toca
   código. (Lo mismo aplica a `DOWNLOAD_ANDROID_PLAY_URL` y `DOWNLOAD_WINDOWS_URL`.)

   > La distribución no listada exige una **primera aprobación** y luego el formulario; no es
   > instantánea el día 1. (TestFlight queda como herramienta opcional de pruebas internas antes de
   > publicar, no como canal de distribución.)

## Capturas de pantalla para la ficha

La ficha de App Store Connect no se puede enviar sin capturas, y Apple las exige en **la
resolución exacta** de dos tamaños: **iPhone de 6,9"** e **iPad de 13"** (del resto de modelos se
encarga él reescalando). Ya están hechas, en [capturas/](capturas/):

| Carpeta | Súbela en el tamaño | Resolución |
|---------|--------------------|-----------|
| `capturas/iphone-6.9/` | iPhone 6,9" | 1290 × 2796 |
| `capturas/ipad-13/` | iPad 13" | 2048 × 2732 |

Van numeradas (`01-…`, `02-…`): ese es el orden en que se enseñan, y **la primera es la que sale
en los resultados de búsqueda**.

Para regenerarlas (al cambiar la interfaz, o para enseñar otras pantallas) **no hace falta un Mac
ni el simulador**:

```bash
./scripts/screenshots/run.sh
```

Compila la app de verdad para web, la ejecuta en Chromium emulando el iPhone y el iPad
(resolución, zonas seguras, `TargetPlatform.iOS`) y la recorre pantalla por pantalla. Los datos que
salen son de una familia inventada, servidos por un Supabase simulado: **en las capturas públicas
no aparece ni un nombre ni una reserva reales**. Detalles y opciones en
[../scripts/screenshots/README.md](../scripts/screenshots/README.md).

## Actualizaciones de iOS
- Subes una build nueva a App Store Connect → pasa revisión → los dispositivos **auto-actualizan**
  desde el App Store. No caduca (a diferencia de TestFlight).
- Cambios de **contenido/config/reglas** (no nativos) son **datos en Supabase** → en vivo, sin
  recompilar ni revisión.

## Push en iOS
El push (APNs) requiere la cuenta de 99 €/año **y** subir una **APNs Authentication Key** a Firebase
(Cloud Messaging). El código de push ya está listo en la app (FCM); el push iOS quedará operativo
cuando exista la cuenta Apple/APNs. Setup en
[COLA-NOTIFICACIONES-TIEMPO-REAL.md](COLA-NOTIFICACIONES-TIEMPO-REAL.md).
