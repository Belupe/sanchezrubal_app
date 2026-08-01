#!/usr/bin/env bash
# =====================================================================
#  build-linux.sh  —  Compila la app de escritorio de Linux y empaqueta
# =====================================================================
#  Espejo de scripts/build-windows.ps1: mismo orden (lee el .env → hornea
#  los valores PÚBLICOS con --dart-define → compila → empaqueta → escribe
#  version.json).
#
#  Se ejecuta DENTRO del contenedor de scripts/linux-build.Dockerfile,
#  porque Flutter no compila Linux en cruzado desde Windows y porque esa
#  imagen fija el suelo de glibc (ver el Dockerfile). Desde Windows se
#  invoca con scripts/build-linux.ps1. En una máquina Linux se puede
#  ejecutar directamente si tiene las dependencias de ese Dockerfile.
#
#  Salida en dist/linux/:
#    portal-familia-x86_64.AppImage   universal · SE AUTO-ACTUALIZA SOLO
#    portal-familia_amd64.deb         Ubuntu/Debian/Kali/Mint/Pop
#    portal-familia-<ver>-x86_64.tar.gz   cualquier otra distro
#    version.json                     (el SHA-256 lo estampa release.ps1)
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
APP="$ROOT/app_flutter"
ENV_FILE="$ROOT/.env"
OUT="$ROOT/dist/linux"
PLANTILLAS="$ROOT/scripts/linux"

APP_ID="net.sanchezrubal.portal_familia"
BIN="portal_familia"
NOMBRE="Portal Familia"

