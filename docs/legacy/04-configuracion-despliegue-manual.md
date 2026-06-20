# Documentación de Configuración y Despliegue — Portal Familia (legacy-next)

> Aplicación Next.js legacy (App Router) destinada a sustituir hojas de Excel en la administración, hospedaje e inspección de domicilios vacacionales de grupos familiares.
> Nombre interno del paquete: `homes-controller` (v0.1.0). Título de la app: **Portal Familia - Digital Concierge**.
> Stack: Next.js 16.2.1, React 19.2.4, Prisma + SQLite, JWT (`jose`), Tailwind CSS 4, Docker (Node 20 Alpine).

---

## 1. Variables de entorno (`.env.example`)

El archivo `.env` está en `.gitignore` y **NUNCA** debe subirse. El `.env.example` sí se versiona.

### Quick start (servidor limpio con Docker)
1. `cp .env.example .env`
2. Generar los DOS secretos obligatorios:
   - `openssl rand -hex 32` → `JWT_SECRET`
   - `openssl rand -base64 32` → `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY`
3. Editar `DOCKER_IMAGE`.
4. `docker compose pull && docker compose up -d`

### Tabla completa de variables

| Variable | Propósito | Default | ¿Obligatoria? | Notas |
|---|---|---|---|---|
| `DOCKER_IMAGE` | Imagen que `docker compose pull` descargará. | `belupe/portal-familia:dev` | No | Recomendado fijar versión en producción. main → `:latest`; IAdev → `:dev`. |
| `NODE_ENV` | Modo de ejecución. Controla protecciones (cookie `Secure`, Turnstile fail-closed). | `production` | No | `development` para pruebas sin HTTPS ni captcha. |
| `DOMAIN_NAME` | Dominio público. Necesario en producción para aceptar Server Actions desde ese origen. | *(vacío)* | No (sí con dominio) | Se inyecta en `allowedOrigins`. |
| `HOST_IP` | IP local de acceso en red doméstica. | `0.0.0.0` | No | Se añade a `allowedOrigins`/`allowedDevOrigins`. |
| `HOST_PORT` | Puerto de publicación. | `3000` | No | Mapea `HOST_PORT:3000`. |
| `HOST_DB_DIR` | Ruta host de la base SQLite. Se monta en `/app/db`. | `./db` | No | Para `npm run dev` se ignora. |
| `HOST_UPLOADS_DIR` | Ruta host de imágenes de reportes. Se monta en `/app/uploads`. | `./uploads_data` | No | — |
| `HOST_LOGS_DIR` | Carpeta host de logs. Se monta en `/app/logs`. | `./logs_data` | No | Logs sobreviven a reinicios. |
| `HOST_CLOUDFLARE_DIR` | **Reservado** para futura integración con certs de Cloudflare. | `./Cloudflare` | No | **NO cableado** en docker-compose. |
| `DB_FILE_NAME` | Nombre del archivo SQLite dentro de `HOST_DB_DIR`. | `familia.db` | No | En Docker, `DATABASE_URL = file:/app/db/${DB_FILE_NAME}`. |
| `DATABASE_URL` | URL de conexión Prisma. | *(comentada)* `"file:./dev.db"` | Depende | Con Docker: NO ponerla. Sin Docker: descomentar. |
| `JWT_SECRET` | Secreto para firmar sesiones JWT. | *(vacío)* | **SÍ — OBLIGATORIA** | `openssl rand -hex 32`. Si se cambia, **todas las sesiones se invalidan**. Mantener igual entre despliegues. |
| `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY` | Clave estable para cifrar IDs de Server Actions. | *(vacío)* | **SÍ — OBLIGATORIA** | `openssl rand -base64 32`. Si no se define, cada build genera una nueva y las pestañas viejas fallan ("Failed to find Server Action"). |
| `TURNSTILE_SITE_KEY` | Site Key pública de Cloudflare Turnstile. | *(vacío)* | Condicional | Cloudflare → Turnstile → Add site. |
| `NEXT_PUBLIC_TURNSTILE_SITE_KEY` | Igual que la anterior; usada como **build arg** para hornearla en el bundle. | *(vacío)* | Condicional (obligatoria con Docker si se usa Turnstile) | Debe coincidir con `TURNSTILE_SITE_KEY`. |
| `TURNSTILE_SECRET_KEY` | Secret Key privada; valida el captcha en el servidor. | *(vacío)* | Condicional | Nunca exponer al cliente. |
| `UPLOAD_DIR` | Directorio de imágenes de reportes. | en Docker `/app/uploads`; sin Docker `./uploads` | No | — |
| `LOG_DIR` | Directorio de archivos de log. | en Docker `/app/logs`; sin Docker `./logs` | No | Crea `app-YYYY-MM-DD.log`; registra `console.error/warn`, `uncaughtException`, `unhandledRejection`, `SIGTERM/SIGINT`, exit. |

