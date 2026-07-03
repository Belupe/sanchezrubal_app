# =====================================================================
#  build-aab.ps1  —  Compila el App Bundle (.aab) para SUBIR A GOOGLE PLAY
# =====================================================================
#  Es el ÚNICO build de Android (el APK self-hosted quedó retirado):
#    · genera un .aab (formato que exige Google Play),
#    · DESACTIVA el auto-updater interno (ENABLE_SELF_UPDATE=false) porque
#      Play prohíbe que la app se actualice bajando APKs y ya actualiza ella,
#    · hornea SOLO valores PÚBLICOS con --dart-define.
#  El .aab se sube A MANO en Play Console (no hay automatización). Ver
#  docs/GOOGLE.md para el paso a paso.
# =====================================================================
$ErrorActionPreference = 'Stop'
$scripts = $PSScriptRoot
$root    = Split-Path $scripts -Parent
$app     = Join-Path $root 'app_flutter'
$envFile = Join-Path $root '.env'

function Read-DotEnv($path) {
  $h = @{}
  if (-not (Test-Path $path)) { return $h }
  foreach ($line in Get-Content $path) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $i = $t.IndexOf('='); if ($i -lt 1) { continue }
    $k = $t.Substring(0, $i).Trim()
    $v = ($t.Substring($i + 1) -replace '\s+#.*$', '').Trim().Trim('"').Trim("'")
    $h[$k] = $v
  }
  return $h
}

$envv = Read-DotEnv $envFile
if (-not (Test-Path $envFile)) { Write-Warning "No existe .env; uso los defaults de lib/config.dart." }

# Firma: Play exige un keystore real (la clave de subida). build.gradle.kts usa
# android/key.properties si existe; si no, cae a la firma DEBUG, que Play RECHAZA.
if (-not (Test-Path (Join-Path $app 'android\key.properties'))) {
  Write-Warning "Falta app_flutter/android/key.properties: el .aab se firmaría en DEBUG y Play lo rechazará."
  Write-Warning "Crea el keystore de subida y key.properties antes de publicar (ver docs/GOOGLE.md)."
}

# Valores PÚBLICOS + auto-update DESACTIVADO para la build de Play.
$defines = @('--dart-define=ENABLE_SELF_UPDATE=false')
foreach ($k in 'SUPABASE_URL','SUPABASE_ANON_KEY','MEDIA_PUBLIC_URL') {
  if ($envv[$k]) { $defines += "--dart-define=$k=$($envv[$k])" }
}

Write-Host "==> flutter build appbundle --release (Google Play, self-update OFF)" -ForegroundColor Cyan
Push-Location $app
try { & flutter build appbundle --release @defines; if ($LASTEXITCODE -ne 0) { throw "build appbundle falló ($LASTEXITCODE)" } }
finally { Pop-Location }

$aabSrc = Join-Path $app 'build\app\outputs\bundle\release\app-release.aab'
if (-not (Test-Path $aabSrc)) { throw "No se encontró el .aab en $aabSrc" }

$verLine = (Get-Content (Join-Path $app 'pubspec.yaml') | Where-Object { $_ -match '^\s*version:' } | Select-Object -First 1)
$verName = '1.0.0'; $verCode = 1
if ($verLine -match 'version:\s*([0-9.]+)\+([0-9]+)') { $verName = $Matches[1]; $verCode = [int]$Matches[2] }

$out = Join-Path $root 'dist\googleplay'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$aabDst = Join-Path $out "portal-familia-$verName-$verCode.aab"
Copy-Item $aabSrc $aabDst -Force

Write-Host "`nOK  App Bundle $verName (build $verCode)" -ForegroundColor Green
Write-Host "    -> $aabDst" -ForegroundColor Green
Write-Host "`nSiguiente paso: súbelo a mano en Play Console (pista de prueba interna o cerrada)." -ForegroundColor Yellow
Write-Host "Guía: docs/GOOGLE.md" -ForegroundColor Yellow
