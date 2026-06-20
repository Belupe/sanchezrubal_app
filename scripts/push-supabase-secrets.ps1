# =====================================================================
#  push-supabase-secrets.ps1  —  Sube los secrets de las Edge Functions
# =====================================================================
#  Adaptador [SUPABASE] del .env único: mapea los valores canónicos del
#  .env a los nombres que esperan las Edge Functions (media-sign, send-email)
#  y los sube con la CLI de Supabase. La nube NO lee tu .env local.
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
  "MINIO_ACCESS_KEY=$($e['MINIO_ROOT_USER'])",
  "MINIO_SECRET_KEY=$($e['MINIO_ROOT_PASSWORD'])",
  "MINIO_REGION=$($e['MINIO_REGION'])"
)
if ($e['CRON_SECRET']) { $secrets += "CRON_SECRET=$($e['CRON_SECRET'])" }

Write-Host "==> supabase secrets set (media-sign + send-email)" -ForegroundColor Cyan
& supabase secrets set @proj @secrets
if ($LASTEXITCODE -ne 0) { throw "supabase secrets set falló ($LASTEXITCODE)" }
Write-Host "OK  secrets subidos." -ForegroundColor Green
