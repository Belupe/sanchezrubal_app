# Arquitectura — Portal Familia (Flutter + Supabase)

## Visión general

```
┌──────────────────────────────┐         ┌──────────────────────────────┐
│  Flutter — 4 apps nativas     │  HTTPS  │       Supabase Cloud          │
│  Android · Windows · Linux    │ ──────► │  Postgres + Auth + API (RLS)  │
│  · iOS  (misma base de código)│         │  Edge Functions (media-sign,  │
│                               │         │   correos) + pg_cron          │
└───────────┬──────────────────┘         └──────────────────────────────┘
            │  URL prefirmada (la firma una Edge Function)
            ▼
┌───────────────────────────────────────────────────────────┐
│  Tu servidor (Docker) tras cloudflared                     │
│  - minio    → fotos/vídeo (MEDIA_DATA_DIR)                 │
│  - updates  → instaladores Android/Windows + version.json  │
│               (UPDATES_DATA_DIR) para auto-actualización   │
└───────────────────────────────────────────────────────────┘
```

- **Datos relacionales** (usuarios, reservas, etc.) → Supabase Cloud (plan free; son pocos KB).
- **Media pesada** (fotos/vídeo) → **MinIO en tu Docker**, en `MEDIA_DATA_DIR`. En la BD solo se
  guarda la **referencia** (`out_reports.media_urls`). Subidas/descargas con **URLs prefirmadas**
  que emite la Edge Function `media-sign` (verifica permisos con RLS).
- **Distribución y updates** de las apps → servicio **`updates`** (nginx) en tu Docker: sirve el
  APK (Android) y el `setup.exe` (Windows) con su `version.json`; las apps se auto-actualizan.
  iOS no usa esto (Apple lo prohíbe): va por **TestFlight**.
- **Red**: el túnel cloudflared publica **`media.`** (MinIO) y **`app.`** (updates). No hay web.

## Roles y permisos

`MEGA_ADMIN` ⊃ `PRINCIPAL_ADMIN` ⊃ `FAMILY_ADMIN`/`FAMILY_SECOND_ADMIN` ⊃ `MEMBER`.
Rol y pertenencia a grupo son **ejes independientes**. Todo se aplica con **RLS** en Postgres
(37 políticas) + triggers (bloqueo de fechas, auditoría). Ver `supabase/migrations/`.

## Notificaciones

| Tipo | Canal | Cómo |
|------|-------|------|
| Alta de usuario / contraseña olvidada | Email | Supabase Auth (invite / reset) |
| Recordatorio de inspección | Email | Edge Function + pg_cron |
| Aviso de mantenimiento / confirmación de reserva | Email | Edge Function (trigger) |
| Resto | Push (FCM) | desde la app *(pendiente de wiring)* |

## ✅ Checklist de configuración manual

1. **Supabase → Auth → URL Configuration**: *Site URL* y *Redirect URLs* = tu dominio.
2. **Supabase → Auth → Email**: desactiva el alta libre (solo invitación). Ajusta plantillas.
3. **Crea el MEGA_ADMIN** a mano: Auth → Users → Add user (Auto-confirm) con metadata
   `{"name":"...","role":"MEGA_ADMIN"}`.
4. **Servidor Docker**: `cp .env.example .env`, rellénalo y `docker compose up -d` (minio + updates).
5. **Secrets de Supabase**: `./scripts/push-supabase-secrets.ps1` (sube `MINIO_*` y `CRON_SECRET`).
6. **cloudflared** (host): ingress de [server/cloudflared/config.example.yml](../server/cloudflared/config.example.yml) + DNS del túnel (`media.`, `app.`).
7. **SMTP** (correos): rellena `system_config` desde la app (MEGA_ADMIN).
8. **Apps**: compila y publica con `./scripts/release.ps1 -Bump` (ver guías por plataforma).

## Estado de implementación

- [x] Esquema + RLS + reglas de negocio (migraciones 0001–0004) y seed (0005)
- [x] Docker: MinIO (media) + updates (instaladores) + cloudflared
- [x] Edge Functions `media-sign` y `send-email` + pg_cron
- [x] App Flutter base: login, recuperar contraseña, calendario, reservas, inspección con media
- [x] Android (APK firmado + auto-update) · Windows (instalador + auto-update) · iOS (scaffolding)
- [x] Linux (AppImage + .deb + .tar.gz, con auto-update) — ver [LINUX.md](LINUX.md)
- [~] Apple: build + TestFlight pendiente de Mac (ver [APPLE.md](APPLE.md))
- [~] Cutover de datos — guía en [CUTOVER.md](CUTOVER.md)
