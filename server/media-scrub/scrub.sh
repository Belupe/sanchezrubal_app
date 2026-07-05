#!/usr/bin/env bash
# =====================================================================
#  media-scrub — quita los metadatos (EXIF/GPS/creación) de los VÍDEOS
#  subidos a MinIO. [2L-12]
# =====================================================================
#  Vigila el bucket con `mc watch`; ante cada subida de un vídeo, lo descarga,
#  lo re-muxa con ffmpeg (-map_metadata -1 -c copy, SIN recodificar) y lo vuelve
#  a subir marcado como 'Scrubbed=1' para no reprocesarlo (evita el bucle del
#  evento que dispara la propia re-subida). Las fotos ya pierden EXIF al
#  reencodarse en el cliente (image_picker imageQuality<100).
#
#  Es un worker interno (misma red Docker que MinIO); usa las credenciales root
#  de MinIO porque `mc watch` necesita escuchar notificaciones del bucket.
# =====================================================================
set -uo pipefail

ENDPOINT="${MINIO_ENDPOINT:-http://minio:9000}"
BUCKET="${MEDIA_BUCKET:-inspections}"
ACCESS="${MINIO_ROOT_USER:?falta MINIO_ROOT_USER}"
SECRET="${MINIO_ROOT_PASSWORD:?falta MINIO_ROOT_PASSWORD}"

is_video() {
  case "${1,,}" in
    *.mp4|*.mov|*.webm|*.mkv|*.avi|*.m4v) return 0 ;;
    *) return 1 ;;
  esac
}

echo "[media-scrub] esperando a MinIO en $ENDPOINT…"
until mc alias set local "$ENDPOINT" "$ACCESS" "$SECRET" >/dev/null 2>&1; do sleep 2; done
echo "[media-scrub] conectado. Vigilando subidas de vídeo en '$BUCKET'…"

scrub_one() {
  local key="$1"
  # Loop-guard: si el objeto ya está marcado, no reprocesar (la re-subida vuelve
  # a disparar el evento put; esta marca corta el bucle).
  if mc stat --json "local/$BUCKET/$key" 2>/dev/null \
       | jq -e '(.metadata // {}) | to_entries | any(.key | ascii_downcase == "x-amz-meta-scrubbed")' \
       >/dev/null 2>&1; then
    return 0
  fi

  local tmp; tmp="$(mktemp -d)"
  local ext="${key##*.}"
  local in="$tmp/in.$ext" out="$tmp/out.$ext"

  if ! mc cp --quiet "local/$BUCKET/$key" "$in" >/dev/null 2>&1; then
    rm -rf "$tmp"; return 0
  fi
  # -map_metadata -1 elimina TODOS los metadatos; -c copy no recodifica (rápido).
  if ffmpeg -y -i "$in" -map_metadata -1 -c copy "$out" >/dev/null 2>&1; then
    if mc cp --quiet --attr "Scrubbed=1" "$out" "local/$BUCKET/$key" >/dev/null 2>&1; then
      echo "[media-scrub] limpiado: $key"
    fi
  else
    echo "[media-scrub] ffmpeg no pudo procesar (se deja tal cual): $key" >&2
  fi
  rm -rf "$tmp"
}

# Un JSON por evento; la ruta llega como 'bucket/key'. Reintenta si el stream cae.
while true; do
  mc watch --json --events put "local/$BUCKET" 2>/dev/null | while read -r line; do
    path="$(printf '%s' "$line" | jq -r '.path // empty' 2>/dev/null || true)"
    [ -z "$path" ] && continue
    key="${path#"$BUCKET"/}"
    is_video "$key" || continue
    scrub_one "$key" || true
  done
  echo "[media-scrub] stream de eventos cerrado; reintentando en 5s…" >&2
  sleep 5
done
