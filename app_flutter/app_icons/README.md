# Iconos de la app — Portal Familia

Carpeta **central** para los iconos de todas las plataformas. Cambias una imagen
aquí, ejecutas un comando, y los iconos nativos de cada plataforma se
**sobrescriben** automáticamente (con `flutter_launcher_icons`).

> ⚡ **Resumen de medidas:** todas las imágenes en **PNG cuadrado de 1024 × 1024 px**.
> La herramienta genera sola todos los tamaños pequeños de cada plataforma (16 px,
> 20 px, 29 px, 40 px, 60 px, 76 px, 120 px, 152 px, 180 px, 512 px, 1024 px… no
> tienes que crearlos a mano). Las excepciones y detalles por plataforma, más abajo.

## 1. Coloca aquí tus imágenes (con EXACTAMENTE estos nombres)

| Archivo              | Plataforma                 | Tamaño recomendado | ¿Transparencia? |
|----------------------|----------------------------|--------------------|-----------------|
| `icon_ios.png`       | iPhone **y** iPad (iOS/iPadOS) | 1024×1024 px    | ❌ NO (fondo opaco) |
| `icon_android.png`   | Android                    | 1024×1024 px       | ✅ permitida    |
| `icon_macos.png`     | Mac (macOS)                | 1024×1024 px       | ✅ permitida    |
| `icon_windows.png`   | Windows                    | 1024×1024 px       | ✅ permitida    |
| `icon_linux.png`     | Linux                      | 1024×1024 px       | ✅ permitida    |

> **Linux es el único que NO pasa por `flutter_launcher_icons`**: esa herramienta no
> soporta Linux (no es que falte la opción, no existe). El icono lo coloca
> [`scripts/build-linux.sh`](../../scripts/build-linux.sh) al empaquetar, copiando
> `icon_linux.png` a `usr/share/icons/hicolor/256x256/apps/`. Solo tienes que dejar
> el fichero aquí con ese nombre.

> **iPadOS no lleva icono propio.** En iOS, iPhone y iPad usan el mismo icono, así
> que `icon_ios.png` cubre los dos. Un `icon_ipados.png` **no** se usaría.

## 2. Requisitos por plataforma

### iOS / iPadOS — `icon_ios.png`
- 1024×1024 px, PNG.
- **Sin transparencia / canal alfa** (Apple rechaza iconos iOS con alfa). Fondo relleno.
- **Sin esquinas redondeadas**: iOS las aplica solo. Entrega el arte cuadrado, a sangre.
- Sin texto pequeño; logo centrado.

### Android — `icon_android.png`
- 1024×1024 px, PNG (admite transparencia).
- El sistema recorta a varias formas (círculo, squircle…). Mantén lo importante en
  el **centro (~66 %)** para que no se corte.

### macOS — `icon_macos.png`
- 1024×1024 px, PNG (admite transparencia).
- macOS usa iconos con **márgenes y esquinas redondeadas** (estilo Big Sur). El
  generador **no** aplica ese estilo: usa la imagen tal cual. Para que se vea como
  un icono de Mac nativo, entrega el arte **ya con esos márgenes/redondeo** (plantilla
  de Apple). Si das una imagen cuadrada a sangre, se verá cuadrada.

### Windows — `icon_windows.png`
- PNG cuadrado, 256×256 mínimo (mejor 1024×1024). Se convierte a `.ico`.

## 3. Aplicar los iconos

Desde la carpeta `app_flutter/` (con Flutter en el PATH):

```bash
flutter pub get
dart run flutter_launcher_icons
```

Eso **sobrescribe** los iconos nativos de:
- iOS  → `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
- Android → `android/app/src/main/res/mipmap-*/`
- macOS → `macos/Runner/Assets.xcassets/AppIcon.appiconset/`
- Windows → `windows/runner/resources/app_icon.ico`

Repite el comando cada vez que cambies una imagen. La configuración vive en
`pubspec.yaml`, sección `flutter_launcher_icons:`.

## 4. (Opcional) Icono adaptativo de Android
Para el icono adaptativo por capas, añade a la config del `pubspec.yaml`:
```yaml
  adaptive_icon_background: "#FFFFFF"                      # color o imagen de fondo
  adaptive_icon_foreground: "app_icons/icon_android_fg.png"  # logo con margen
```
y coloca aquí `icon_android_fg.png` (el sistema recorta los bordes).

## 5. Notas para las tiendas
- El **1024×1024 de iOS** es el mismo que subes a App Store Connect.
- **Google Play** pide además el icono 512×512 de alta resolución (se sube en Play
  Console; no va dentro de la app).
