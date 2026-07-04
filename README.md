# Portal Familia

Gestión de casas familiares (calendario, reservas, inspecciones con fotos/vídeo, anuncios,
sorteos, usuarios). **Una sola base de código Flutter** → **3 apps nativas**:

| Plataforma | Distribución | Auto-update |
|-----------|--------------|-------------|
| **Android** | APK propio alojado en tu Docker (sin Google Play) | ✅ desde la app |
| **Windows** | Instalador `.exe` (Inno Setup) alojado en tu Docker | ✅ desde la app |
| **Apple (iOS)** | **App Store de forma privada (no listado / *unlisted*)** — accesible solo por enlace, NO público y NO por TestFlight | ✅ auto-update de App Store (cada versión nativa pasa revisión, rápida en no listado) |

**Backend:** Supabase Cloud (Postgres + Auth + API + Edge Functions). **Media** (fotos/vídeo):
**MinIO self-hosted** en tu Docker — los archivos viven en tu servidor, no en Supabase.

> Arquitectura completa: [docs/ARQUITECTURA.md](docs/ARQUITECTURA.md).
> Seguridad (explicada para todos): [docs/SEGURIDAD.md](docs/SEGURIDAD.md).

## Novedades

- **Lista de espera (cola) de reservas.** Si unas fechas están ocupadas, te apuntas a la cola; si
  quien la tiene **cancela**, el siguiente (orden FIFO) hereda la reserva **automáticamente** y
  recibe **2 avisos** ("X canceló" y "las fechas son tuyas").
- **Tiempo real (Supabase Realtime).** Calendario, reservas, cola y anuncios se actualizan **solos**
  en todos los dispositivos abiertos, sin recargar.
- **Notificaciones push (FCM).** Avisos de dispositivo además de email. Requiere setup de Firebase
  (ver guía). Push iOS pendiente de la cuenta Apple/APNs.
- **iOS ahora por App Store privado** (no listado), no por TestFlight: no caduca y auto-actualiza.

> Guía de la cola + push + tiempo real:
> [docs/COLA-NOTIFICACIONES-TIEMPO-REAL.md](docs/COLA-NOTIFICACIONES-TIEMPO-REAL.md).

---

## Estructura del repo

```
README.md          ← este archivo
.env.example       ← ÚNICA fuente de configuración (credenciales, rutas, URLs)
compose.yaml       ← Docker: minio + updates  (docker compose up -d)
app_flutter/       ← la app (android/ · ios/ · windows/ · lib/)
supabase/          ← migraciones (0001–0015) + Edge Functions (media-sign · send-email ·
                     admin-users · test-smtp · send-push · notify-waitlist)
server/            ← soporte del servidor:  nginx/ · cloudflared/ · updates/ (plantillas)
scripts/           ← release.ps1 · build-aab.ps1 · build-windows.ps1 · push-supabase-secrets.*
docs/              ← GOOGLE.md · APPLE.md · WINDOWS.md · ANDROID.md · ARQUITECTURA.md ·
                     SEGURIDAD.md · COLA-NOTIFICACIONES-TIEMPO-REAL.md
dist/              ← (generado) artefactos finales: setup.exe (Windows), .aab (Google Play), version.json
```

## Configuración: un único `.env`

Toda la configuración está en **`.env`** (copia de `.env.example`). Es la única fuente de la
verdad. Como Docker, Supabase y las apps son sistemas distintos que no leen el mismo archivo en
ejecución, **3 adaptadores** lo reparten (sin filtrar secretos al cliente):

| Adaptador | Qué hace |
|-----------|----------|
| **Docker** | `docker compose up -d` lee `.env` directamente (MinIO + updates) |
| **Supabase** | `scripts/push-supabase-secrets.*` sube los *secrets* a las Edge Functions |
| **Apps** | `scripts/build-*.ps1` hornean SOLO los valores **públicos** (`SUPABASE_URL/ANON_KEY`, `MEDIA_PUBLIC_URL`, `UPDATES_PUBLIC_URL`) con `--dart-define` |

## Puesta en marcha del servidor (una vez)

1. **Instala Docker** (Docker Desktop en Windows/Mac, o Docker Engine en Linux): https://docs.docker.com/get-docker/
2. `cp .env.example .env` y rellena las líneas marcadas con ⬅️ CAMBIA (rutas de almacenamiento,
   contraseña de MinIO, subdominios).
3. `docker compose up -d` → levanta **MinIO** (media) y **updates** (instaladores).
4. **cloudflared** (en el host) para publicar `media.` y `app.`: ver
   [server/cloudflared/config.example.yml](server/cloudflared/config.example.yml).
5. `./scripts/push-supabase-secrets.ps1` (o `.sh`) → sube los secrets de Supabase.

## Las 3 apps

| Plataforma | Cómo se compila y se actualiza | Guía |
|-----------|-------------------------------|------|
| Android | `flutter build appbundle` (`build-aab.ps1`) → **Google Play** (por invitación) | [docs/GOOGLE.md](docs/GOOGLE.md) |
| Windows | `flutter build windows` (Visual Studio C++) + Inno Setup → `setup.exe`; auto-update | [docs/WINDOWS.md](docs/WINDOWS.md) |
| Apple | `flutter build ipa` en un **Mac** → App Store Connect → **App Store privado (no listado)** | [docs/APPLE.md](docs/APPLE.md) |

## Publicar una actualización (un comando)

```powershell
./scripts/release.ps1 -Bump
```
Sube el número de versión de `app_flutter/pubspec.yaml`, compila **Windows**, deja los artefactos en
`dist/` y —si `UPDATES_DATA_DIR` es accesible— los **publica** en el servidor y regenera la página de
descargas. **No** hace falta reconstruir imágenes ni reiniciar contenedores: el servicio `updates`
sirve la carpeta en vivo y **Windows se actualiza solo** al reabrirse. (Android va por **Google Play**
—`build-aab.ps1`— e iOS por el **App Store**; se publican aparte, ver sus guías.)

> Si el servidor Docker está en otra máquina (Linux), copia el contenido de `dist/` a la carpeta
> `UPDATES_DATA_DIR` de ese servidor (la primera vez incluye `index.html`).

## Herramientas por plataforma (en tu máquina de desarrollo)

- **Android**: Android Studio o el Android SDK (cmdline-tools). Keystore de subida (ver ANDROID.md); el `.aab` se compila con `build-aab.ps1` (ver GOOGLE.md).
- **Windows**: Visual Studio con *Desktop development with C++* + **Inno Setup**.
- **Apple**: un **Mac** con Xcode + **Apple Developer Program** (99 €/año). Distribución en
  **App Store no listado** (privado por enlace), no TestFlight — ver [docs/APPLE.md](docs/APPLE.md).
- **Push (FCM)**: proyecto **Firebase** (`flutterfire configure` + service account). Setup completo
  en [docs/COLA-NOTIFICACIONES-TIEMPO-REAL.md](docs/COLA-NOTIFICACIONES-TIEMPO-REAL.md).