**Turnstile con claves vacías:** `development` → omite verificación; `production` → **rechaza** login/registro (fail-closed).

**Seguridad:** los dos secretos son obligatorios, se generan una vez y se conservan idénticos entre despliegues. Cambiar `JWT_SECRET` invalida todas las sesiones.

---

## 2. `next.config.ts`

- **`output: 'standalone'`**: bundle autocontenido para Docker (con `server.js`).
- **`logging.fetches.fullUrl: false`**: no imprime la URL completa de los `fetch` en logs.
- **`allowedDevOrigins`**: `0.0.0.0`, `localhost` y `HOST_IP` si está.
- **`experimental.serverActions.allowedOrigins`**: `0.0.0.0:${HOST_PORT}`, `localhost:${HOST_PORT}`, y `HOST_IP`/`DOMAIN_NAME` (con y sin puerto) si están definidos.
- **Cabeceras de seguridad** (a todas las rutas `/(.*)`):
  | Cabecera | Valor | Efecto |
  |---|---|---|
  | `X-Frame-Options` | `DENY` | Anti clickjacking. |
  | `X-Content-Type-Options` | `nosniff` | Evita MIME-sniffing. |
  | `Referrer-Policy` | `strict-origin-when-cross-origin` | Limita el referrer cross-origin. |

---

## 3. `package.json` — scripts y dependencias

### Scripts de npm

| Script | Comando | Qué hace |
|---|---|---|
| `dev` | node + dotenv → `next dev -H 0.0.0.0 -p $HOST_PORT` | Carga `.env`, arranca dev escuchando en `0.0.0.0`. |
| `build` | `next build` | Compila producción (bundle standalone). |
| `start` | `next start` | Arranca el servidor de producción. |
| `lint` | `eslint` | Linter. |
| `db:update` | `npx kill-port 3000 && npx prisma db push && npx prisma generate` | Libera puerto, aplica esquema a SQLite y regenera el cliente Prisma. |

### Dependencias clave

| Paquete | Versión | Rol |
|---|---|---|
| `next` | 16.2.1 | Framework (App Router, Server Actions, standalone). |
| `react`/`react-dom` | 19.2.4 | UI. |
| `@prisma/client` | ^6.19.2 | Cliente ORM (SQLite). |
| `prisma` (dev) | ^6.12.0 | CLI/ORM. |
| `jose` | ^6.2.2 | JWT (sesiones, middleware). |
| `bcryptjs` | ^3.0.3 | Hash de contraseñas. |
| `zod` | ^3.23.8 | Validación/sanitización. |
| `nodemailer` | ^8.0.4 | Envío SMTP. |
| `node-cron` | ^4.2.1 | Cron diario 08:30. |
| `xlsx` | ^0.18.5 | Exportar historial a Excel. |
| `@fullcalendar/*` | ^6.1.20 | Calendario interactivo. |
| `date-fns` | ^4.1.0 | Fechas. |
| `zustand` | ^5.0.12 | Estado global. |
| `lucide-react` | ^1.7.0 | Iconos. |
| `clsx` + `tailwind-merge` | — | Composición de clases. |
| `uuid` | ^13.0.0 | IDs (links, tokens). |
| `dotenv` | ^17.3.1 | Carga `.env` en `dev`. |

