# Desplegar con Dockge (Ubuntu Server)

Guía para levantar el stack de Portal Familia usando [Dockge](https://github.com/louislam/dockge)
en vez de `docker compose` a mano. Complementa a [DESPLIEGUE.md](DESPLIEGUE.md), que es donde se
explica **qué significa cada variable del `.env`**; aquí solo está lo específico de Dockge y Ubuntu.

**El [`compose.yaml`](../compose.yaml) es autosuficiente:** no hay que copiar ningún fichero al
servidor. Todas las imágenes se descargan (`media-scrub` la publica GitHub Actions en GHCR) y la
config de nginx va incrustada en el propio compose. Se pega en el editor de Dockge y funciona.

> **Requisito:** Docker Compose **v2.23 o superior** (el compose usa `configs` con `content:`).
> Compruébalo con `docker compose version`. Cualquier instalación reciente de `docker-ce` lo cumple.

---

## 1) Instalar Dockge apuntando a tu home

Dockge exige que **la ruta de la carpeta de stacks sea idéntica dentro y fuera del contenedor**.
No habla con la API de Docker para levantar los stacks: ejecuta `docker compose` por debajo, y las
rutas las resuelve el *daemon* del host. Si montas `/home/USUARIO/stacks` en `/app/stacks`, las
rutas relativas fallan de forma difícil de diagnosticar.

Sustituye `USUARIO` por el tuyo en los tres sitios:

```yaml
# ~/dockge/compose.yaml
services:
  dockge:
    image: louislam/dockge:1
    container_name: dockge
    restart: unless-stopped
    ports:
      - 5001:5001
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      - /home/USUARIO/stacks:/home/USUARIO/stacks   # <<< misma ruta a ambos lados
    environment:
      - DOCKGE_STACKS_DIR=/home/USUARIO/stacks      # <<< y aquí igual
```

```bash
mkdir -p ~/dockge ~/stacks
cd ~/dockge && docker compose up -d
```

Panel en `http://IP_DEL_SERVIDOR:5001`.

---

## 2) Crear el stack

En Dockge: **+ Compose** → nombre `portal-familia` → pega el contenido de
[`compose.yaml`](../compose.yaml) en el editor → pega tu `.env` en la pestaña de variables de
entorno. Nada más.

Dockge lo guardará en `~/stacks/portal-familia/`. No hace falta clonar el repositorio en el
servidor ni copiar carpetas.

---

## 3) Preparar las carpetas de datos (esto sí es tuyo)

El compose no crea las carpetas del host: solo las monta. Elige dónde quieres los datos y créalas
**antes** de arrancar.

En el `.env`, cambia las rutas de Windows que trae la plantilla:

```diff
-MEDIA_DATA_DIR=C:/PortalFamilia/media
-UPDATES_DATA_DIR=C:/PortalFamilia/updates
+MEDIA_DATA_DIR=/home/USUARIO/portal-familia/media
+UPDATES_DATA_DIR=/home/USUARIO/portal-familia/updates
```

Créalas y **dales el dueño correcto**. MinIO corre como UID 1000
(`user: "${MINIO_UID:-1000}:${MINIO_GID:-1000}"`) con el sistema de ficheros de solo lectura salvo
`/data`. En Windows el *bind mount* ignora el UID, pero **en Linux no**: sin este `chown`, MinIO
arranca y falla al escribir.

```bash
mkdir -p ~/portal-familia/{media,updates}
sudo chown -R 1000:1000 ~/portal-familia/media ~/portal-familia/updates
```

Las demás variables (secretos, Supabase, URLs públicas) están explicadas en
[DESPLIEGUE.md](DESPLIEGUE.md) §1.

---

## 4) Puertos y túnel

Por defecto todo escucha solo en local:

```
BIND_HOST=127.0.0.1
```

Es lo correcto: los servicios no se exponen a la red, y **cloudflared publica hacia fuera desde el
host** (ver `server/cloudflared/config.example.yml`). No abras estos puertos en el cortafuegos.

| Servicio | Puerto local | Sale por el túnel como |
|---|---|---|
| MinIO API (S3) | 9000 | `MEDIA_PUBLIC_URL` |
| MinIO consola | 9001 | `MINIO_CONSOLE_URL` (opcional) |
| updates (nginx) | 8090 | `UPDATES_PUBLIC_URL` |

`MEDIA_PUBLIC_URL` tiene que coincidir **exactamente** con el dominio del túnel: MinIO lo usa como
`MINIO_SERVER_URL` para firmar las URLs prefirmadas, y si no cuadra, las firmas se rechazan y la app
no ve las fotos. Es el fallo más común de este despliegue.

---

## 5) Comprobar que arrancó

Desde el panel de Dockge, o por terminal:

```bash
cd ~/stacks/portal-familia
docker compose ps
docker compose logs preflight    # debe decir: [.env] Validación OK: sin placeholders.
docker compose logs createbuckets
docker compose logs media-scrub  # [media-scrub] conectado. Vigilando subidas…
```

Si el stack no levanta, **mira `preflight` primero**: aborta el arranque entero si algún secreto
sigue con su valor de plantilla.

---

## 6) La imagen de media-scrub

`media-scrub` es un worker que quita los metadatos (EXIF/GPS) de los vídeos subidos. Su imagen la
construye y publica **GitHub Actions** ([`.github/workflows/media-scrub.yml`](../.github/workflows/media-scrub.yml))
en GHCR cada vez que cambia algo en `server/media-scrub/`. El servidor solo la descarga.

| Etiqueta | Para qué |
|---|---|
| `ghcr.io/belupe/media-scrub:latest` | la que usa el compose por defecto |
| `ghcr.io/belupe/media-scrub:sha-<hash>` | inmutable, para fijar una versión en `MEDIA_SCRUB_IMAGE` |

**El paquete tiene que ser público**, o el servidor no podrá descargarlo sin autenticarse. La
primera publicación lo crea privado: ve a la pestaña **Packages** del repositorio → `media-scrub` →
*Package settings* → *Change visibility* → **Public**. Si prefieres dejarlo privado, hay que hacer
`docker login ghcr.io` en el servidor con un token que tenga `read:packages`.

La imagen se construye para **linux/amd64** (el `Dockerfile` fija el cliente `mc` a esa
arquitectura). Si algún día mueves el servidor a ARM, hay que parametrizar esa URL y añadir
`linux/arm64` a `platforms:` en el workflow.

Para actualizar el worker en el servidor, basta con volver a bajar la imagen:

```bash
cd ~/stacks/portal-familia
docker compose pull media-scrub && docker compose up -d media-scrub
```

---

## 7) Actualizar el stack

Cuando cambie el `compose.yaml` del repositorio, pega la versión nueva en el editor de Dockge y
redespliega. El `.env` no se toca: no está en el repositorio, y no debe estarlo.
