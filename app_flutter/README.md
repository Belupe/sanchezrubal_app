# app_flutter — Portal Familia (web + móvil)

App Flutter que consume **Supabase** (datos/Auth) y **MinIO** (media). Reemplaza
la antigua UI de Next.js.

## Requisitos

- Flutter SDK (stable). Comprueba con `flutter doctor`.

## Ejecutar en desarrollo

Las claves PÚBLICAS de Supabase vienen como defaults en `lib/config.dart`, así
que arranca sin parámetros:

```bash
cd app_flutter
flutter pub get
flutter run -d chrome      # web
# o un emulador/dispositivo para Android/iOS
```

Para sobrescribir la config (p. ej. otro proyecto o la URL de media):

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxx \
  --dart-define=MEDIA_PUBLIC_URL=https://media.tu-dominio
```

## Compilar

- **Web**: `flutter build web` (o automático dentro de Docker: `infra/web/Dockerfile`).
- **Android**: `flutter build apk` / `appbundle`.
- **iOS**: `flutter build ipa` (requiere macOS/Xcode).

## Implementado

- **Auth**: login, recuperar contraseña, **perfil editable** (nombre/contraseña) + logout.
- **Calendario** de reservas: ver, crear (mantenimiento solo admin principal),
  **editar** (el creador ajusta personas/comentarios; el admin también fechas) y **borrar**.
- **Domicilios**: CRUD (crear/editar/borrar para admin principal).
- **Grupos y usuarios**: crear grupo + propietario, invitar por email, cambiar roles,
  quitar de grupo, eliminar usuario (vía Edge Function `admin-users`).
- **Sorteos**: asignación Fisher-Yates de quincenas a familias + historial.
- **Configuración**: SMTP/general/límite de días, plantillas de correo, notificaciones.
- **Anuncios**: ver, publicar (con domicilios), borrar.
- **Inspecciones**: rellenar (subida de fotos/vídeo a MinIO) + **panel** para revisar lo subido.
- **Límite de días** por reserva impuesto en la BD (trigger).
- Navegación por rol (Drawer); pantallas de admin gateadas por permisos + RLS.

## Pendiente

- **Push (FCM)**: requiere proyecto Firebase + config nativa. El guardado de token ya
  está listo en `lib/services/push_service.dart` (solo falta activar Firebase).
- **Archivado anual a Excel** (cron 31 dic) — opcional.
- **Aviso pre-estancia / recordatorio mensual** por correo — opcional (el ajuste `PRE_STAY`
  ya existe en Configuración).
- **Subida multiparte** de vídeos > 100 MB (límite de Cloudflare free).

## ⚠️ Verificación

Este código **no se ha compilado** en el entorno de desarrollo (sin SDK Flutter). Antes
de usar, ejecuta:

```bash
cd app_flutter
flutter pub get
flutter analyze   # corrige cualquier aviso que aparezca
flutter run -d chrome   # o un dispositivo/emulador
```
