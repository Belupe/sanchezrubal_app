# =====================================================================
#  build-android.ps1  —  Compila el APK release y lo deja en dist/android
# =====================================================================
#  Adaptador [APP] del .env único: hornea SOLO los valores PÚBLICOS con
#  --dart-define. No copia al servidor (eso lo hace release.ps1).
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

$defines = @()
foreach ($k in 'SUPABASE_URL','SUPABASE_ANON_KEY','MEDIA_PUBLIC_URL','UPDATES_PUBLIC_URL') {
  if ($envv[$k]) { $defines += "--dart-define=$k=$($envv[$k])" }
}

Write-Host "==> flutter build apk --release (Android)" -ForegroundColor Cyan
Push-Location $app
try { & flutter build apk --release @defines; if ($LASTEXITCODE -ne 0) { throw "build apk falló ($LASTEXITCODE)" } }
finally { Pop-Location }

$apkSrc = Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $apkSrc)) { throw "No se encontró el APK en $apkSrc" }

$verLine = (Get-Content (Join-Path $app 'pubspec.yaml') | Where-Object { $_ -match '^\s*version:' } | Select-Object -First 1)
$verName = '1.0.0'; $verCode = 1
if ($verLine -match 'version:\s*([0-9.]+)\+([0-9]+)') { $verName = $Matches[1]; $verCode = [int]$Matches[2] }
$base = if ($envv['UPDATES_PUBLIC_URL']) { $envv['UPDATES_PUBLIC_URL'] } else { 'https://app.sanchezrubal.net' }

$out = Join-Path $root 'dist\android'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Copy-Item $apkSrc (Join-Path $out 'portal-familia.apk') -Force
([ordered]@{ versionCode = $verCode; versionName = $verName; url = "$base/android/portal-familia.apk"; mandatory = $false; notes = "Versión $verName" } | ConvertTo-Json) |
  Set-Content (Join-Path $out 'version.json') -Encoding UTF8
@"
Portal Familia — instalación en Android
1) Abre $base en el móvil.
2) Descarga e instala 'portal-familia.apk' (permite "orígenes desconocidos" una vez).
3) Las siguientes versiones se actualizan solas desde dentro de la app.
"@ | Set-Content (Join-Path $out 'instalar-android.txt') -Encoding UTF8

Write-Host "OK  Android $verName (build $verCode)  ->  $out" -ForegroundColor Green
