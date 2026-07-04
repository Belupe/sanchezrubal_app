#!/usr/bin/env bash
# =====================================================================
#  push-supabase-secrets.sh  —  Sube los secrets de las Edge Functions
# =====================================================================
#  Adaptador [SUPABASE] del .env único: mapea los valores canónicos del
#  .env a los nombres que esperan las Edge Functions (media-sign, send-email,
#  notify-waitlist, send-push) y los sube con la CLI de Supabase. Los secrets
#  son a nivel de proyecto (los comparten todas las funciones). La nube NO lee
#  tu .env local.
#
#  Requisitos: CLI de Supabase instalada. Se autentica y apunta al proyecto
#  con SUPABASE_ACCESS_TOKEN y SUPABASE_PROJECT_REF del .env (si no, usa la
#  sesión de 'supabase login' / 'supabase link').
#
#  Uso:  ./scripts/push-supabase-secrets.sh
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
[ -f "$ENV_FILE" ] || { echo "No existe .env (cp .env.example .env y rellénalo)."; exit 1; }

# Carga el .env (ignora comentarios). Las claves quedan como variables.
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

# --- Fichero temporal 0600 con los secrets [B-07] ---
# NO se pasan por argv: los argumentos de un proceso son visibles en la tabla de
# procesos (ps -ef) para cualquier usuario local y quedan en el historial del
# shell. 'supabase secrets set --env-file' lee pares KEY=value de un fichero y no
# coloca ningún secreto en argv.
umask 077
TMP_ENV="$(mktemp "${TMPDIR:-/tmp}/sr-secrets.XXXXXX")"
chmod 600 "$TMP_ENV"
trap 'rm -f "$TMP_ENV"' EXIT INT TERM

# comillas simples => valor literal en el dotenv (sin expansión de $ ni escapes)
emit() { printf "%s='%s'\n" "$1" "$2" >> "$TMP_ENV"; }
emit MINIO_ENDPOINT         "${MEDIA_PUBLIC_URL}"
emit MINIO_BUCKET           "${MEDIA_BUCKET}"
emit MEDIA_SIGN_ACCESS_KEY  "${MEDIA_SIGN_ACCESS_KEY}"
emit MEDIA_SIGN_SECRET_KEY  "${MEDIA_SIGN_SECRET_KEY}"
emit MINIO_REGION           "${MINIO_REGION}"
emit MEDIA_MAX_UPLOAD_BYTES "${MEDIA_MAX_UPLOAD_BYTES:-104857600}"
[ -n "${CRON_SECRET:-}" ] && emit CRON_SECRET "${CRON_SECRET}"
[ -n "${PUSH_SECRET:-}" ] && emit PUSH_SECRET "${PUSH_SECRET}"   # [B-06] secreto dedicado de send-push

# FCM (push): el secret es el CONTENIDO del JSON de la service account
# (multilínea), referenciado por ruta en FCM_SERVICE_ACCOUNT_FILE. Solo si existe.
# JSON a UNA línea (se quitan CR/LF reales; los \n literales de private_key se
# conservan) y se cita en simples.
if [ -n "${FCM_SERVICE_ACCOUNT_FILE:-}" ] && [ -f "${FCM_SERVICE_ACCOUNT_FILE}" ]; then
  if command -v jq >/dev/null 2>&1; then
    FCM_JSON="$(jq -c . "${FCM_SERVICE_ACCOUNT_FILE}")"
  else
    FCM_JSON="$(tr -d '\r\n' < "${FCM_SERVICE_ACCOUNT_FILE}")"
  fi
  case "$FCM_JSON" in *\'*) echo "FCM JSON contiene comilla simple; no soportado en el dotenv temporal." >&2; exit 1;; esac
  emit FCM_SERVICE_ACCOUNT "$FCM_JSON"
fi

supabase secrets set \
  ${SUPABASE_PROJECT_REF:+--project-ref "${SUPABASE_PROJECT_REF}"} \
  --env-file "$TMP_ENV"

echo "OK  secrets subidos."
