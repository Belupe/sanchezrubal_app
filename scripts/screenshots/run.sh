#!/usr/bin/env bash
#
# Genera las capturas de pantalla para App Store Connect.
#
#   ./scripts/screenshots/run.sh                  # iPhone 6,9" + iPad 13"
#   ./scripts/screenshots/run.sh --dispositivo=iphone
#   ./scripts/screenshots/run.sh --salida=/tmp/capturas
#
# Qué hace, por orden:
#   1. Copia `app_flutter/` a una carpeta temporal y le añade el objetivo web.
#   2. Aplica `overlay/`: sustituye los servicios que dependen de `dart:io`
#      (registro, auto-update, escritorio de Linux, push) por dobles inertes, y
#      añade `main_shots.dart` como punto de entrada.
#   3. Compila la app en release contra un backend local.
#   4. Levanta `mock_backend.mjs`, que sirve la app Y hace de Supabase con datos
#      de demostración.
#   5. Recorre la app con Chromium emulando iPhone y iPad, y guarda los PNG en
#      la resolución exacta que exige Apple.
#
# NADA de esto toca `app_flutter/`: la copia es aparte y el repositorio queda
# igual. Ver README.md.
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$AQUI/../.." && pwd)"

SALIDA="$RAIZ/docs/capturas"
DISPOSITIVO="todos"
PUERTO="8787"

for a in "$@"; do
  case "$a" in
    --salida=*)      SALIDA="${a#*=}" ;;
    --dispositivo=*) DISPOSITIVO="${a#*=}" ;;
    --puerto=*)      PUERTO="${a#*=}" ;;
    -h|--help)       sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Opción desconocida: $a" >&2; exit 1 ;;
  esac
done

# --- Herramientas ------------------------------------------------------------
command -v flutter >/dev/null || { echo "Falta Flutter en el PATH." >&2; exit 1; }
command -v node    >/dev/null || { echo "Falta Node.js en el PATH." >&2; exit 1; }

FLUTTER_ROOT="$(cd "$(dirname "$(command -v flutter)")/.." && pwd)"
FUENTES="$FLUTTER_ROOT/bin/cache/artifacts/material_fonts"
[ -d "$FUENTES" ] || flutter precache --universal >/dev/null

export NPM_GLOBAL_ROOT="$(npm root -g 2>/dev/null || true)"
if ! node -e "require.resolve('playwright')" 2>/dev/null \
   && [ ! -d "${NPM_GLOBAL_ROOT:-/nonexistent}/playwright" ]; then
  echo "Falta Playwright. Instálalo con:  npm i -g playwright" >&2
  exit 1
fi

# --- 1. Copia de trabajo -----------------------------------------------------
TMP="$(mktemp -d "${TMPDIR:-/tmp}/portal-familia-capturas.XXXXXX")"

limpiar() {
  if [ -n "${SRV_PID:-}" ]; then kill "$SRV_PID" 2>/dev/null || true; fi
  rm -rf "$TMP"
}
trap limpiar EXIT

echo "▸ Preparando copia de trabajo…"
mkdir -p "$TMP/app"
cp -r "$RAIZ/app_flutter/lib" \
      "$RAIZ/app_flutter/pubspec.yaml" \
      "$RAIZ/app_flutter/pubspec.lock" \
      "$RAIZ/app_flutter/analysis_options.yaml" "$TMP/app/"

(cd "$TMP/app" && flutter create --platforms=web --project-name portal_familia . >/dev/null)

# --- 2. Capa de sustitución --------------------------------------------------
cp "$AQUI/overlay/log_service.dart" \
   "$AQUI/overlay/update_service.dart" \
   "$AQUI/overlay/linux_desktop_integration.dart" \
   "$AQUI/overlay/push_service.dart" "$TMP/app/lib/services/"
cp "$AQUI/overlay/main_shots.dart" "$TMP/app/lib/"
# Arranque propio: redirige los tipos de letra de respaldo al servidor local.
cp "$AQUI/overlay/flutter_bootstrap.js" "$TMP/app/web/"

# Roboto empaquetada: en el navegador no hay fuentes del sistema y, sin esto, el
# motor saldría a fonts.gstatic.com justo mientras se toma la captura.
mkdir -p "$TMP/app/assets/fonts"
cp "$FUENTES"/Roboto-{Regular,Medium,Bold,Light,Italic,BoldItalic}.ttf "$TMP/app/assets/fonts/"
python3 "$AQUI/fuentes.py" "$TMP/app/pubspec.yaml"

# --- 3. Compilación ----------------------------------------------------------
echo "▸ Compilando la app para web (release)…"
(cd "$TMP/app" && flutter pub get >/dev/null && \
  flutter build web --release --no-web-resources-cdn --no-wasm-dry-run \
    -t lib/main_shots.dart \
    --dart-define=SUPABASE_URL="http://127.0.0.1:$PUERTO" \
    --dart-define=SUPABASE_ANON_KEY=sb_publishable_capturas_demo >/dev/null)

# --- 4. Backend simulado -----------------------------------------------------
echo "▸ Levantando el backend de demostración en el puerto $PUERTO…"
node "$AQUI/mock_backend.mjs" "$TMP/app/build/web" "$PUERTO" >"$TMP/servidor.log" 2>&1 &
SRV_PID=$!

for _ in $(seq 1 40); do
  if curl -sf "http://127.0.0.1:$PUERTO/rest/v1/properties?select=id" >/dev/null; then break; fi
  sleep 0.25
done

# --- 5. Capturas -------------------------------------------------------------
echo "▸ Capturando…"
mkdir -p "$SALIDA"
node "$AQUI/capture.mjs" \
  --salida="$SALIDA" \
  --url="http://127.0.0.1:$PUERTO" \
  --dispositivo="$DISPOSITIVO"