# ---------------------------------------------------------------------
#  1) Lector del .env
# ---------------------------------------------------------------------
#  Mismo criterio que build-windows.ps1: ignora comentarios y líneas vacías,
#  quita el comentario final y las comillas. Se PARSEA en vez de hacer
#  `source`: así un .env no puede ejecutar código durante la compilación.
leer_env() {   # leer_env CLAVE  ->  valor por stdout
  [ -f "$ENV_FILE" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=//p" "$ENV_FILE" | head -n1 \
    | sed -e 's/[[:space:]]\{1,\}#.*$//' \
          -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
          -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

DEFINES=()
for K in SUPABASE_URL SUPABASE_ANON_KEY MEDIA_PUBLIC_URL UPDATES_PUBLIC_URL; do
  V="$(leer_env "$K")"
  [ -n "$V" ] && DEFINES+=("--dart-define=$K=$V")
done

# ---------------------------------------------------------------------
#  2) Compilar
# ---------------------------------------------------------------------
echo "==> flutter build linux --release"
( cd "$APP" && flutter build linux --release ${DEFINES[@]+"${DEFINES[@]}"} )

REL="$APP/build/linux/x64/release/bundle"
[ -x "$REL/$BIN" ] || { echo "No se encontró el build en $REL" >&2; exit 1; }

# Aviso temprano si el binario exige una glibc más nueva que la de la base:
# es EL fallo que deja a media Linux sin poder abrir la app.
SUELO="$(objdump -T "$REL/$BIN" "$REL"/lib/*.so 2>/dev/null \
         | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1 || true)"
echo "    glibc requerida (máx): ${SUELO:-desconocida}"

# ---------------------------------------------------------------------
#  3) Versión (mismo parseo que build-windows.ps1)
# ---------------------------------------------------------------------
VERLINE="$(grep -m1 '^[[:space:]]*version:' "$APP/pubspec.yaml")"
VERNAME="$(printf '%s' "$VERLINE" | sed -n 's/.*version:[[:space:]]*\([0-9.]*\)+\([0-9]*\).*/\1/p')"
VERCODE="$(printf '%s' "$VERLINE" | sed -n 's/.*version:[[:space:]]*\([0-9.]*\)+\([0-9]*\).*/\2/p')"
: "${VERNAME:=1.0.0}"
: "${VERCODE:=1}"
BASE="$(leer_env UPDATES_PUBLIC_URL)"
: "${BASE:=https://app.sanchezrubal.net}"

rm -rf "$OUT"
mkdir -p "$OUT"
TRABAJO="$(mktemp -d)"
trap 'rm -rf "$TRABAJO"' EXIT INT TERM

ICONO="$APP/app_icons/icon_linux.png"

# Genera un .desktop; solo cambia la línea Exec entre formatos.
escribir_desktop() {   # escribir_desktop <ruta> <Exec>
  cat > "$1" <<EOF
[Desktop Entry]
Type=Application
Name=$NOMBRE
Comment=Gestión de casas familiares
Exec=$2
Icon=$APP_ID
Categories=Office;Calendar;
Terminal=false
StartupWMClass=$APP_ID
MimeType=x-scheme-handler/portalfamilia;
EOF
}

# ---------------------------------------------------------------------
#  4) AppDir  →  AppImage
# ---------------------------------------------------------------------
echo "==> AppImage"
APPDIR="$TRABAJO/AppDir"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp -a "$REL/." "$APPDIR/usr/bin/"

# libsecret SÍ se empaqueta: es dependencia ENLAZADA del ejecutable (por
# flutter_secure_storage), así que si falta en la distro del usuario la app NI
# ARRANCA ("error while loading shared libraries"). Ojo, es distinto de que no
# haya llavero corriendo: eso solo obliga a volver a iniciar sesión.
# GTK3 NO se empaqueta a propósito: arrastra temas, módulos GIO y cargadores de
# pixbuf del sistema, y empaquetarla rompe más de lo que arregla.
for lib in libsecret-1.so.0 libgcrypt.so.20; do
  ruta="$(ldconfig -p | awk -v l="$lib" '$1==l {print $NF; exit}')"
  [ -n "${ruta:-}" ] && cp -L "$ruta" "$APPDIR/usr/bin/lib/" && echo "    + $lib"
done

cp "$ICONO" "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APP_ID.png"
cp "$ICONO" "$APPDIR/$APP_ID.png"
ln -sf "$APP_ID.png" "$APPDIR/.DirIcon"
escribir_desktop "$APPDIR/$APP_ID.desktop" "$BIN %u"
cp "$APPDIR/$APP_ID.desktop" "$APPDIR/usr/share/applications/"
desktop-file-validate "$APPDIR/$APP_ID.desktop"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
AQUI="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$AQUI/usr/bin/lib:${LD_LIBRARY_PATH:-}"
exec "$AQUI/usr/bin/portal_familia" "$@"
EOF
chmod +x "$APPDIR/AppRun"

ARCH=x86_64 appimagetool "$APPDIR" "$OUT/portal-familia-x86_64.AppImage" >/dev/null

# ---------------------------------------------------------------------
#  5) .deb  (Ubuntu / Debian / Kali / Mint / Pop)
# ---------------------------------------------------------------------
echo "==> .deb"
DEB="$TRABAJO/deb"
mkdir -p "$DEB/opt/portal-familia" "$DEB/usr/bin" "$DEB/DEBIAN" \
         "$DEB/usr/share/applications" "$DEB/usr/share/icons/hicolor/256x256/apps"
cp -a "$REL/." "$DEB/opt/portal-familia/"
ln -sf /opt/portal-familia/$BIN "$DEB/usr/bin/portal-familia"
cp "$ICONO" "$DEB/usr/share/icons/hicolor/256x256/apps/$APP_ID.png"
escribir_desktop "$DEB/usr/share/applications/$APP_ID.desktop" "/opt/portal-familia/$BIN %u"

cat > "$DEB/opt/portal-familia/install-info.json" <<EOF
{
  "modo": "sistema",
  "prefijo": "/opt/portal-familia",
  "paquete": "deb",
  "desktop": "/usr/share/applications/$APP_ID.desktop"
}
EOF

# Las dependencias NO se escriben a mano: dpkg-shlibdeps las deduce del binario
# real, así que los nombres de paquete y las versiones mínimas salen correctos
# en cada versión de Debian/Ubuntu (libsecret-1-0, libgtk-3-0, libjsoncpp…).
DEPS="libgtk-3-0, libglib2.0-0, libsecret-1-0, libstdc++6"
if command -v dpkg-shlibdeps >/dev/null 2>&1; then
  ( cd "$DEB" && mkdir -p debian && : > debian/control \
    && DEDUCIDAS="$(dpkg-shlibdeps -O --ignore-missing-info \
         "opt/portal-familia/$BIN" opt/portal-familia/lib/*.so 2>/dev/null \
         | sed -n 's/^shlibs:Depends=//p')" \
    && [ -n "$DEDUCIDAS" ] && printf '%s' "$DEDUCIDAS" > .deps || true
    rm -rf debian )
  [ -s "$DEB/.deps" ] && DEPS="$(cat "$DEB/.deps")"
  rm -f "$DEB/.deps"
fi

cat > "$DEB/DEBIAN/control" <<EOF
Package: portal-familia
Version: $VERNAME
Architecture: amd64
Maintainer: Sanchez Rubal <soporte@sanchezrubal.net>
Section: utils
Priority: optional
Depends: $DEPS, xdg-utils
Recommends: gnome-keyring | kwalletmanager
Description: Portal Familia
 Gestión de casas familiares: calendario, reservas, inspecciones con
 fotos y vídeo, anuncios y sorteos.
EOF

# gnome-keyring va en Recommends (apt lo instala por defecto): sin un llavero
# activo la app funciona, pero hay que volver a iniciar sesión cada vez.
cat > "$DEB/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
# Registra el menú, el icono y el esquema portalfamilia:// (equivale al bloque
# [Registry] de scripts/windows-installer.iss). Best-effort: que no falle la
# instalación si el usuario no tiene sesión gráfica.
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q -f /usr/share/icons/hicolor 2>/dev/null || true
EOF
cp "$DEB/DEBIAN/postinst" "$DEB/DEBIAN/postrm"
chmod 0755 "$DEB/DEBIAN/postinst" "$DEB/DEBIAN/postrm"

fakeroot dpkg-deb --build "$DEB" "$OUT/portal-familia_amd64.deb" >/dev/null

# ---------------------------------------------------------------------
#  6) .tar.gz  (cualquier otra distro, con instalar.sh de dos modos)
# ---------------------------------------------------------------------
echo "==> .tar.gz"
TAR="$TRABAJO/portal-familia-$VERNAME"
mkdir -p "$TAR"
cp -a "$REL/." "$TAR/"
cp "$ICONO" "$TAR/$APP_ID.png"
cp "$PLANTILLAS/instalar.sh" "$TAR/instalar.sh"
chmod +x "$TAR/instalar.sh"
tar -C "$TRABAJO" -czf "$OUT/portal-familia-$VERNAME-x86_64.tar.gz" \
    "portal-familia-$VERNAME"

# ---------------------------------------------------------------------
#  7) version.json
# ---------------------------------------------------------------------
#  Mismo esquema que el de Windows, más `urlDeb` para el canal de sistema.
#  Los campos sha256/sha256Deb los AÑADE scripts/release.ps1 al publicar [C-02],
#  para que la verificación de integridad viva en un único sitio.
cat > "$OUT/version.json" <<EOF
{
  "versionCode": $VERCODE,
  "versionName": "$VERNAME",
  "url": "$BASE/linux/portal-familia-x86_64.AppImage",
  "urlDeb": "$BASE/linux/portal-familia_amd64.deb",
  "mandatory": false,
  "notes": "Versión $VERNAME"
}
EOF

echo
echo "OK  Linux $VERNAME (build $VERCODE)  ->  $OUT"
ls -1sh "$OUT"
