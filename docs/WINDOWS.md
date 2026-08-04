# Windows — instalador `.exe` + auto-update

App de escritorio Flutter, **sin firma de código** (no requiere el certificado de pago).
Se distribuye como un **instalador `.exe`** (Inno Setup) alojado en tu Docker, con
auto-actualización igual que Android.

---

## Compilar y publicar

Flutter **no compila Windows en cruzado**: el `.exe` no se puede generar desde macOS ni
desde Linux. Hace falta una máquina con Windows — sirve una **máquina virtual**.

### 1. Requisitos en esa máquina Windows

- **Visual Studio** (Community o Build Tools) con el workload **"Desktop development with C++"**.
  VS Code **no** sirve para compilar; es un editor distinto.
- **Inno Setup** (gratis): https://jrsoftware.org/isdl.php — aporta `ISCC.exe`.
- El repositorio clonado y un `.env` con al menos `SUPABASE_URL`, `SUPABASE_ANON_KEY` y
  `UPDATES_PUBLIC_URL` (son los únicos tres valores que se hornean en la app; ninguno es
  secreto).

### 2. Compilar

```powershell
./scripts/release.ps1 -Bump        # Windows + Linux; o solo Windows:
./scripts/build-windows.ps1
```

Deja en `dist/windows/`:

```
portal-familia-setup.exe
version.json
```

### 3. Subir al servidor por SFTP

Los dos ficheros van a la subcarpeta `windows/` de tu `UPDATES_DATA_DIR`:

```
/home/nach/sr/updates/windows/portal-familia-setup.exe
/home/nach/sr/updates/windows/version.json
```

Con cualquier cliente SFTP (FileZilla, Cyberduck, WinSCP) o por consola:

```bash
sftp nach@192.168.8.214
> cd /home/nach/sr/updates/windows
> put portal-familia-setup.exe
> put version.json
```

**Sube el `.exe` primero y el `version.json` después.** Si lo haces al revés, durante unos
segundos la app anunciará una versión cuyo instalador todavía no está completo, y la
descarga fallará a mitad.

Comprueba que los ficheros quedan legibles (`chmod 644` si tu cliente los sube con permisos
raros): nginx los sirve en modo solo lectura y no puede arreglar un permiso mal puesto.

No hay que reiniciar ningún contenedor: el servicio `updates` sirve la carpeta en vivo.

---

## Cómo funciona el auto-update

- Al abrir, la app consulta `${UPDATES_PUBLIC_URL}/windows/version.json`.
- Si hay versión nueva, descarga el `setup.exe`, lo **lanza y cierra la app** para que el
  instalador reemplace los archivos y la relance (Inno Setup con `CloseApplications=yes`).
- El instalador es **por usuario** (`%LOCALAPPDATA%\Portal Familia`, sin admin ni UAC).

---

# Instalar sin certificado — guía para la familia

> Esta parte está escrita para reenviársela a quien vaya a instalar la app.
> No hace falta saber nada técnico.

## Por qué Windows te va a avisar

Portal Familia **no está firmada con un certificado de código**. Esos certificados los
venden empresas por unos cientos de euros al año y sirven para que Microsoft sepa quién
publica el programa.

Como no lo tiene, Windows muestra un aviso al instalar. **El aviso no dice que la app sea
peligrosa**: dice que Windows no reconoce quién la ha hecho. Es exactamente lo mismo que
pasa con cualquier programa pequeño o casero.

## Paso 1 — Descargar

Abre **https://app.sanchezrubal.net** y pulsa **Windows — Descargar instalador**.
Se descarga `portal-familia-setup.exe`, normalmente a la carpeta **Descargas**.

Puede que el navegador ya te avise durante la descarga:

- **Microsoft Edge**: aparece "…no se descarga habitualmente" o similar. Pulsa los tres
  puntos `···` junto al aviso → **Conservar** → si pide confirmación, **Conservar de todos
  modos**.
- **Google Chrome**: aparece "…puede ser peligroso". Pulsa la flecha `˅` → **Conservar**.
- **Firefox**: pulsa la flecha `˅` en el aviso de la descarga → **Permitir la descarga**.

## Paso 2 — Ejecutar (aquí sale el aviso grande)

Haz doble clic en el archivo descargado. Verás una ventana azul:

```
        Windows protegió su PC

  Microsoft Defender SmartScreen impidió el
  inicio de una aplicación desconocida.

  Aplicación:  portal-familia-setup.exe
  Editor:      Desconocido

                              [ No ejecutar ]
```

**No pulses "No ejecutar".** Haz esto:

1. Pulsa **Más información** (el enlace pequeño, debajo del texto).
2. Aparece un botón nuevo: **Ejecutar de todas formas**.
3. Púlsalo.

Eso es todo. El instalador se abre con normalidad y solo hay que ir dando a **Siguiente**.

> Si no ves el enlace "Más información", es que la ventana está a medio cargar. Espera un
> segundo y vuelve a mirar: siempre está ahí.

## Paso 3 — Si no aparece "Más información"

Ocurre cuando Windows ha marcado el archivo como "venido de internet" y bloquea antes de
llegar a SmartScreen. Se quita así:

1. Clic **derecho** sobre `portal-familia-setup.exe` → **Propiedades**.
2. Abajo del todo de la pestaña **General**, marca la casilla **Desbloquear**.
3. **Aceptar**, y vuelve a hacer doble clic.

## Si el antivirus lo borra

Algunos antivirus borran los instaladores sin firma directamente. No es que hayan
detectado un virus: es que no reconocen al editor y aplican la regla más estricta.

Añade una excepción para el archivo, o desactiva la protección el minuto que dura la
instalación. Si tu antivirus **da un nombre de amenaza concreto** (no algo genérico como
"Unsigned" o "Heuristic"), no lo instales y avísame antes.

## No hace falta ser administrador

La app se instala **solo para tu usuario**, en `%LOCALAPPDATA%\Portal Familia`. Nunca pide
la contraseña de administrador ni toca el resto del ordenador. Si algo te pide permisos de
administrador durante la instalación, **cancela**: eso no es este instalador.

## Las siguientes veces no hay que hacer nada

Este proceso es **solo la primera vez**. A partir de ahí la app se actualiza sola: detecta
la versión nueva, la descarga y se reinicia. Sin avisos y sin volver a descargar nada a mano.

---

## Nota para el que publica: quitar el aviso del todo

La única forma de que SmartScreen no avise nunca es **firmar el instalador**:

| Tipo de certificado | Coste anual aproximado | Efecto |
|---|---|---|
| Ninguno (hoy) | 0 € | El aviso sale siempre |
| OV (validación de organización) | 200–400 € | El aviso desaparece **al cabo de un tiempo**, cuando el certificado acumula reputación |
| EV (validación extendida) | 300–600 € | Sin aviso desde el primer instalador |

Para una app familiar que se instala unas pocas veces, no compensa. El coste real es
explicar estos dos clics una vez a cada persona.
