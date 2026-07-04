# Guía de despliegue — Portal Familia

Esta guía te lleva **paso a paso** para poner el proyecto en marcha: de dónde sale
**cada valor** que va en el `.env`, y los **comandos exactos** para aplicarlo todo en
Supabase. Está pensada para que cualquiera de la familia pueda seguirla.

> **Idea clave:** TODO lo configurable vive en un único archivo, el **`.env`**. Lo rellenas
> una vez y unos scripts reparten cada cosa a su sitio. La plantilla con todas las variables y
> sus explicaciones está en [.env.example](../.env.example) — esta guía te dice **dónde
> conseguir** cada valor.

Índice:
- [0) Antes de empezar (requisitos)](#0-antes-de-empezar-requisitos)
- [1) Rellenar el `.env` — de dónde sale cada valor](#1-rellenar-el-env--de-dónde-sale-cada-valor)
- [2) Aplicarlo todo en Supabase — comandos](#2-aplicarlo-todo-en-supabase--comandos)
- [3) Comprobar que salió bien](#3-comprobar-que-salió-bien)

---

## 0) Antes de empezar (requisitos)

1. **Copia la plantilla:** en la raíz del proyecto, `cp .env.example .env`. El `.env` **nunca**
   se sube al repositorio (está en `.gitignore`). Todo lo que rellenes va en ese `.env`.
2. **CLI de Supabase** (para migraciones, secretos y funciones). Instálala:
   - macOS: `brew install supabase/tap/supabase`
   - Windows (scoop): `scoop install supabase`
   - Otras: https://supabase.com/docs/guides/cli/getting-started
3. **Docker** (solo en el servidor donde corren MinIO + actualizaciones). No hace falta en tu PC.
4. **Dos "sitios" distintos** donde ejecutarás cosas:
   - **Tu PC / la máquina de despliegue:** la CLI de Supabase (migraciones, secretos, funciones).
   - **El servidor:** Docker (`docker compose up -d`) y la creación de la clave de MinIO.

---

## 1) Rellenar el `.env` — de dónde sale cada valor

Abre el `.env` y ve rellenando. Cada apartado corresponde a una sección de
[.env.example](../.env.example).

### 1.1 Supabase  (Dashboard → tu proyecto → *Project Settings* ⚙️)

Abre https://supabase.com/dashboard, entra en el proyecto **SanchezRubal**.

| Variable | Dónde se saca |
|---|---|
| `SUPABASE_URL` | *Project Settings → API Keys* (o *Data API*). Es la **Project URL**. Ya viene puesta en la plantilla. |
| `SUPABASE_ANON_KEY` | *Project Settings → API Keys* → la clave **anon / publishable** (empieza por `sb_publishable_…`). **Es pública a propósito** (la protege el RLS); puede ir horneada en la app. |
| `SUPABASE_PROJECT_REF` | *Project Settings → General* → *Reference ID*. Es también el subdominio de la URL (`pjceyplciujtrnxptwbx`). |
| `SUPABASE_ACCESS_TOKEN` | 🔑 **Secreto.** En https://supabase.com/dashboard/account/tokens → *Generate new token*. Cópialo al momento (no se vuelve a mostrar). Permite a la CLI trabajar sin `supabase login`. |
| `SUPABASE_SERVICE_ROLE_KEY` | 🔑 **Secreto máximo** (salta el RLS). *Project Settings → API Keys* → clave **service_role** (o, si tu panel usa el formato nuevo, una **Secret key** `sb_secret_…`) → *Reveal* y copiar. Solo la necesitas para scripts externos; Supabase la inyecta sola en las funciones. |
| `SUPABASE_DB_PASSWORD` | 🔑 **Secreto.** *Project Settings → Database*. Si no la recuerdas, *Reset database password*. Solo hace falta para `supabase db push/pull`. |

### 1.2 Media / MinIO  (tu servidor)

Las fotos y vídeos los guarda **MinIO** (un almacén tipo S3) en tu servidor.

| Variable | Dónde se saca |
|---|---|
| `MINIO_ROOT_USER` | Lo **eliges tú**. NO uses nombres obvios (`admin`, `minio`, `portalfamilia`…). Genera uno: `openssl rand -hex 8`. |
| `MINIO_ROOT_PASSWORD` | 🔑 Lo eliges tú, fuerte: `openssl rand -base64 24`. |
| `MEDIA_PUBLIC_URL` | El subdominio público del API S3 (el de tu túnel de Cloudflare), p. ej. `https://media.sanchezrubal.net`. |
| `MINIO_CONSOLE_URL` | Subdominio de la consola web de MinIO (opcional). |
| `MEDIA_SIGN_ACCESS_KEY` / `MEDIA_SIGN_SECRET_KEY` | 🔑 Clave **de mínimo privilegio** (solo Get/Put del bucket, NO la root) que usa la función `media-sign`. Se crea una vez con la herramienta `mc`: **sigue el [apéndice A-02 de docs/SEGURIDAD.md](SEGURIDAD.md#apéndice-operativo--crear-la-llave-limitada-de-minio-a-02)**, que trae los comandos exactos. |
| `MEDIA_DATA_DIR` | Carpeta del servidor donde se guardan TODAS las fotos/vídeos (debe existir). |
| `MEDIA_BUCKET`, `MINIO_REGION`, `MINIO_PORT`, `MINIO_CONSOLE_PORT`, `MEDIA_MAX_UPLOAD_BYTES` | Valores por defecto razonables (ver plantilla); normalmente no se tocan. |
| `MINIO_CORS_ORIGIN` | Déjalo en `*` salvo que tengas un cliente web propio (ver nota I-08 en la plantilla). |

### 1.3 Secretos que generas tú  (`openssl rand -base64 24`)

| Variable | Dónde se saca |
|---|---|
| `CRON_SECRET` | 🔑 Token con el que el backend se llama a sí mismo (cron de recordatorios + cola). ⚠️ **Debe COINCIDIR** con el `cron_secret` que ya está guardado en el **Vault** de Supabase. Para leer el que hay (SQL Editor del Dashboard): `select decrypted_secret from vault.decrypted_secrets where name='cron_secret';` y pega ESE valor aquí. (Si prefieres cambiarlo, ver el recuadro de abajo.) |
| `PUSH_SECRET` | 🔑 Secreto **dedicado** para las notificaciones push (distinto del `CRON_SECRET`). Genera uno nuevo: `openssl rand -base64 24`. |
| `FUNCTIONS_ALLOWED_ORIGIN` | *(Opcional)* Origen web permitido en las funciones. Déjalo en `*` (la app es nativa, no le afecta). |

> **Cambiar el `CRON_SECRET`** (opcional): si generas uno nuevo, actualiza también el Vault para
> que coincidan. En el *SQL Editor*:
> ```sql
> select vault.update_secret(
>   (select id from vault.secrets where name='cron_secret'),
>   'PEGA_AQUI_EL_NUEVO_VALOR'
> );
> ```

### 1.4 Notificaciones push — Firebase  (opcional; solo si usas push)

| Variable | Dónde se saca |
|---|---|
| `FCM_SERVICE_ACCOUNT_FILE` | Ruta a un **JSON** de cuenta de servicio de Firebase. Se consigue en: [Firebase Console](https://console.firebase.google.com) → tu proyecto → ⚙️ *Configuración del proyecto* → pestaña **Cuentas de servicio** → *Generar nueva clave privada* → descarga el JSON y apunta aquí su ruta. El fichero está en `.gitignore` (nunca se sube). Déjalo vacío si aún no usas push. |

### 1.5 Actualizaciones y enlaces de descarga  (Docker / web)

| Variable | Dónde se saca |
|---|---|
| `UPDATES_DATA_DIR` | Carpeta del servidor que sirve los instaladores (Windows) + `version.json`. |
| `UPDATES_PUBLIC_URL` | Subdominio público de descargas/auto-update (tu túnel). |
| `BIND_HOST` | Déjalo en `127.0.0.1` (recomendado con Cloudflare delante). **No uses `0.0.0.0`** salvo firewall estricto. |
| `DOWNLOAD_ANDROID_PLAY_URL` | Enlace de la prueba de **Google Play** (ver [docs/GOOGLE.md](GOOGLE.md)). |
| `DOWNLOAD_IOS_URL` | Enlace de distribución no listada de **App Store** (ver [docs/APPLE.md](APPLE.md)). |
| `DOWNLOAD_WINDOWS_URL` | Ruta del instalador de Windows (por defecto la sirve tu propio servidor). |

### 1.6 Endurecimiento de Docker  (opcional; recomendado)

Todo esto es **opcional**: si lo dejas vacío, el stack arranca con valores por defecto.

| Variable | Dónde se saca |
|---|---|
| `MINIO_IMAGE` / `MC_IMAGE` / `NGINX_IMAGE` | Fijan las imágenes por *digest* (reproducible). Obtén el digest en el servidor: `docker inspect --format='{{index .RepoDigests 0}}' minio/minio:latest` (idem `minio/mc:latest`, `nginx:alpine`). Pega el `repo:tag@sha256:…`. |
| `MINIO_UID` / `MINIO_GID` | Usuario no-root de los contenedores (por defecto `1000`). En Linux, haz `chown -R 1000:1000` a `MEDIA_DATA_DIR`. |
| `*_MEM_LIMIT` / `*_CPU_LIMIT` | Topes de memoria/CPU de cada contenedor (opcionales). |

---

## 2) Aplicarlo todo en Supabase — comandos

Ejecuta desde la **raíz del proyecto**, con el `.env` ya relleno.

### Paso 1 — Apuntar la CLI al proyecto (sin `login`)

La CLI usa `SUPABASE_ACCESS_TOKEN` y `SUPABASE_PROJECT_REF` del `.env`. En bash:

```bash
set -a; source .env; set +a         # carga el .env en el entorno
supabase link --project-ref "$SUPABASE_PROJECT_REF"
```
(En PowerShell, las variables se cargan solas al usar los scripts `.ps1`.)

### Paso 2 — Aplicar las migraciones (0016–0021)

Sube toda la remediación de la base de datos (RLS, auditoría, Vault, etc.):

```bash
supabase db push
```
Aplica en orden `0016 → 0021`. Las anteriores (`0001–0015`) ya están y no se re-aplican.

> 💡 **Alternativa:** si lo prefieres, **puedo aplicarlas yo** por la cuenta que has conectado
> (el proyecto está vacío, riesgo mínimo). Solo dímelo.

### Paso 3 — Subir los secretos a las Edge Functions

Lee el `.env` y sube los secretos (por fichero temporal, no por línea de comandos):

```bash
./scripts/push-supabase-secrets.sh          # macOS / Linux
# .\scripts\push-supabase-secrets.ps1        # Windows PowerShell
```
Sube: credenciales de `media-sign`, `CRON_SECRET`, `PUSH_SECRET`, `FUNCTIONS_ALLOWED_ORIGIN`
(si lo pusiste) y el JSON de Firebase (si lo pusiste).

### Paso 4 — Desplegar las Edge Functions

Las tres de "cron" (se llaman con un secreto, no con sesión de usuario) van **sin** verificación
de JWT; el resto, con JWT normal:

```bash
supabase functions deploy media-sign
supabase functions deploy admin-users
supabase functions deploy test-smtp
supabase functions deploy send-email     --no-verify-jwt
supabase functions deploy send-push      --no-verify-jwt
supabase functions deploy notify-waitlist --no-verify-jwt
```

### Paso 5 — Ajustes de Authentication (Dashboard)

Estos **no** se pueden hacer por comando; hazlos en *Dashboard → Authentication*. El checklist
exacto está también dentro de [supabase/config.toml](../supabase/config.toml):

- **Providers → Email → "Allow new users to sign up" = OFF** (alta solo por invitación) `[C-01]`.
- **Multi-Factor Auth → TOTP (Authenticator app) = ENABLED** (opcional, no forzado) `[M-11]`.
- **Policies → Minimum password length = 10** y **"Prevent use of leaked passwords" = ON** `[M-13]`.
- **"Secure password change" / "Secure email change" = ON** (reautenticación) `[M-12]`.

### Paso 6 — Congelar versiones y recompilar la app

- Congela el `deno.lock` de las funciones (reproducibilidad) — ver
  [apéndice I-09 de docs/SEGURIDAD.md](SEGURIDAD.md#apéndice-operativo--congelar-versiones-de-las-funciones-i-09).
- Recompila la app con el `.env` ya relleno (los scripts de build hornean solo los valores
  públicos). Ver [docs/DISTRIBUCION.md](DISTRIBUCION.md).

---

## 3) Comprobar que salió bien

- **Migraciones:** `supabase migration list` → deben aparecer `0016`–`0021`.
- **Login:** entra en la app con tu cuenta; prueba activar la **2FA** en *Perfil → Verificación
  en dos pasos* (ver [docs/SEGURIDAD.md](SEGURIDAD.md#verificación-en-dos-pasos-2fa-m-11)).
- **Fotos:** crea una reserva y sube una foto (comprueba que `media-sign` firma bien; requiere
  las claves `MEDIA_SIGN_*` y la clave de MinIO creada).
- **Correo:** en *Configuración → Probar envío* debería llegarte un correo de prueba a **tu
  propio correo** (requiere el SMTP configurado en la app).
- **Seguridad:** en *Dashboard → Advisors → Security* revisa que no queden avisos importantes
  (el de "leaked password protection" desaparece al hacer el Paso 5).

> ¿Dudas con algún valor concreto? Cada variable tiene además su explicación breve en
> [.env.example](../.env.example).
