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

# --- Fichero temporal restringido con los secrets [B-07] ---
# NO se pasan por argv: los argumentos de un proceso son visibles con
# Get-CimInstance Win32_Process para otros usuarios. 'supabase secrets set
# --env-file' los lee de un fichero que solo el usuario actual puede leer.
$tmp = [System.IO.Path]::GetTempFileName()
# Rompe herencia y concede solo al usuario actual (equivalente a chmod 600)
icacls $tmp /inheritance:r /grant:r "$($env:USERNAME):(F)" | Out-Null
try {
  $lines = New-Object System.Collections.Generic.List[string]
  # comillas simples => valor literal en el dotenv (sin expansión). Asume que el valor no contiene '
  function Add-Secret([string]$k, [string]$v) { $lines.Add("$k='$v'") }

  Add-Secret 'MINIO_ENDPOINT'         $e['MEDIA_PUBLIC_URL']
  Add-Secret 'MINIO_BUCKET'           $e['MEDIA_BUCKET']
  Add-Secret 'MEDIA_SIGN_ACCESS_KEY'  $e['MEDIA_SIGN_ACCESS_KEY']
  Add-Secret 'MEDIA_SIGN_SECRET_KEY'  $e['MEDIA_SIGN_SECRET_KEY']
  Add-Secret 'MINIO_REGION'           $e['MINIO_REGION']
  $mmb = if ([string]::IsNullOrEmpty($e['MEDIA_MAX_UPLOAD_BYTES'])) { '104857600' } else { $e['MEDIA_MAX_UPLOAD_BYTES'] }
  Add-Secret 'MEDIA_MAX_UPLOAD_BYTES'  $mmb
  if ($e['CRON_SECRET']) { Add-Secret 'CRON_SECRET' $e['CRON_SECRET'] }
  if ($e['PUSH_SECRET']) { Add-Secret 'PUSH_SECRET' $e['PUSH_SECRET'] }   # [B-06] secreto dedicado de send-push

  # FCM (push): el secret es el CONTENIDO del JSON de la service account (multilínea),
  # referenciado por ruta en FCM_SERVICE_ACCOUNT_FILE. Solo si existe el fichero.
  $fcmFile = $e['FCM_SERVICE_ACCOUNT_FILE']
  if ($fcmFile -and (Test-Path $fcmFile)) {
    # JSON a UNA línea: quita CR/LF reales; conserva los \n literales de private_key
    $fcmJson = (Get-Content -Raw -Path $fcmFile) -replace '\r?\n', ''
    if ($fcmJson.Contains("'")) { throw "FCM JSON contiene comilla simple; no soportado." }
    Add-Secret 'FCM_SERVICE_ACCOUNT' $fcmJson
  }

  # UTF-8 SIN BOM (el BOM rompe el parseo del dotenv)
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($tmp, (($lines -join "`n") + "`n"), $utf8NoBom)

  Write-Host "==> supabase secrets set (media-sign + send-email + notify-waitlist + send-push)" -ForegroundColor Cyan
  & supabase secrets set @proj --env-file $tmp
  if ($LASTEXITCODE -ne 0) { throw "supabase secrets set falló ($LASTEXITCODE)" }
  Write-Host "OK  secrets subidos." -ForegroundColor Green
}
finally {
  Remove-Item -Force -ErrorAction SilentlyContinue $tmp
}