devDeps: `tailwindcss` 4, `typescript` 5, `eslint` 9 + `eslint-config-next`, `kill-port`, tipados `@types/*`.

---

## 4. Despliegue Docker

### 4.1 `Dockerfile` (multi-stage, base `node:20-alpine`)

- **base:** instala `libc6-compat` (Prisma).
- **deps:** copia `package*.json`, `npm ci`.
- **builder:** copia node_modules + código. ENV de build: `NEXT_TELEMETRY_DISABLED=1`, `DATABASE_URL="file:/app/db/dev.db"`, `JWT_SECRET="build-time-secret"`. Build arg `NEXT_PUBLIC_TURNSTILE_SITE_KEY` → ENV. `npx prisma generate` + `npm run build`.
- **runner:** `NODE_ENV=production`. Crea usuario no root `nextjs:nodejs` (1001). Crea y da permisos a `/app/prisma /app/uploads /app/db /app/logs`. Copia `public`, `.next/standalone`, `.next/static`, `prisma`, `package.json`. Instala `prisma@6.12.0` global y le da `chown` (la CLI escribe en su dir de caché).

**Entrypoint** (`/app/entrypoint.sh`):
```sh
#!/bin/sh
set -e
prisma db push --schema=/app/prisma/schema.prisma --skip-generate
exec node server.js
```
- `--skip-generate`: el cliente ya viene del build. `set -e`: aborta si el push falla (visible en `docker logs`).

Config final: `USER nextjs`, `EXPOSE 3000`, ENV `PORT=3000`, `HOSTNAME=0.0.0.0`, `UPLOAD_DIR=/app/uploads`, `LOG_DIR=/app/logs`, `CMD ["/app/entrypoint.sh"]`.

### 4.2 `docker-compose.yml`

Servicio único `portal-familia` (contenedor `portal_familia_app`):
- **image:** `${DOCKER_IMAGE:-belupe/portal-familia:latest}`.
- **env_file:** `.env`. **restart:** `unless-stopped`. **ports:** `${HOST_PORT:-3000}:3000`.
- **environment:** `NODE_ENV`, `DATABASE_URL=file:/app/db/${DB_FILE_NAME:-dev.db}`, `UPLOAD_DIR`, `LOG_DIR`, `JWT_SECRET`, `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY`.
- **volumes:** `${HOST_DB_DIR:-./db}:/app/db`, `${HOST_UPLOADS_DIR:-./uploads_data}:/app/uploads`, `${HOST_LOGS_DIR:-./logs_data}:/app/logs`.
- **healthcheck:** `wget -q --spider http://localhost:3000/login || exit 1` (interval 30s, timeout 5s, retries 5, start_period 30s).
- **logging:** `json-file`, `max-size 10m`, `max-file 3`.

Actualización: `docker compose pull && docker compose up -d`.

---

## 5. Sistema de logs — `src/lib/logger.ts`

- **Directorio:** `LOG_DIR` o `./logs`. Crea recursivo y verifica `W_OK`; si no puede, avisa en stderr y deja de escribir a archivo (sin romper la app).
- **Formato:** un archivo **por día** `app-YYYY-MM-DD.log`. Cada línea `[<ISO>] [<LEVEL>] <mensaje>`. Niveles: INFO, WARN, ERROR, DEBUG, FATAL. **No** hay rotación por tamaño ni purga; solo rota por día.
- **Redacción de secretos:** `safeStringify` reemplaza por `[REDACTED]` claves (case-insensitive): `password, pass, passwordhash, secret, token, resettoken, authorization, cookie, session, jwt_secret, turnstile_secret_key, next_server_actions_encryption_key`. Maneja referencias circulares (`[Circular]`).
- **Captura (`initLogger`, una vez):** sobrescribe `console.error`→ERROR y `console.warn`→WARN (delegando al original); `uncaughtException`/`unhandledRejection`→FATAL; `SIGTERM`/`SIGINT`/`exit`→INFO.
- **API:** `initLogger()`, `logger.info/warn/error/debug`.

