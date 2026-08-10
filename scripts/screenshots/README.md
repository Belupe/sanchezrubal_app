# Capturas para la App Store

Genera las capturas de pantalla que pide **App Store Connect**, emulando un
**iPhone** y un **iPad**, sin necesidad de un Mac ni del simulador de Xcode.

```bash
./scripts/screenshots/run.sh
```

Las deja en **`docs/capturas/`**:

| Carpeta | Dispositivo | Resolución | Obligatoria en App Store Connect |
|---|---|---|---|
| `iphone-6.9/` | iPhone 6,9" (16/15 Pro Max) | **1290 × 2796** | sí |
| `ipad-13/` | iPad Pro 13" | **2048 × 2732** | sí, porque la app también se publica para iPad |

Apple acepta hasta 10 capturas por tamaño; aquí se generan 9. Esos dos tamaños
son los únicos que hay que subir: **App Store Connect reescala** el resto de
modelos a partir de ellos.

## Qué se está fotografiando exactamente

**La app de verdad.** Se compila `app_flutter/` tal cual —las mismas pantallas,
los mismos widgets, las mismas consultas— y se ejecuta en Chromium. No hay
maquetas ni pantallazos dibujados a mano: lo que sale en el PNG es lo que
renderiza Flutter.

Cambian solo dos cosas, y ninguna toca `app_flutter/`:

1. **El servidor.** En vez de Supabase, la app habla con `mock_backend.mjs`, que
   devuelve datos de una familia inventada. Así no se publica en la App Store ni
   un nombre ni una reserva reales, y las capturas salen idénticas cada vez.
2. **Cuatro servicios de plataforma** (`overlay/`) que usan `dart:io` y no
   compilan para navegador: registro de fallos, auto-actualización, integración
   con el escritorio de Linux y push. Se sustituyen por dobles inertes con la
   misma API pública. Ninguno pinta nada en pantalla.

## Cómo se emula el dispositivo

- **Resolución**: viewport en puntos × `deviceScaleFactor` (430×932 ×3 en el
  iPhone; 1024×1366 ×2 en el iPad) = exactamente los píxeles que pide Apple.
- **Sistema**: el navegador se presenta con el *user agent* y el
  `navigator.platform` de iOS, así que `defaultTargetPlatform` vale
  `TargetPlatform.iOS` y la app se comporta como en el dispositivo (transiciones,
  física del scroll, `Theme.of(context).platform`).
- **Zonas seguras**: `main_shots.dart` inyecta por `MediaQuery` el recorte de la
  isla dinámica (59 pt) y el del indicador de inicio (34 pt), de modo que la
  AppBar pinta su fondo bajo la barra de estado igual que en el móvil.
- **Barra de estado**: se dibuja encima (hora 9:41, cobertura, wifi, batería),
  como en las capturas del simulador de Xcode. Es decoración del dispositivo,
  no interfaz de la app; se quita con `?statusbar=0`.
- **Navegación**: Playwright pulsa sobre el **árbol de semántica** que Flutter
  publica en el DOM (`flt-semantics[aria-label]`), no sobre coordenadas fijas.
  Si mañana cambia el diseño, el guion sigue encontrando los botones.

## Requisitos

- **Flutter** en el `PATH` (la versión que pide `pubspec.yaml`).
- **Node.js** y **Playwright**: `npm i -g playwright`.
- **Python 3** (solo para insertar el bloque de fuentes en el pubspec temporal).

La primera ejecución necesita internet un momento para bajar los tipos de letra
de respaldo (los caracteres que Roboto no trae: la flecha `→` de los rangos de
fechas y el `⭐` de las valoraciones). Se quedan en caché y a partir de ahí el
proceso funciona sin red.

## Opciones

```bash
./scripts/screenshots/run.sh --dispositivo=iphone    # solo iPhone
./scripts/screenshots/run.sh --dispositivo=ipad      # solo iPad
./scripts/screenshots/run.sh --salida=/tmp/capturas  # otra carpeta
./scripts/screenshots/run.sh --puerto=9000           # si el 8787 está ocupado
```

## Cambiar lo que se ve

- **Los datos** (casas, familias, reservas, anuncios, sorteos, inspecciones):
  `mock_backend.mjs`. Las fechas se generan **relativas a hoy**, así que las
  capturas nunca salen caducadas.
- **Qué pantallas se fotografían y en qué orden**: la constante `GUION` de
  `capture.mjs`. Cada escena dice cómo llegar (`ir`), cómo saber que ya ha
  llegado (`esperarTitulo` / `esperar`) y si hay que desplazar (`desplazarHasta`).
- **Los dispositivos**: la constante `DISPOSITIVOS` de `capture.mjs`. Para el
  otro tamaño que acepta Apple en el iPhone (1320 × 2868) basta con poner
  `ancho: 440, alto: 956`.

## Ficheros

```
run.sh              orquesta todo (copia → capa de sustitución → compila → sirve → captura)
mock_backend.mjs    Supabase simulado + servidor de la app + espejo de fuentes
capture.mjs         guion de captura con Playwright (emulación de iPhone/iPad)
fuentes.py          declara Roboto en el pubspec de la copia temporal
overlay/            lo que se superpone a app_flutter SOLO para esta compilación
  main_shots.dart              punto de entrada (marco del dispositivo + inicio de sesión)
  flutter_bootstrap.js         redirige los tipos de respaldo al servidor local
  log_service.dart             \
  update_service.dart           |  dobles inertes de los servicios que
  linux_desktop_integration.dart|  no compilan para navegador
  push_service.dart            /
```

## Después de generarlas

En **App Store Connect** → tu app → la versión → *Vista previa de la App Store y
capturas de pantalla*: se sube la carpeta `iphone-6.9/` en el tamaño de 6,9" y
`ipad-13/` en el de 13". El orden de los ficheros (`01-…`, `02-…`) es el orden
en que se enseñan en la ficha, y el **primero es el que se ve en los resultados
de búsqueda**.
