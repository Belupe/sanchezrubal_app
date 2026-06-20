# Distribución multiplataforma — lluvia de ideas

> Una sola base de código Flutter → compila a **web, Android e iOS**. El código YA
> está listo. Lo difícil no es construir, es **distribuir** (sobre todo iOS).

## Aclaración importante sobre Docker

- **Docker NO ejecuta apps móviles** (corren en el teléfono).
- Docker **sí** puede: alojar el **APK de Android** para descargar + un endpoint de
  "hay nueva versión". También compilar el APK (CI Linux).
- Docker **no** puede compilar ni firmar **iOS** (eso necesita macOS + cuenta Apple).

---

## 1) Web — RESUELTO

- **Cloudflare Pages** (build de Flutter web) → conexión directa a **Supabase**.
- Funciona en cualquier navegador, también el del móvil. **Coste: 0.**

## 2) Android — fácil y gratis

Android permite instalar APK directamente (sideload), sin tienda ni cuota.

| Vía | Cómo | Coste |
|-----|------|-------|
| **APK propio** | Alojas el `.apk` en tu Docker (nginx) / Cloudflare Pages / GitHub Releases; la gente lo descarga e instala | **0** |
| **Google Play** | Subes el `.aab`; instalación fácil + auto-updates + confianza | **25 $ pago ÚNICO** (no anual) |

- **Auto-actualización del APK propio**: la app consulta un `version.json` en tu Docker
  y avisa "hay nueva versión" → descarga el APK nuevo. (Te lo puedo montar.)
- **Compilar**: tu PC (`flutter build apk` / `appbundle`) o CI Linux (Docker / GitHub Actions).
- **Push (FCM)**: gratis en Android.

## 3) iOS — aquí está la trampa

**Verdad incómoda:** para poner una app **nativa** en iPhones de otras personas a largo
plazo, Apple exige el **Apple Developer Program (~99 €/año)**. No hay atajo legal estable.

Opciones **sin pagar** (con peros):
- **PWA** — la rechazaste, pero ojo: una PWA moderna **no es un marcador**; tiene
  **offline, pantalla completa, icono propio y push** (iOS 16.4+). Es la **única vía
  gratis "tipo app"** en iPhone.
- **Solo web en Safari** (sin instalar).
- **Sideload con Apple ID gratis**: la app **caduca a los 7 días** y solo en tus
  dispositivos → inviable para una familia.
- **Distribución web / marketplace alternativo (UE, DMA)**: **sigue requiriendo los
  99 €/año** + notarización. No lo evita.

Opción **pagando 99 €/año**:
- **TestFlight** (recomendado para familia): invitas por email, sin listado público,
  hasta 10.000 testers. Lo más sencillo y barato para una app privada.
  - Pegas: el build **caduca a 90 días** (re-subir); compilar iOS necesita un **Mac** o
    un CI con Mac (Codemagic / GitHub Actions macOS / Cirrus).
- **App Store** público (si algún día se abre a más gente).

> Nota: el **push en iOS** (APNs) **también** requiere la cuenta de 99 €/año. Otra razón
> por la que iOS nativo prácticamente obliga a pagar.

---

## Coste real comparado

| Plataforma | Vía | Coste |
|---|---|---|
| Web | Cloudflare Pages | **0** |
| Android | APK sideload (Docker) | **0** |
| Android | Google Play | 25 $ (una vez) |
| iOS | PWA / web | **0** |
| iOS | TestFlight / App Store | **99 €/año** (+ Mac/CI para compilar) |

## Recomendación (para discutir)

1. **Web + Android APK** cubren a casi todos **gratis** y ya. Docker aloja el APK.
2. **iOS**: o asumes los **99 €/año** (TestFlight, indolora para familia) o los de iPhone
   usan **web/PWA**. No existe un "iOS nativo gratis" real y estable.
3. **Híbrido sugerido**: lanza ya **Web + Android** (gratis); deja iOS como **web/PWA**;
   si hay bastantes iPhones, pagas los 99 € y subes a **TestFlight**.

## Extras / ideas

- **Shorebird** (code-push OTA para Flutter): actualizas el código de la app sin re-subir
  a las tiendas. Tiene plan gratis con límites. Útil para iterar rápido.
- **Build CI**: GitHub Actions (Android en Linux gratis; iOS en runner macOS) o **Codemagic**
  (especializado en Flutter, plan gratis, compila iOS en sus Macs).

## Preguntas a decidir cuando volvamos

1. **¿iOS sí o no?** Si sí: ¿asumes 99 €/año (TestFlight) o te vale **PWA/web** para iPhone?
2. **Android**: ¿APK propio (gratis, Docker) o **Google Play** (25 $ una vez)?
3. **¿Tienes un Mac** o usamos un CI con Mac para compilar iOS?
4. ¿Quieres que monte ya el **build + descarga del APK de Android** (con auto-update)?
