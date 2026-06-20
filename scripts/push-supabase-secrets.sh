#!/usr/bin/env bash
# =====================================================================
#  push-supabase-secrets.sh  —  Sube los secrets de las Edge Functions
# =====================================================================
#  Adaptador [SUPABASE] del .env único: mapea los valores canónicos del
#  .env a los nombres que esperan las Edge Functions y los sube con la CLI
#  de Supabase. La nube NO lee tu .env local.
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

supabase secrets set \
  ${SUPABASE_PROJECT_REF:+--project-ref "${SUPABASE_PROJECT_REF}"} \
  "MINIO_ENDPOINT=${MEDIA_PUBLIC_URL}" \
  "MINIO_BUCKET=${MEDIA_BUCKET}" \
  "MINIO_ACCESS_KEY=${MINIO_ROOT_USER}" \
  "MINIO_SECRET_KEY=${MINIO_ROOT_PASSWORD}" \
  "MINIO_REGION=${MINIO_REGION}" \
  ${CRON_SECRET:+"CRON_SECRET=${CRON_SECRET}"}

echo "OK  secrets subidos."
