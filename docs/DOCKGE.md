# Desplegar con Dockge (Ubuntu Server)

Guía para levantar el stack de Portal Familia usando [Dockge](https://github.com/louislam/dockge)
en vez de `docker compose` a mano. Complementa a [DESPLIEGUE.md](DESPLIEGUE.md), que es donde se
explica **qué significa cada variable del `.env`**; aquí solo está lo específico de Dockge y Ubuntu.

---

## 0) Por qué este stack NO se puede pegar en el editor de Dockge

Es lo primero que hay que entender, porque ahorra media hora de pelea.

El editor de Dockge crea un `compose.yaml` y nada más. Este stack necesita **dos ficheros del repo
que viven junto al compose**:

| Referencia en `compose.yaml` | Qué es | ¿Se puede incrustar? |
|---|---|---|
| `build: ./server/media-scrub` | `Dockerfile` + `scrub.sh` que construyen la imagen del worker | **No.** Compose no tiene sintaxis para meter un contexto de construcción dentro del fichero. |
| `./server/nginx/updates.conf` | configuración de nginx del servicio `updates` | Técnicamente sí (`configs:` + `content:`), pero no compensa: obliga a escapar cada `$` como `$$` y la carpeta hace falta igual por lo de arriba. |

**Conclusión:** el stack se despliega poniendo la carpeta en el disco del servidor, y Dockge la
detecta sola. Es el flujo normal de Dockge para stacks con `build:`, no un apaño.

---

## 1) Instalar Dockge apuntando a tu home

Dockge exige que **la ruta de la carpeta de stacks sea idéntica dentro y fuera del contenedor**.
No habla con la API de Docker para levantar los stacks: ejecuta `docker compose` por debajo, y las
rutas las resuelve el *daemon* del host. Si montas `/home/USUARIO/stacks` en `/app/stacks`, los
`build:` y los *bind mounts* relativos fallan de forma difícil de diagnosticar.

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

## 2) Colocar el stack

```bash
cd ~/stacks
git clone https://github.com/Belupe/sanchezrubal_app portal-familia-src
mkdir -p portal-familia
cd portal-familia
cp -r ../portal-familia-src/compose.yaml ../portal-familia-src/server .
cp ../portal-familia-src/.env.example .env
```

La carpeta del stack tiene que quedar así — el nombre de la carpeta es el nombre que verás en Dockge:

```
~/stacks/portal-familia/
├── compose.yaml
├── .env
└── server/
    ├── nginx/updates.conf
    └── media-scrub/{Dockerfile,scrub.sh}
```

Refresca Dockge y el stack aparece en la lista, listo para editar el `.env` y arrancar desde el panel.

> El resto de `server/` (`cloudflared/`, `updates/`) no lo usa el compose: el túnel corre en el
> host. Copiarlo entero es lo más simple y no molesta.

---

## 3) Ajustar el `.env` para Linux

El `.env.example` viene con rutas de Windows. **Hay que cambiarlas o MinIO no arranca:**

```diff
-MEDIA_DATA_DIR=C:/PortalFamilia/media
-UPDATES_DATA_DIR=C:/PortalFamilia/updates
+MEDIA_DATA_DIR=/home/USUARIO/portal-familia/media
+UPDATES_DATA_DIR=/home/USUARIO/portal-familia/updates
```

Crea las carpetas y **dales el dueño correcto**. MinIO corre como UID 1000 (`user: "${MINIO_UID:-1000}:${MINIO_GID:-1000}"`)
con el sistema de ficheros de solo lectura salvo `/data`. En Windows el *bind mount* ignora el UID,
pero **en Linux no**: sin este `chown`, MinIO arranca y falla al escribir.

```bash
mkdir -p ~/portal-familia/{media,updates}
sudo chown -R 1000:1000 ~/portal-familia/media ~/portal-familia/updates
```

Las demás variables (`MEDIA_PUBLIC_URL`, secretos, Supabase…) están explicadas en
[DESPLIEGUE.md](DESPLIEGUE.md) §1. El servicio `preflight` aborta el arranque entero si algún
secreto sigue con su valor de plantilla, así que si el stack no levanta, mira **sus** logs primero.

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

La primera vez `media-scrub` tarda un poco: construye su imagen (Alpine + ffmpeg + mc).

> **Nota de arquitectura:** su `Dockerfile` descarga el cliente `mc` de MinIO fijado a
> `linux-amd64`. En un servidor x86 no hay problema; en ARM (Raspberry Pi, Ampere…) hay que
> cambiar esa URL a `linux-arm64`.

---

## 6) Actualizar

```bash
cd ~/stacks/portal-familia-src && git pull
cd ../portal-familia && cp -r ../portal-familia-src/compose.yaml ../portal-familia-src/server .
```

El `.env` no se toca al actualizar: no está en el repo, y no debe estarlo.