---

## 6. `src/app/layout.tsx` (layout raíz)

- Metadata: `title: 'Portal Familia - Digital Concierge'`, `description: 'Gestor de domicilios y calendarios familiares'`.
- Fuentes Google: **Inter** (`--font-inter`), **Manrope** (`--font-manrope`); + Material Symbols Outlined.
- `<html lang="es" className="dark">` → **modo oscuro** por defecto.
- Lee cookie `session`, `decrypt`, y si hay `userId` consulta `uiPreferences` (JSON); si trae `fontSize`, aplica esa clase de tamaño de fuente al `<body>` (default `text-base`).

---

## 7. MANUAL DEL USUARIO — contenido íntegro de `LEEME.html`

> **Portal Familia - Calendario de Domicilios** — *Plataforma para sustituir hojas de Excel en la administración, hospedaje e inspección de domicilios vacacionales.*

### PARTE 1: Guía para Usuarios y Administradores

#### ¿Cómo funciona el proyecto?
- **Calendario Autogestionado Dinámico:** drag-and-drop de días; colores HSL por familia; Modo Oscuro Premium.
- **Alta Individual vs. Grupos Familiares:** se crean admins "sueltos" o Grupos enteros en una acción. Si una persona suelta luego forma familia, el portal la enlaza detectando su **mismo correo**.
- **Control Anti-Abusos (Límites de Reserva):** Mega Admins configuran **Días Máximos de Estadía**. Por defecto, máximo **15 días consecutivos**.
- **Sorteos Matemáticos Justos:** asignación de turnos/quincenas con algoritmo **Fisher-Yates**.
- **Automatización (CRON):** avisos por correo y limpieza anual.

#### Jerarquía de Permisos

| Roles | Crear/Borrar Domicilios | Ascender Súper Admins | Alterar Límites y SMTP | Añadir Grupos/Familias | Hacer Reservas |
|---|:--:|:--:|:--:|:--:|:--:|
| 👑 **Mega Admin (Root)** | ✅ | ✅ | ✅ | ✅ | ✅ |
| 🛡️ **Súper Admin** | ✅ | ✅ | ❌ | ✅ | ✅ |
| 👨‍👩‍👧‍👦 **Admin Familiar** | ❌ | ❌ | ❌ | Parcial (a su familia) | ✅ |
| 👤 **Miembro** | ❌ | ❌ | ❌ | ❌ | ✅ |

#### Despliegue Docker
1. Instalar Docker.
2. Personalizar `.env` (ej. `DB_FILE_NAME=familia.db`).
3. `docker-compose up -d --build`
4. App en `http://localhost:3000`.

> ⚠ **PRIMER INGRESO:** al abrir por primera vez con base recién creada, el sistema muestra un formulario ineludible para crear la cuenta **Mega Administrador**. Esa cuenta **jamás se autoelimina ni se bloquea**.

#### Ejecución local (sin Docker)
- `npm install`, `npm run db:update`, `npm run dev`. Producción: `npm run build` + `npm run start`.
- **Acceso desde la red (Allow IPs):** Server Actions de Next requieren permitir orígenes en `next.config.ts` (`allowedDevOrigins`, `serverActions.allowedOrigins`). Solución universal: añadir `"0.0.0.0"` y `"0.0.0.0:3000"`. Arrancar con `npm run dev -- -H 0.0.0.0`.

