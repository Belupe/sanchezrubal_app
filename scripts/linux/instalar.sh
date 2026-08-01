#!/usr/bin/env bash
# =====================================================================
#  instalar.sh  —  Instala Portal Familia en cualquier distro de Linux
# =====================================================================
#  Va DENTRO del .tar.gz. Es la vía para las distros que no usan .deb
#  (Arch, Fedora, openSUSE…) y para quien prefiera no usar el AppImage.
#
#  Uso:
#    ./instalar.sh                 instala SOLO PARA TI (sin contraseña)
#    ./instalar.sh --sistema       instala PARA TODOS (pide contraseña)
#    ./instalar.sh --desinstalar   quita la instalación que encuentre
#
#  Diferencia entre los dos modos:
#
#    │              │ de usuario          │ de sistema                │
#    │ dónde        │ ~/.local            │ /opt + /usr               │
#    │ contraseña   │ NO                  │ SÍ (pkexec)               │
#    │ quién la ve  │ solo tú             │ todos los usuarios        │
#    │ se actualiza │ sola, sin preguntar │ pide contraseña cada vez  │
#
#  La carpeta del modo sistema queda como propiedad de ROOT a propósito: si
#  fuese escribible por tu usuario, cualquiera que entrase con tu cuenta podría
#  cambiar un binario que después se ejecuta con privilegios. Por eso la
#  actualización pide autorización cada vez en ese modo.
# =====================================================================
set -euo pipefail

APP_ID="net.sanchezrubal.portal_familia"
NOMBRE="Portal Familia"
BIN="portal_familia"
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

MODO="usuario"
case "${1:-}" in
  --sistema)      MODO="sistema" ;;
  --desinstalar)  MODO="desinstalar" ;;
  ""|--usuario)   MODO="usuario" ;;
  -h|--help)      sed -n '2,30p' "$0"; exit 0 ;;
  *) echo "Opción desconocida: $1  (usa --sistema, --desinstalar o nada)" >&2; exit 1 ;;
esac

# --- Rutas de cada modo ----------------------------------------------
if [ "$MODO" = "sistema" ]; then
  PREFIJO="/opt/portal-familia"
  LANZADOR="/usr/local/bin/portal-familia"
  APPS="/usr/share/applications"
  ICONOS="/usr/share/icons/hicolor/256x256/apps"
else
  DATOS="${XDG_DATA_HOME:-$HOME/.local/share}"
  PREFIJO="$HOME/.local/lib/portal-familia"
  LANZADOR="$HOME/.local/bin/portal-familia"
  APPS="$DATOS/applications"
  ICONOS="$DATOS/icons/hicolor/256x256/apps"
fi

# --- Elevar a root solo cuando toca -----------------------------------
# Se prefiere pkexec: el diálogo de contraseña lo muestra EL ESCRITORIO, así
# que la contraseña no pasa por este script en ningún momento. Si no hay
# agente de PolicyKit (Arch pelado, i3, sway…), se cae a sudo.
elevar_si_hace_falta() {
  [ "$(id -u)" = "0" ] && return 0
  echo "==> Hace falta permiso de administrador para instalar en $PREFIJO"
  if command -v pkexec >/dev/null 2>&1; then
    exec pkexec "$(readlink -f "$0")" "$@"
  elif command -v sudo >/dev/null 2>&1; then
    exec sudo "$(readlink -f "$0")" "$@"
  else
    echo "No hay ni pkexec ni sudo. Instala sin root con:  ./instalar.sh" >&2
    exit 1
  fi
}

# --- Desinstalar -------------------------------------------------------
if [ "$MODO" = "desinstalar" ]; then
  borrados=0
  DATOS="${XDG_DATA_HOME:-$HOME/.local/share}"
  # De usuario primero (no necesita permisos).
  for f in "$HOME/.local/lib/portal-familia" "$HOME/.local/bin/portal-familia" \
           "$DATOS/applications/$APP_ID.desktop" \
           "$DATOS/icons/hicolor/256x256/apps/$APP_ID.png"; do
    [ -e "$f" ] && { rm -rf "$f"; borrados=$((borrados+1)); }
  done
  [ "$borrados" -gt 0 ] && echo "Quitada la instalación de usuario."
  # De sistema: solo si existe, y entonces sí hay que elevar.
  if [ -e /opt/portal-familia ]; then
    if [ "$(id -u)" != "0" ]; then elevar_si_hace_falta --desinstalar; fi
    rm -rf /opt/portal-familia /usr/local/bin/portal-familia \
           "/usr/share/applications/$APP_ID.desktop" \
           "/usr/share/icons/hicolor/256x256/apps/$APP_ID.png"
    update-desktop-database -q /usr/share/applications 2>/dev/null || true
    echo "Quitada la instalación de sistema."
    borrados=$((borrados+1))
  fi
  [ "$borrados" -eq 0 ] && echo "No había nada instalado."
  exit 0
fi

[ "$MODO" = "sistema" ] && elevar_si_hace_falta --sistema

# --- Comprobación previa ----------------------------------------------
[ -x "$DIR/$BIN" ] || {
  echo "No encuentro '$BIN' junto a este script ($DIR)." >&2
  echo "Descomprime el .tar.gz entero y ejecuta el instalar.sh de dentro." >&2
  exit 1
}

# --- Copiar ------------------------------------------------------------
echo "==> Instalando en $PREFIJO"
rm -rf "$PREFIJO"
mkdir -p "$PREFIJO" "$(dirname "$LANZADOR")" "$APPS" "$ICONOS"
cp -a "$DIR/." "$PREFIJO/"
rm -f "$PREFIJO/instalar.sh"          # el instalador no viaja a la instalación

ln -sf "$PREFIJO/$BIN" "$LANZADOR"
[ -f "$PREFIJO/$APP_ID.png" ] && cp -f "$PREFIJO/$APP_ID.png" "$ICONOS/$APP_ID.png"

# --- Entrada de menú + esquema portalfamilia:// -------------------------
cat > "$APPS/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$NOMBRE
Comment=Gestión de casas familiares
Exec=$PREFIJO/$BIN %u
Icon=$APP_ID
Categories=Office;Calendar;
Terminal=false
StartupWMClass=$APP_ID
MimeType=x-scheme-handler/portalfamilia;
EOF

# --- Manifiesto: dónde y cómo se instaló --------------------------------
# Lo lee la app al arrancar para saber si puede actualizarse sola o si tiene
# que pedir autorización, sin adivinarlo mirando permisos.
cat > "$PREFIJO/install-info.json" <<EOF
{
  "modo": "$MODO",
  "prefijo": "$PREFIJO",
  "paquete": "tar",
  "desktop": "$APPS/$APP_ID.desktop"
}
EOF

update-desktop-database -q "$APPS" 2>/dev/null || true
gtk-update-icon-cache -q -f "$(dirname "$(dirname "$(dirname "$ICONOS")")")" 2>/dev/null || true
if [ "$MODO" = "usuario" ]; then
  xdg-mime default "$APP_ID.desktop" x-scheme-handler/portalfamilia 2>/dev/null || true
fi

echo
echo "Listo. $NOMBRE instalado ($MODO)."
if [ "$MODO" = "usuario" ]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) echo "Ábrelo desde el menú, o con:  portal-familia" ;;
    *) echo "Ábrelo desde el menú, o con:  $LANZADOR"
       echo "(~/.local/bin no está en tu PATH; añádelo si quieres el comando corto.)" ;;
  esac
else
  echo "Ábrelo desde el menú, o con:  portal-familia"
fi
echo "Para quitarlo:  ./instalar.sh --desinstalar"
