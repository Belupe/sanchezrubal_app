# Linux — AppImage (cualquier distro) + `.deb` + auto-update

App de escritorio Flutter, **sin firma de código** (en Linux no hace falta: no hay SmartScreen
ni Gatekeeper que avise). Se distribuye en **tres formatos** alojados en tu Docker, con
auto-actualización igual que Windows.

| Formato | Para quién | ¿Pide contraseña? | ¿Se actualiza sola? |
|---|---|---|---|
| **AppImage** | **Cualquier** distro: Ubuntu, Kali, Arch, Fedora, Manjaro, openSUSE… | No | **Sí, sola** |
| **`.deb`** | Ubuntu · Debian · Kali · Mint · Pop!\_OS | Sí, al instalar y al actualizar | Sí, pidiendo contraseña |
| **`.tar.gz`** | Cualquier distro, con instalador de dos modos | Solo en modo `--sistema` | Sí (modo usuario, sin contraseña) |

> **El recomendado para la familia es el AppImage**: un solo fichero, no instala nada, funciona
> en todas las distros y se actualiza solo sin pedir nada.

---

## Requisitos (en tu PC de desarrollo)

**Solo Docker** — el mismo que ya usas para el servidor (`docker compose up -d`). No hace falta
un ordenador con Linux ni instalar Flutter para Linux: se compila dentro de un contenedor.

Es obligatorio hacerlo así porque **Flutter no puede compilar Linux desde Windows** (no hay
compilación cruzada), y porque la imagen fija la versión de las librerías del sistema, que es lo
que decide en qué distros arrancará la app (ver "Por qué Ubuntu 22.04" más abajo).

## Compilar y publicar

```powershell
./scripts/release.ps1 -Bump        # Windows + Linux; o solo Linux:
./scripts/build-linux.ps1
```

Construye la imagen `scripts/linux-build.Dockerfile` (la primera vez tarda: descarga el SDK de
Flutter) y ejecuta dentro [scripts/build-linux.sh](../scripts/build-linux.sh), que deja en
`dist/linux/`:

```
portal-familia-x86_64.AppImage        universal, se auto-actualiza
portal-familia_amd64.deb              Ubuntu/Debian/Kali/Mint
portal-familia-<versión>-x86_64.tar.gz
version.json                          (release.ps1 le estampa los SHA-256)
```

`release.ps1` los publica en `UPDATES_DATA_DIR/linux/` y regenera la página de descargas. Si el
servidor está en otra máquina, copia ahí el contenido de `dist/`.

En una máquina que ya sea Linux puedes saltarte Docker y ejecutar `./scripts/build-linux.sh`
directamente, siempre que tenga las dependencias que instala ese Dockerfile.

### Por qué la imagen es Ubuntu 22.04 y no la última

No es un descuido, y **subirla rompería la app en muchos equipos**. Son dos problemas distintos:

1. **glibc no es compatible hacia adelante.** Un binario compilado contra una glibc nueva no
   arranca en una distro con una más vieja (`version 'GLIBC_2.38' not found`), y ni el AppImage
   ni el `.deb` lo arreglan: empaquetan las librerías de la app, no la libc del sistema. Está
   comprobado: compilando en Ubuntu 24.04, `flutter_secure_storage` exige `GLIBC_2.38`, lo que
   dejaría fuera a Ubuntu 22.04 y Debian 12.
2. **Los nombres de los paquetes del `.deb`.** Ubuntu 24.04 renombró medio sistema por la
   transición de `time_t` a 64 bits: allí las dependencias salen como `libgtk-3-0t64`,
   `libglib2.0-0t64`… que **no existen** en Ubuntu 22.04 ni en Debian 12, así que el `.deb`
   sería ininstalable allí. Compilando en 22.04 salen los nombres sin sufijo, y esos sí valen
   también en 24.04.

Ubuntu 22.04 (glibc 2.35) cubre Ubuntu 22.04+, Debian 12+, Kali rolling, Arch, Fedora 36+,
Mint 21+ y Pop!\_OS 22.04+.

---

## Instalar (familia)

Abre `https://app.sanchezrubal.net` y elige según tu distro.

### Ubuntu · Debian · Kali · Linux Mint · Pop!_OS → el `.deb`

Descarga el `.deb` y haz doble clic, o desde la terminal:

```bash
sudo apt install ./portal-familia_amd64.deb
```

> Usa `apt install ./fichero.deb`, **no** `dpkg -i`: `apt` instala también las librerías que
> falten. Con `dpkg -i` puede quedarse a medias y dar
> `error while loading shared libraries: libsecret-1.so.0` (se arregla con
> `sudo apt --fix-broken install`).

Queda en el menú de aplicaciones. Se instala **para todos los usuarios del equipo**, por eso pide
la contraseña de administrador tanto al instalar como al actualizar.

### Arch · Manjaro · Fedora · openSUSE · cualquier otra → el AppImage

```bash
chmod +x portal-familia-x86_64.AppImage     # o Propiedades → Permisos → «Permitir ejecutar»
./portal-familia-x86_64.AppImage
```

No instala nada: es un solo fichero. **Guárdalo en una carpeta tuya** (por ejemplo
`~/Aplicaciones/`), porque para poder actualizarse solo necesita permiso de escritura donde esté.
La primera vez que lo abras se añadirá solo al menú de aplicaciones.

### Alternativa para cualquier distro → el `.tar.gz`

Descomprime y ejecuta el instalador que trae dentro:

```bash
tar xzf portal-familia-1.0.0-x86_64.tar.gz
cd portal-familia-1.0.0
./instalar.sh                # solo para ti, en ~/.local, SIN contraseña
./instalar.sh --sistema      # para todos, en /opt, CON contraseña
./instalar.sh --desinstalar  # quita cualquiera de las dos
```

