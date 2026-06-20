# =====================================================================
#  release.ps1  —  Compila y publica una versión nueva (un solo comando)
# =====================================================================
#  Compila Android (+ Windows si hay toolchain), deja los artefactos en
#  dist/ y, si UPDATES_DATA_DIR es una ruta local accesible, los publica
#  automáticamente para que las apps se auto-actualicen.
#
#  Uso:
#    ./scripts/release.ps1            # compila la versión actual de pubspec
#    ./scripts/release.ps1 -Bump      # sube el build number (+1) y compila
#    ./scripts/release.ps1 -SkipWindows
# =====================================================================
param([switch]$Bump, [switch]$SkipAndroid, [switch]$SkipWindows)
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

if ($Bump) {
  $pub = Join-Path $app 'pubspec.yaml'
  $newLines = Get-Content $pub | ForEach-Object {
    if ($_ -match '^(\s*version:\s*[0-9.]+)\+([0-9]+)\s*$') { "$($Matches[1])+$([int]$Matches[2] + 1)" } else { $_ }
  }
  Set-Content $pub $newLines -Encoding UTF8
  $v = (Get-Content $pub | Where-Object { $_ -match '^\s*version:' } | Select-Object -First 1)
  Write-Host "Versión: $($v.Trim())  (build number +1)" -ForegroundColor Cyan
}

if (-not $SkipAndroid) { & (Join-Path $scripts 'build-android.ps1') }
if (-not $SkipWindows) {
  & (Join-Path $scripts 'build-windows.ps1')
  if ($LASTEXITCODE -eq 2) { Write-Warning "Windows: instalador no generado (falta Inno Setup o Visual Studio)." }
}

# Publicar: si UPDATES_DATA_DIR existe localmente, copia dist/* allí.
$dataDir = $envv['UPDATES_DATA_DIR']
$dist = Join-Path $root 'dist'
if ($dataDir -and (Test-Path $dataDir)) {
  foreach ($plat in 'android','windows') {
    $src = Join-Path $dist $plat
    if (Test-Path $src) {
      $dst = Join-Path $dataDir $plat
      New-Item -ItemType Directory -Force -Path $dst | Out-Null
      Copy-Item "$src\*" $dst -Recurse -Force
    }
  }
  if (-not (Test-Path (Join-Path $dataDir 'index.html'))) {
    Copy-Item (Join-Path $root 'server\updates\index.html') $dataDir -Force
  }
  Write-Host "`nPublicado en UPDATES_DATA_DIR: $dataDir  →  las apps se actualizarán solas." -ForegroundColor Green
} else {
  Write-Host "`nSiguiente paso: sube el contenido de '$dist' (android/, windows/, e index.html la 1ª vez)" -ForegroundColor Yellow
  Write-Host "a la carpeta UPDATES_DATA_DIR de tu servidor Docker." -ForegroundColor Yellow
}
