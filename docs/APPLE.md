# Apple (iOS) — TestFlight privado

A diferencia de Android/Windows, **iOS no puede auto-actualizarse desde tu Docker**: Apple no
permite instalar ni actualizar apps fuera de la App Store/TestFlight. Para una app **privada**
de familia, la vía estable es **TestFlight** (hasta 10.000 testers por invitación, sin listado
público). Requiere **Mac** + **Apple Developer Program (99 €/año)**.

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
6. En **App Store Connect → TestFlight**: añade testers por email (grupo interno o externo) y
   reparte el enlace de invitación. La familia instala la app **TestFlight** y desde ahí Portal Familia.

## Actualizaciones de iOS
- Subes una build nueva a TestFlight → los testers reciben la actualización por TestFlight.
- Los builds de TestFlight **caducan a los 90 días** (vuelve a subir).
- **Opción OTA (opcional):** [Shorebird](https://shorebird.dev) permite *code-push* del código
  Dart cumpliendo las reglas de Apple (no cambia código nativo). Útil para iterar sin re-subir,
  pero no sustituye a TestFlight para cambios nativos.

## Push en iOS
El push (APNs) también requiere la cuenta de 99 €/año. Queda fuera de esta entrega (ver notas de
FCM en el proyecto).