|  | `./instalar.sh` | `./instalar.sh --sistema` |
|---|---|---|
| Dónde | `~/.local/lib/portal-familia` | `/opt/portal-familia` |
| Contraseña al instalar | No | Sí |
| Quién la ve en el menú | Solo tú | Todos los usuarios |
| Al actualizar | Sola, sin preguntar | Pide contraseña cada vez |

**Por qué el modo de sistema pide la contraseña cada vez** y no se puede desactivar: la carpeta
queda como propiedad de `root` a propósito. Si fuese escribible por tu usuario, cualquiera que
entrase con tu cuenta podría cambiar un binario que después se ejecuta con privilegios. Si no
quieres escribir la contraseña nunca, usa el **AppImage** o la instalación de usuario: esas dos
se actualizan solas.

---

## Cómo funciona el auto-update

Al abrir, la app consulta `${UPDATES_PUBLIC_URL}/linux/version.json`. Si hay versión nueva,
descarga el paquete, **verifica su SHA-256** y lo instala según cómo esté instalada:

- **AppImage** → se reemplaza a sí mismo y se relanza. Sin contraseña.
- **Instalación de usuario** (`~/.local`) → reemplaza sus ficheros y se relanza. Sin contraseña.
- **Instalación de sistema** (`.deb` o `--sistema`) → instala el `.deb` nuevo elevando con
  **PolicyKit**. El diálogo de contraseña lo muestra tu escritorio, no la app: **la contraseña
  no pasa nunca por Portal Familia**.
- **Cualquier otro caso** (por ejemplo un AppImage en una carpeta donde no puedes escribir) →
  solo avisa y abre la página de descargas.

La app sabe en cuál de estos casos está leyendo un `install-info.json` que dejan el `.deb` y
`instalar.sh`, en vez de adivinarlo.

Sea cual sea el camino, **nunca se ejecuta ni se instala nada cuyo SHA-256 no coincida** con el
publicado, y solo se descarga desde el mismo dominio de `UPDATES_PUBLIC_URL` por HTTPS.

---

## Lo que NO hay en Linux (ni en Windows)

- **No se pueden hacer fotos ni vídeos desde el ordenador.** El selector abre tus **archivos**;
  para capturar con cámara se usa el móvil (Android o iPhone). Es igual en Windows y macOS, así
  que el botón "Cámara" solo aparece en el móvil.
- **No hay notificaciones push.** Firebase no soporta Linux de escritorio. Los avisos por
  **correo** siguen llegando igual.

## Llavero: que no te pida la contraseña cada vez

La sesión (el "estás dentro") se guarda cifrada en el **llavero del sistema**. En Ubuntu, Kali,
Fedora, Mint o Manjaro con escritorio ya viene uno y **se desbloquea solo al iniciar sesión**, así
que no notarás nada. El `.deb` además lo instala por su cuenta.

En distros minimalistas o gestores de ventanas pelados (Arch básica, i3, sway) puede no haber
ninguno. Entonces la app **funciona igual, pero te pedirá iniciar sesión cada vez que la abras**.
Se arregla instalando uno:

```bash
sudo apt install gnome-keyring      # Debian, Ubuntu, Kali, Mint
sudo pacman -S gnome-keyring        # Arch, Manjaro
sudo dnf install gnome-keyring      # Fedora
```

Es la sesión **de la app**, no la de Linux: nunca se te pedirá la contraseña del ordenador para
entrar en Portal Familia.

---

## Problemas frecuentes

| Qué ves | Por qué | Cómo se arregla |
|---|---|---|
| `version 'GLIBC_2.xx' not found` | Tu distro es más antigua que la máquina donde se compiló | Avísanos: hay que bajar la base de `scripts/linux-build.Dockerfile` |
| `dlopen(): error loading libfuse.so.2` | Al AppImage le falta FUSE 2 | `sudo apt install libfuse2`, o ejecútalo con `--appimage-extract-and-run`. En Ubuntu/Debian/Kali, mejor usa el `.deb` |
| `Permission denied` al abrir el AppImage | Le falta el permiso de ejecución | `chmod +x portal-familia-x86_64.AppImage` |
| `error while loading shared libraries: libsecret-1.so.0` | Se instaló con `dpkg -i` sin resolver dependencias | `sudo apt --fix-broken install` |
| Te pide iniciar sesión cada vez que abres la app | No hay llavero del sistema | Instala `gnome-keyring` (ver arriba) |
| Los enlaces de los correos no abren la app | El `.desktop` no está registrado | Abre la app una vez (se registra sola). Si no: `xdg-mime default net.sanchezrubal.portal_familia.desktop x-scheme-handler/portalfamilia` |
| "No se pudo escribir junto a la app" al actualizar | El AppImage está donde no puedes escribir | Muévelo a una carpeta tuya, p. ej. `~/Aplicaciones/` |
| Ventana en blanco (sobre todo en máquinas virtuales) | Sin aceleración gráfica | `LIBGL_ALWAYS_SOFTWARE=1 ./portal-familia-x86_64.AppImage` |
| Al abrir un enlace no pasa nada y la app ya estaba abierta | Es de instancia única: el enlace va a la ventana existente | Mira la ventana ya abierta; debería haber navegado sola |

Para comprobar que el esquema de los correos está bien registrado:

```bash
xdg-mime query default x-scheme-handler/portalfamilia
# → net.sanchezrubal.portal_familia.desktop
xdg-open 'portalfamilia://inspeccion/<uuid-de-la-reserva>'
```

## Si algo falla

La app deja un informe técnico del último fallo. Ver **[docs/REGISTROS.md](REGISTROS.md)**:
Configuración → **Abrir carpeta de registros**.
