; =====================================================================
;  windows-installer.iss  —  Instalador de Portal Familia (Inno Setup)
; =====================================================================
;  Lo invoca scripts/build-windows.ps1 con:
;    ISCC /DAppVersion=x.y.z /DSourceDir=<...Release> /DOutputDir=<...dist\windows>
;  Instala sin admin en %LOCALAPPDATA%\Portal Familia y permite reinstalar
;  encima (eso es la auto-actualización). App sin firma → SmartScreen puede
;  avisar; "Más información → Ejecutar de todas formas".
; =====================================================================

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\app_flutter\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist\windows"
#endif
#define MyAppName "Portal Familia"
#define MyAppExeName "portal_familia.exe"

[Setup]
AppId={{A3F1B2C4-5D6E-4789-A0B1-C2D3E4F5A6B7}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher=Sanchez Rubal
; El usuario puede CAMBIAR la carpeta en el asistente (página de destino).
DefaultDirName={autopf}\Portal Familia
DisableDirPage=no
UsePreviousAppDir=yes
DisableProgramGroupPage=yes
; Permite elegir "para todos los usuarios" (admin → Archivos de programa) o
; "solo para mí" (sin admin → tu perfil). Por defecto, sin admin.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutputDir}
OutputBaseFilename=portal-familia-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Cierra la app si está abierta (clave para actualizar sin archivos bloqueados).
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}";  Filename: "{app}\{#MyAppExeName}"

[Registry]
; Esquema portalfamilia:// para abrir la app desde los enlaces de los correos.
Root: HKCU; Subkey: "Software\Classes\portalfamilia"; ValueType: string; ValueName: ""; ValueData: "URL:Portal Familia"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\portalfamilia"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\portalfamilia\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCU; Subkey: "Software\Classes\portalfamilia\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir Portal Familia"; Flags: nowait postinstall skipifsilent
