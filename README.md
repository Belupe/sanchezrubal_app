# Portal Familia

Gestión de casas familiares (calendario, reservas, inspecciones con fotos/vídeo, anuncios,
sorteos, usuarios). **Una sola base de código Flutter** → **4 apps nativas**:

| Plataforma | Distribución | Auto-update |
|-----------|--------------|-------------|
| **Android** | APK propio alojado en tu Docker (sin Google Play) | ✅ desde la app |
| **Windows** | Instalador `.exe` (Inno Setup) alojado en tu Docker | ✅ desde la app |
| **Linux** | `AppImage` (**cualquier** distro: Ubuntu, Kali, Arch, Fedora…) + `.deb` (Ubuntu/Debian/Kali) + `.tar.gz`, alojados en tu Docker | ✅ desde la app (el AppImage, sin contraseña) |
| **Apple (iOS)** | **App Store de forma privada (no listado / *unlisted*)** — accesible solo por enlace, NO público y NO por TestFlight | ✅ auto-update de App Store (cada versión nativa pasa revisión, rápida en no listado) |

**Backend:** Supabase Cloud (Postgres + Auth + API + Edge Functions). **Media** (fotos/vídeo):
**MinIO self-hosted** en tu Docker — los archivos viven en tu servidor, no en Supabase.

> Arquitectura completa: [docs/ARQUITECTURA.md](docs/ARQUITECTURA.md).
> Seguridad (explicada para todos): [docs/SEGURIDAD.md](docs/SEGURIDAD.md).
> **Despliegue paso a paso** (de dónde sale cada valor del `.env` + comandos): [docs/DESPLIEGUE.md](docs/DESPLIEGUE.md).
> Servidor con **Dockge** en Ubuntu (colocación del stack, rutas y permisos): [docs/DOCKGE.md](docs/DOCKGE.md).

## Novedades

- **Compatible con Linux.** Cualquier distro: **AppImage** (un solo fichero, se actualiza solo y
  sin contraseña), **`.deb`** para Ubuntu/Debian/Kali y **`.tar.gz`** con instalador de dos modos.
  Se compila desde Windows dentro de Docker. Guía: [docs/LINUX.md](docs/LINUX.md).
- **Registro de fallos en las 5 plataformas.** Si la app se cierra sola o falla, deja un informe
  técnico (sin credenciales) que el usuario puede enviarte desde Configuración → *Diagnóstico*.
  Guía: [docs/REGISTROS.md](docs/REGISTROS.md).
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
app_flutter/       ← la app (android/ · ios/ · linux/ · macos/ · windows/ · lib/ · test/)
supabase/          ← migraciones (0001–0021) + Edge Functions (media-sign · send-email ·
                     admin-users · test-smtp · send-push · notify-waitlist)
server/            ← soporte del servidor:  nginx/ · cloudflared/ · updates/ (plantillas)
scripts/           ← release.ps1 · build-aab.ps1 · build-windows.ps1 · build-linux.ps1|.sh ·
                     linux-build.Dockerfile · linux/instalar.sh · push-supabase-secrets.*
docs/              ← DESPLIEGUE.md · GOOGLE.md · APPLE.md · WINDOWS.md · LINUX.md · ANDROID.md ·
                     ARQUITECTURA.md · SEGURIDAD.md · REGISTROS.md ·
                     COLA-NOTIFICACIONES-TIEMPO-REAL.md
dist/              ← (generado) artefactos finales: setup.exe (Windows), .AppImage/.deb/.tar.gz
                     (Linux), .aab (Google Play), version.json
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

## Las 4 apps

| Plataforma | Cómo se compila y se actualiza | Guía |
|-----------|-------------------------------|------|
| Android | `flutter build appbundle` (`build-aab.ps1`) → **Google Play** (por invitación) | [docs/GOOGLE.md](docs/GOOGLE.md) |
| Windows | `flutter build windows` (Visual Studio C++) + Inno Setup → `setup.exe`; auto-update | [docs/WINDOWS.md](docs/WINDOWS.md) |
| Linux | `flutter build linux` **dentro de Docker** (`build-linux.ps1`) → `AppImage` + `.deb` + `.tar.gz`; auto-update | [docs/LINUX.md](docs/LINUX.md) |
| Apple | `flutter build ipa` en un **Mac** → App Store Connect → **App Store privado (no listado)** | [docs/APPLE.md](docs/APPLE.md) |

## Publicar una actualización (un comando)

```powershell
./scripts/release.ps1 -Bump
```
Sube el número de versión de `app_flutter/pubspec.yaml`, compila **Windows y Linux**, deja los
artefactos en `dist/` y —si `UPDATES_DATA_DIR` es accesible— los **publica** en el servidor y
regenera la página de descargas. **No** hace falta reconstruir imágenes ni reiniciar contenedores: el
servicio `updates` sirve la carpeta en vivo y **Windows y Linux se actualizan solos** al reabrirse.
(Android va por **Google Play** —`build-aab.ps1`— e iOS por el **App Store**; se publican aparte, ver
sus guías.)

> Linux se compila dentro de **Docker** porque Flutter no puede compilar Linux desde Windows. Si no
> tienes Docker arrancado, `release.ps1` avisa y sigue con lo demás; puedes hacerlo luego con
> `./scripts/build-linux.ps1`, o saltártelo con `-SkipLinux`.

> Si el servidor Docker está en otra máquina (Linux), copia el contenido de `dist/` a la carpeta
> `UPDATES_DATA_DIR` de ese servidor (la primera vez incluye `index.html`).

## Herramientas por plataforma (en tu máquina de desarrollo)

- **Android**: Android Studio o el Android SDK (cmdline-tools). Keystore de subida (ver ANDROID.md); el `.aab` se compila con `build-aab.ps1` (ver GOOGLE.md).
- **Windows**: Visual Studio con *Desktop development with C++* + **Inno Setup**.
- **Linux**: **solo Docker** (el mismo que ya usas para el servidor). No hace falta un ordenador con
  Linux: `build-linux.ps1` compila dentro de un contenedor Ubuntu 22.04 — y esa versión antigua es
  a propósito, es lo que hace que el binario arranque también en distros más viejas
  (ver [docs/LINUX.md](docs/LINUX.md)).
- **Apple**: un **Mac** con Xcode + **Apple Developer Program** (99 €/año). Distribución en
  **App Store no listado** (privado por enlace), no TestFlight — ver [docs/APPLE.md](docs/APPLE.md).
- **Push (FCM)**: proyecto **Firebase** (`flutterfire configure` + service account). Setup completo
  en [docs/COLA-NOTIFICACIONES-TIEMPO-REAL.md](docs/COLA-NOTIFICACIONES-TIEMPO-REAL.md).
