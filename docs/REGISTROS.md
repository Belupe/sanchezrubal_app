# Registros de fallos — dónde están y cómo enviarlos

Si la app se cierra sola, se queda en blanco o da un error raro, deja un **informe técnico** con
lo que estaba pasando: fecha y hora, versión, sistema operativo y el detalle del error. Sirve
para poder arreglarlo sin tener que adivinar.

> **No contiene tu contraseña ni tu sesión.** Antes de escribir nada, se limpian los datos
> sensibles (ver "Qué NO se guarda"). Puedes enviarlo con tranquilidad.

---

## Para la familia: cómo enviarlo

Solo hace falta si te lo piden.

### En el ordenador (Windows, Mac o Linux)

1. Abre la app → **Configuración**.
2. Abajo del todo, en **Diagnóstico**, pulsa **Abrir carpeta de registros**.
3. Se abre una carpeta llamada `Logs`. Envía el fichero **`ultimo-fallo.log`**.

Si no se abre la carpeta, ahí mismo aparece la ruta completa y se copia al portapapeles al
pulsar el botón, para que la pegues en el explorador de archivos.

Si dice **"No hay ningún fallo registrado"**, es que no ha habido ninguno: no hay nada que enviar.

### En el móvil (Android o iPhone)

1. Abre la app → **Configuración**.
2. En **Diagnóstico**, pulsa **Enviar informe del último fallo**.
3. Se abre el menú de compartir de siempre: elige correo, WhatsApp o lo que uses.

---

## Cómo funciona (técnico)

La carpeta `Logs` vive dentro del directorio de datos de la app:

| Sistema | Ruta |
|---|---|
| Windows | `%APPDATA%\net.sanchezrubal\portal_familia\Logs` |
| macOS | `~/Library/Application Support/net.sanchezrubal.portal_familia/Logs` |
| Linux | `~/.local/share/net.sanchezrubal.portal_familia/Logs` |
| Android / iOS | Dentro del sandbox de la app (se accede con el botón de compartir) |

Como esas rutas no son fáciles de encontrar, la pantalla de Configuración las muestra y las abre.

### Los tres ficheros, y nunca más de tres

| Fichero | Qué es |
|---|---|
| `sesion.log` | La sesión que está abierta ahora mismo |
| `sesion.activa` | Marca de "hay una sesión abierta" |
| `ultimo-fallo.log` | El último fallo. **Solo se guarda uno** |

### La regla de borrado

El marcador `sesion.activa` es lo que distingue un cierre normal de un fallo:

- **Cierras tú la app** → se borran el marcador y el registro de la sesión. No queda nada.
- **La app muere** (se cierra sola, error, corte de luz, el sistema la mata) → el marcador
  sobrevive. Al volver a abrirla se detecta y ese registro se guarda como `ultimo-fallo.log`.
- **Cada fallo nuevo sustituye al anterior**, así que nunca hay más de un informe guardado y la
  carpeta no crece.

El informe se conserva hasta que ocurra otro fallo, así que sigue ahí aunque vuelvas a usar la
app con normalidad durante días.

### Qué se guarda

Al arrancar, una cabecera con la fecha y hora (con zona horaria), la versión y número de
compilación, el sistema operativo y su versión, el idioma, la ruta del ejecutable y —en Linux—
si es un AppImage. Después, cada aviso o error con su marca de tiempo y su traza completa.

El fichero de sesión tiene un tope de 1 MB; si se pasa, se recorta por el principio (interesa lo
último, que es lo que precede al fallo).

### Qué NO se guarda

Antes de escribir, se sustituyen:

- los **tokens de sesión** (JWT) y los `refresh_token`;
- las **claves de Supabase** y las cabeceras `Authorization` / `apikey`;
- las **firmas de las URLs de fotos y vídeos** de MinIO (las excepciones de red incluyen la URL
  entera, firma incluida);
- las **direcciones de correo**, de las que se deja solo el dominio.

Está cubierto por pruebas automáticas (`app_flutter/test/log_service_test.dart`) porque es lo
único de este sistema que, si se rompe, filtra credenciales.

### Un límite honesto

Un fallo **nativo** (un cierre abrupto del propio motor gráfico, o que el sistema mate la app por
falta de memoria) no puede dejar traza: el proceso muere sin llegar a ejecutar nada. Aun así
**queda detectado**, porque el marcador sobrevive y se conserva el registro con lo último que se
estaba haciendo antes de morir, que suele bastar para situar el problema.

---

## Además, y sin hacer nada: los informes de las tiendas

Para las versiones de **Android** e **iPhone** publicadas en las tiendas, los fallos nativos ya
llegan por su cuenta, sin código ni configuración:

- **Android** → Google Play Console → **Calidad de la app → Android vitals → Fallos y ANR**.
- **iPhone/iPad** → App Store Connect, o en un Mac: **Xcode → Window → Organizer → Crashes**.

Llegan agrupados y con la traza simbolizada, pero **solo de usuarios que hayan aceptado compartir
diagnósticos** y con retraso de horas. El informe de la app es inmediato y no depende de eso, por
eso existen los dos.