#### Notificaciones Automatizadas (CRON, **todos los días 08:30 AM**)

| Alerta | Cuándo | Qué hace / quién recibe | Personalizable |
|---|---|---|:--:|
| **1. Pre-Estancia** `PRE_STAY` | Diario 08:30. Reservas que empiezan **en 2 días** (pasado mañana). | Correo de bienvenida con instrucciones al responsable y su familia. | **Sí** (texto de normas desde *Config > Notificaciones*). |
| **2. Post-Estancia** `POST_STAY` | Diario 08:30. Reservas que **concluyeron ayer**. | Correo al admin/viajante con link al Formulario de Check-out (inventarios/daños). | **Totalmente** (asunto y cuerpo con tags). |
| **3. Recordatorio Mensual** `MONTHLY_REMINDER` | **Día 1 de cada mes** 08:30. | Mail a miembros con reservas en el mes. | **Sí** (desactivable/redactable). |
| **4. Purga y Archivo Anual** | **31 de diciembre** 08:30. | Exporta el historial a Excel y **elimina solo las citas del año que termina** (las futuras quedan a salvo). Envía el Excel a Súper y Mega admins. | **No** (lógica hardcoded). |

#### Configuraciones Pos-Arranque
1. Login como Mega Admin.
2. *Configuración → Límites* (default 15 días).
3. *SMTP*: servidor y contraseña de App (ej. Gmail) → **Probar Servidor**.

#### Retención y Propiedad Digital
Los reportes y datos **no pasan por nubes externas**; se guardan en disco propio (`./sqlite_data` y `./uploads_data`). Backups perpetuos mientras Docker viva.

### PARTE 2: Guía para Desarrolladores
- **Core:** Next.js App Router compilado, `output: standalone` (Docker Alpine).
- **Seguridad:** carga de archivos saneada con `zod`; mitigación LFI con `path` nativo; middleware JWT (`jose`) que **falla catastróficamente** si falta el secreto.
- **Prisma/SQLite:** `DATABASE_URL` se instrumenta con vars de Docker Compose para leer `${DB_FILE_NAME}`.
- **Vínculo Fantasma de Usuarios:** si un email ya existe y se intenta "Añadir Nuevo Grupo" con ese email, la BD no duplica: sobrescribe su FK asociándolo como `FAMILY_ADMIN` del nuevo grupo, sin eliminar su rol ni dañar reservas históricas.
- **Modificar esquema:** editar `schema.prisma` → `prisma generate` → `db push`/`prisma migrate dev`.

---

## 8. README.md (complementa el manual)

Título: **Portal Familia - Calendario de Domicilios**.
- Roles reales e independientes (Mega/Super/Familiar/Miembro).
- Centro de Límites (default 15 días).
- Asignación Flotante Inteligente (enlace por email coincidente).
- Sorteos Fisher-Yates registrados en BD.
- Modo Oscuro Premium, colores HSL, drag-and-drop.
- CRON: correos 1 día antes + vaciado anual a `.xlsx`.
- Seguridad: Zod, bcryptjs, Rate Limit, JWT; fallos de env críticos bloquean el arranque.
- Inicio: `docker-compose up -d --build` → `http://localhost:3000` → crear Mega Admin.
- Backups: `./sqlite_data` (`familia.db`) y `./uploads_data`.

---

## 9. Discrepancias detectadas

- **Rutas de backup inconsistentes:** el manual menciona `./sqlite_data`, pero `.env.example`/compose usan `HOST_DB_DIR=./db`. Las reales operativas son `./db`, `./uploads_data`, `./logs_data`.
- **Dos métodos de despliegue:** manual usa `docker-compose up -d --build` (build local); `.env`/compose usan imagen publicada (`pull` + `up -d`).
- **`HOST_CLOUDFLARE_DIR`** declarada pero **no cableada**.
- **Logger sin rotación por tamaño:** solo por día; no purga antiguos.
