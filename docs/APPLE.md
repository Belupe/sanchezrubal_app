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

   > La distribución no listada exige una **primera aprobación** y luego el formulario; no es
   > instantánea el día 1. (TestFlight queda como herramienta opcional de pruebas internas antes de
   > publicar, no como canal de distribución.)

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
