#!/usr/bin/env bash
# Compila el App Bundle de Google Play. Equivalente de build-aab.ps1 para macOS/Linux.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/app_flutter"
env_file="$root/.env"; [ -f "$env_file" ] || env_file="$root/env"

export PATH="$HOME/flutter/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

leer_env() { # clave -> valor, sin comillas ni comentario final
  [ -f "$env_file" ] || return 0
  sed -n "s/^$1=//p" "$env_file" | head -1 | sed 's/[[:space:]]*#.*$//' | tr -d "\"'"
}

# Play exige un keystore real. build.gradle.kts falla el release si falta, en vez
# de caer a la firma debug (que Play rechaza de todos modos).
if [ ! -f "$app/android/key.properties" ]; then
  echo "ERROR: falta app_flutter/android/key.properties." >&2
  echo "Crea el keystore de subida y ese fichero antes de publicar (docs/GOOGLE.md)." >&2
  exit 1
fi

# Valores públicos + auto-update DESACTIVADO: Play prohíbe que la app se
# actualice por su cuenta.
defines=(--dart-define=ENABLE_SELF_UPDATE=false)
for k in SUPABASE_URL SUPABASE_ANON_KEY MEDIA_PUBLIC_URL; do
  v="$(leer_env "$k")"
  [ -n "$v" ] && defines+=("--dart-define=$k=$v")
done

echo "==> flutter build appbundle --release (Google Play, self-update OFF)"
cd "$app"
flutter build appbundle --release "${defines[@]}"

aab="$app/build/app/outputs/bundle/release/app-release.aab"
[ -f "$aab" ] || { echo "No se encontró el .aab en $aab" >&2; exit 1; }

version_line="$(grep -m1 '^version:' "$app/pubspec.yaml")"
ver_name="$(echo "$version_line" | sed -E 's/version:[[:space:]]*([0-9.]+)\+.*/\1/')"
ver_code="$(echo "$version_line" | sed -E 's/.*\+([0-9]+).*/\1/')"

out="$root/dist/googleplay"
mkdir -p "$out"
dst="$out/portal-familia-$ver_name-$ver_code.aab"
cp -f "$aab" "$dst"

echo
echo "OK  App Bundle $ver_name (build $ver_code)"
echo "    -> $dst"
echo
echo "Siguiente paso: súbelo a mano en Play Console (pista de prueba interna)."
echo "Guía: docs/GOOGLE.md"
