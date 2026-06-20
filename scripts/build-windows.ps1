# =====================================================================
#  build-windows.ps1  —  Compila la app de escritorio y genera el instalador
# =====================================================================
#  Requisitos: Visual Studio con workload "Desktop development with C++"
#  e Inno Setup (ISCC.exe). Hornea SOLO los valores PÚBLICOS del .env.
#  Salida: dist/windows/portal-familia-setup.exe + version.json
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
$defines = @()
foreach ($k in 'SUPABASE_URL','SUPABASE_ANON_KEY','MEDIA_PUBLIC_URL','UPDATES_PUBLIC_URL') {
  if ($envv[$k]) { $defines += "--dart-define=$k=$($envv[$k])" }
}

Write-Host "==> flutter build windows --release" -ForegroundColor Cyan
Push-Location $app
try { & flutter build windows --release @defines; if ($LASTEXITCODE -ne 0) { throw "build windows falló ($LASTEXITCODE)" } }
finally { Pop-Location }

$rel = Join-Path $app 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $rel 'portal_familia.exe'))) { throw "No se encontró el build en $rel" }

$verLine = (Get-Content (Join-Path $app 'pubspec.yaml') | Where-Object { $_ -match '^\s*version:' } | Select-Object -First 1)
$verName = '1.0.0'; $verCode = 1
if ($verLine -match 'version:\s*([0-9.]+)\+([0-9]+)') { $verName = $Matches[1]; $verCode = [int]$Matches[2] }
$base = if ($envv['UPDATES_PUBLIC_URL']) { $envv['UPDATES_PUBLIC_URL'] } else { 'https://app.sanchezrubal.net' }

$out = Join-Path $root 'dist\windows'
New-Item -ItemType Directory -Force -Path $out | Out-Null

# Localizar el compilador de Inno Setup.
$iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
  $iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $iscc) {
  Write-Warning "Inno Setup (ISCC.exe) no encontrado. La app está compilada en:`n  $rel`nInstala Inno Setup y reejecuta para generar el setup.exe."
  exit 2
}

& $iscc "/DAppVersion=$verName" "/DSourceDir=$rel" "/DOutputDir=$out" (Join-Path $scripts 'windows-installer.iss')
if ($LASTEXITCODE -ne 0) { throw "ISCC falló ($LASTEXITCODE)" }

([ordered]@{ versionCode = $verCode; versionName = $verName; url = "$base/windows/portal-familia-setup.exe"; mandatory = $false; notes = "Versión $verName" } | ConvertTo-Json) |
  Set-Content (Join-Path $out 'version.json') -Encoding UTF8

Write-Host "OK  Windows $verName (build $verCode)  ->  $out\portal-familia-setup.exe" -ForegroundColor Green
