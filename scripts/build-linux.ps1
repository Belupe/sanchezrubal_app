# =====================================================================
#  build-linux.ps1  —  Compila la app de Linux dentro de Docker
# =====================================================================
#  Flutter NO compila Linux en cruzado desde Windows, así que la app de
#  escritorio de Linux se compila en un contenedor Ubuntu 22.04 (glibc
#  antigua a propósito: ver scripts/linux-build.Dockerfile).
#
#  Requisito: Docker, que este repo ya usa para el servidor. No hace falta
#  instalar nada más en el PC ni tener una máquina con Linux.
#
#  Salida: dist/linux/  (AppImage + .deb + .tar.gz + version.json)
#
#  Uso:
#    ./scripts/build-linux.ps1
#    ./scripts/build-linux.ps1 -Rebuild    # reconstruye la imagen sin caché
# =====================================================================
param([switch]$Rebuild)
$ErrorActionPreference = 'Stop'
$scripts = $PSScriptRoot
$root    = Split-Path $scripts -Parent
$image   = 'portal-familia/linux-build:3.44.6'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Warning "Docker no está disponible. Instala Docker Desktop (es el mismo que usa el servidor: docker compose up -d)."
  exit 2
}

Write-Host "==> docker build (imagen de compilación de Linux)" -ForegroundColor Cyan
$buildArgs = @('build', '-f', (Join-Path $scripts 'linux-build.Dockerfile'), '-t', $image)
if ($Rebuild) { $buildArgs += '--no-cache' }
$buildArgs += $scripts
& docker @buildArgs
if ($LASTEXITCODE -ne 0) { throw "docker build falló ($LASTEXITCODE)" }

# El repo se monta en /src. OJO si va lento o falla al crear los enlaces
# simbólicos de flutter/ephemeral/.plugin_symlinks: es cosa del montaje de
# NTFS en Docker Desktop. Solución: mueve el repo dentro de WSL2 (ext4) y
# ejecuta desde ahí ./scripts/build-linux.sh directamente.
Write-Host "==> build-linux.sh dentro del contenedor" -ForegroundColor Cyan
& docker run --rm -v "${root}:/src" -w /src $image bash /src/scripts/build-linux.sh
if ($LASTEXITCODE -ne 0) { throw "build-linux.sh falló ($LASTEXITCODE)" }

Write-Host "OK  Linux  ->  $root\dist\linux" -ForegroundColor Green
