# =====================================================================
#  release.ps1  —  Compila y publica una versión nueva (un solo comando)
# =====================================================================
#  Compila el instalador de Windows y los paquetes de Linux, deja los
#  artefactos en dist/ y, si UPDATES_DATA_DIR es una ruta local accesible, los
#  publica y regenera la página de descargas (con los enlaces del .env).
#
#  Android va por Google Play (scripts/build-aab.ps1) e iOS por App Store: no
#  se compilan aquí. Windows y el AppImage de Linux se auto-actualizan.
#
#  Linux se compila dentro de Docker (Flutter no compila Linux en cruzado
#  desde Windows): lo hace scripts/build-linux.ps1, que solo necesita el
#  Docker que ya usas para el servidor.
#
#  Uso:
#    ./scripts/release.ps1            # compila la versión actual de pubspec
#    ./scripts/release.ps1 -Bump      # sube el build number (+1) y compila
#    ./scripts/release.ps1 -SkipWindows
#    ./scripts/release.ps1 -SkipLinux
# =====================================================================
param([switch]$Bump, [switch]$SkipWindows, [switch]$SkipLinux)
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

if (-not $SkipWindows) {
  & (Join-Path $scripts 'build-windows.ps1')
  if ($LASTEXITCODE -eq 2) { Write-Warning "Windows: instalador no generado (falta Inno Setup o Visual Studio)." }
}

if (-not $SkipLinux) {
  & (Join-Path $scripts 'build-linux.ps1')
  if ($LASTEXITCODE -eq 2) { Write-Warning "Linux: paquetes no generados (falta Docker)." }
}

# [C-02] Calcula el SHA-256 de CADA artefacto y lo escribe en el version.json de
# su plataforma. La app rechaza cualquier paquete cuyo hash no coincida con este
# valor, así que un version.json manipulado no puede forzar la ejecución (ni la
# instalación como root, en el canal de sistema de Linux) de un binario ajeno.
$distDir = Join-Path $root 'dist'
$artefactos = @(
  @{ Plat = 'windows'; File = 'portal-familia-setup.exe';        Campo = 'sha256' },
  @{ Plat = 'linux';   File = 'portal-familia-x86_64.AppImage';  Campo = 'sha256' },
  @{ Plat = 'linux';   File = 'portal-familia_amd64.deb';        Campo = 'sha256Deb' }
)
foreach ($a in $artefactos) {
  $bin = Join-Path $distDir "$($a.Plat)\$($a.File)"
  $vjPath = Join-Path $distDir "$($a.Plat)\version.json"
  if (-not (Test-Path $bin)) { continue }
  $sha = (Get-FileHash -Algorithm SHA256 -Path $bin).Hash.ToLower()
  if (Test-Path $vjPath) {
    $vj = Get-Content $vjPath -Raw | ConvertFrom-Json
    $vj | Add-Member -NotePropertyName $a.Campo -NotePropertyValue $sha -Force
    ($vj | ConvertTo-Json -Depth 8) | Set-Content $vjPath -Encoding UTF8
    Write-Host "SHA-256 de $($a.File) -> $($a.Plat)/version.json ($($a.Campo))" -ForegroundColor Cyan
  } else {
    Write-Warning "No hay dist/$($a.Plat)/version.json; SHA-256 de $($a.File): $sha (anadelo como campo '$($a.Campo)')."
  }
}

# Publicar: si UPDATES_DATA_DIR existe localmente, copia dist/* allí.
$dataDir = $envv['UPDATES_DATA_DIR']
$dist = Join-Path $root 'dist'
if ($dataDir -and (Test-Path $dataDir)) {
  foreach ($plat in @('windows', 'linux')) {
    $src = Join-Path $dist $plat
    if (Test-Path $src) {
      $dst = Join-Path $dataDir $plat
      New-Item -ItemType Directory -Force -Path $dst | Out-Null
      Copy-Item "$src\*" $dst -Recurse -Force
    }
  }
  # index.html: se regenera SIEMPRE desde la plantilla, horneando los enlaces de
  # descarga del .env (así cambiarlos por seguridad es editar .env y republicar).
  $windowsUrl     = if ($envv['DOWNLOAD_WINDOWS_URL'])      { $envv['DOWNLOAD_WINDOWS_URL'] }      else { './windows/portal-familia-setup.exe' }
  $iosUrl         = if ($envv['DOWNLOAD_IOS_URL'])          { $envv['DOWNLOAD_IOS_URL'] }          else { '' }
  $androidPlayUrl = if ($envv['DOWNLOAD_ANDROID_PLAY_URL']) { $envv['DOWNLOAD_ANDROID_PLAY_URL'] } else { '' }
  $linuxAppImgUrl = if ($envv['DOWNLOAD_LINUX_APPIMAGE_URL']) { $envv['DOWNLOAD_LINUX_APPIMAGE_URL'] } else { './linux/portal-familia-x86_64.AppImage' }
  $linuxDebUrl    = if ($envv['DOWNLOAD_LINUX_DEB_URL'])      { $envv['DOWNLOAD_LINUX_DEB_URL'] }      else { './linux/portal-familia_amd64.deb' }
  $tpl = Get-Content (Join-Path $root 'server\updates\index.html') -Raw
  # Android: SOLO Google Play (por invitación). Si hay enlace, se muestra el botón;
  # si no, se oculta (igual que iOS). Ya no se ofrece APK de descarga directa.
  if ($androidPlayUrl) {
    $tpl = $tpl -replace '<!--ANDROID_PLAY:START-->', '' -replace '<!--ANDROID_PLAY:END-->', ''
  } else {
    $tpl = [regex]::Replace($tpl, '(?s)\s*<!--ANDROID_PLAY:START-->.*?<!--ANDROID_PLAY:END-->', '')
  }
  if ($iosUrl) {
    # Hay enlace de App Store: deja el bloque iOS, solo quita los marcadores.
    $tpl = $tpl -replace '<!--IOS:START-->', '' -replace '<!--IOS:END-->', ''
  } else {
    # Sin enlace: elimina por completo cada bloque entre marcadores (botón + ayuda).
    $tpl = [regex]::Replace($tpl, '(?s)\s*<!--IOS:START-->.*?<!--IOS:END-->', '')
  }
  # [2I-02] Escapa los valores del .env antes de hornearlos en atributos href
  # (un valor con comillas o < > no puede romper el HTML de la página pública).
  function Html-Attr([string]$v) {
    if ([string]::IsNullOrEmpty($v)) { return $v }
    return $v.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
  }
  $tpl = $tpl.Replace('{{DOWNLOAD_ANDROID_PLAY_URL}}', (Html-Attr $androidPlayUrl)).
              Replace('{{DOWNLOAD_WINDOWS_URL}}', (Html-Attr $windowsUrl)).
              Replace('{{DOWNLOAD_LINUX_APPIMAGE_URL}}', (Html-Attr $linuxAppImgUrl)).
              Replace('{{DOWNLOAD_LINUX_DEB_URL}}', (Html-Attr $linuxDebUrl)).
              Replace('{{DOWNLOAD_IOS_URL}}', (Html-Attr $iosUrl))
  Set-Content (Join-Path $dataDir 'index.html') $tpl -Encoding UTF8
  Write-Host "`nPublicado en UPDATES_DATA_DIR: $dataDir  →  las apps se actualizarán solas." -ForegroundColor Green
} else {
  Write-Host "`nSiguiente paso: sube el contenido de '$dist' (windows/ e index.html la 1ª vez)" -ForegroundColor Yellow
  Write-Host "a la carpeta UPDATES_DATA_DIR de tu servidor Docker." -ForegroundColor Yellow
}
