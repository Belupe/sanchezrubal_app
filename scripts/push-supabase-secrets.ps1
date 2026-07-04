# =====================================================================
#  push-supabase-secrets.ps1  —  Sube los secrets de las Edge Functions
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
#  Uso:  ./scripts/push-supabase-secrets.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$envFile = Join-Path $root '.env'
if (-not (Test-Path $envFile)) { throw "No existe .env (cp .env.example .env y rellénalo)." }

function Read-DotEnv($path) {
  $h = @{}
  foreach ($line in Get-Content $path) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    $k = $t.Substring(0, $i).Trim()
    $v = $t.Substring($i + 1)
    $v = ($v -replace '\s+#.*$', '').Trim().Trim('"').Trim("'")
    $h[$k] = $v
  }
  return $h
}

$e = Read-DotEnv $envFile

# Autenticación/destino para la CLI desde el .env (opcionales).
if ($e['SUPABASE_ACCESS_TOKEN']) { $env:SUPABASE_ACCESS_TOKEN = $e['SUPABASE_ACCESS_TOKEN'] }
$proj = if ($e['SUPABASE_PROJECT_REF']) { @('--project-ref', $e['SUPABASE_PROJECT_REF']) } else { @() }

# Mapeo .env canónico  ->  nombre del secret en Supabase
$secrets = @(
  "MINIO_ENDPOINT=$($e['MEDIA_PUBLIC_URL'])",
  "MINIO_BUCKET=$($e['MEDIA_BUCKET'])",
  "MEDIA_SIGN_ACCESS_KEY=$($e['MEDIA_SIGN_ACCESS_KEY'])",
  "MEDIA_SIGN_SECRET_KEY=$($e['MEDIA_SIGN_SECRET_KEY'])",
  "MINIO_REGION=$($e['MINIO_REGION'])"
)
if ($e['CRON_SECRET']) { $secrets += "CRON_SECRET=$($e['CRON_SECRET'])" }

# FCM (push): el secret es el CONTENIDO del JSON de la service account (multilínea),
# referenciado por ruta en FCM_SERVICE_ACCOUNT_FILE. Solo si existe el fichero.
$fcmFile = $e['FCM_SERVICE_ACCOUNT_FILE']
if ($fcmFile -and (Test-Path $fcmFile)) {
  $fcmJson = Get-Content -Raw -Path $fcmFile
  $secrets += "FCM_SERVICE_ACCOUNT=$fcmJson"
}

Write-Host "==> supabase secrets set (media-sign + send-email + notify-waitlist + send-push)" -ForegroundColor Cyan
& supabase secrets set @proj @secrets
if ($LASTEXITCODE -ne 0) { throw "supabase secrets set falló ($LASTEXITCODE)" }
Write-Host "OK  secrets subidos." -ForegroundColor Green
