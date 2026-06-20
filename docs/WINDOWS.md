# Windows — instalador `.exe` + auto-update

App de escritorio Flutter, **sin firma de código** (no requiere el certificado de pago).
Se distribuye como un **instalador `.exe`** (Inno Setup) alojado en tu Docker, con
auto-actualización igual que Android.

## Requisitos (en tu PC)
- **Visual Studio** (Community o **Build Tools**) con el workload **"Desktop development with C++"**.
  ⚠️ VS Code **no** sirve para compilar; es un editor distinto.
- **Inno Setup** (gratis): https://jrsoftware.org/isdl.php — aporta `ISCC.exe` (lo localiza el script).

## Compilar y publicar
```powershell
./scripts/release.ps1 -Bump        # Android + Windows; o solo Windows:
./scripts/build-windows.ps1
```
Hace `flutter build windows --release` y empaqueta el resultado con
[scripts/windows-installer.iss](../scripts/windows-installer.iss) en
`dist/windows/portal-familia-setup.exe` + `version.json`. `release.ps1` lo publica en
`UPDATES_DATA_DIR/windows/` (o cópialo tú al servidor).

## Cómo funciona el auto-update
- Al abrir, la app consulta `${UPDATES_PUBLIC_URL}/windows/version.json`.
- Si hay versión nueva, descarga el `setup.exe`, lo **lanza y cierra la app** para que el
  instalador reemplace los archivos y la relance (Inno Setup con `CloseApplications=yes`).
- El instalador es **por usuario** (`%LOCALAPPDATA%\Portal Familia`, sin admin/UAC).

## Aviso de SmartScreen
Como el `.exe` no está firmado, Windows SmartScreen puede avisar al instalar:
**Más información → Ejecutar de todas formas**. Es normal en apps sin certificado.

## Instalar (familia)
Abre `https://app.sanchezrubal.net`, pulsa **Windows — Descargar instalador** y ejecútalo.
Las siguientes versiones se actualizan solas desde la app.
