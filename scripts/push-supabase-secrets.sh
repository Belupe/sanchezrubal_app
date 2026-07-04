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

ARGS=(
  "MINIO_ENDPOINT=${MEDIA_PUBLIC_URL}"
  "MINIO_BUCKET=${MEDIA_BUCKET}"
  "MEDIA_SIGN_ACCESS_KEY=${MEDIA_SIGN_ACCESS_KEY}"
  "MEDIA_SIGN_SECRET_KEY=${MEDIA_SIGN_SECRET_KEY}"
  "MINIO_REGION=${MINIO_REGION}"
  "MEDIA_MAX_UPLOAD_BYTES=${MEDIA_MAX_UPLOAD_BYTES:-104857600}"
)
[ -n "${CRON_SECRET:-}" ] && ARGS+=("CRON_SECRET=${CRON_SECRET}")

# FCM (push): el secret es el CONTENIDO del JSON de la service account
# (multilínea), referenciado por ruta en FCM_SERVICE_ACCOUNT_FILE. Solo si existe.
if [ -n "${FCM_SERVICE_ACCOUNT_FILE:-}" ] && [ -f "${FCM_SERVICE_ACCOUNT_FILE}" ]; then
  ARGS+=("FCM_SERVICE_ACCOUNT=$(cat "${FCM_SERVICE_ACCOUNT_FILE}")")
fi

supabase secrets set \
  ${SUPABASE_PROJECT_REF:+--project-ref "${SUPABASE_PROJECT_REF}"} \
  "${ARGS[@]}"

echo "OK  secrets subidos."
