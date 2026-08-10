"""Declara Roboto como fuente empaquetada en el pubspec de la copia de trabajo.

Se hace aquí y no en `app_flutter/pubspec.yaml` porque solo hace falta para la
compilación web de las capturas: en Android, iOS, Windows, macOS y Linux la
fuente la pone el sistema, y añadirla al paquete real engordaría las 5 apps sin
motivo.

Uso:  python3 fuentes.py <ruta-al-pubspec.yaml>
"""
import io
import sys

ANCLA = "  uses-material-design: true\n"

BLOQUE = ANCLA + """
  # Añadido SOLO para la compilación de capturas (scripts/screenshots/run.sh).
  fonts:
    - family: Roboto
      fonts:
        - asset: assets/fonts/Roboto-Light.ttf
          weight: 300
        - asset: assets/fonts/Roboto-Regular.ttf
          weight: 400
        - asset: assets/fonts/Roboto-Italic.ttf
          weight: 400
          style: italic
        - asset: assets/fonts/Roboto-Medium.ttf
          weight: 500
        - asset: assets/fonts/Roboto-Bold.ttf
          weight: 700
        - asset: assets/fonts/Roboto-BoldItalic.ttf
          weight: 700
          style: italic
"""
# Los caracteres que Roboto no trae (la flecha "→", el "⭐") NO se arreglan
# aquí: registrar una segunda fuente en la misma familia no sirve, porque el
# motor elige por estilo y no por cobertura. Se resuelven con el espejo de
# `/gfonts/` que monta mock_backend.mjs.


def main(ruta: str) -> None:
    with io.open(ruta, encoding="utf-8") as f:
        texto = f.read()

    if "assets/fonts/Roboto-Regular.ttf" in texto:
        return  # ya estaba

    if ANCLA not in texto:
        raise SystemExit(
            "No encuentro 'uses-material-design: true' en el pubspec: "
            "revisa scripts/screenshots/fuentes.py"
        )

    with io.open(ruta, "w", encoding="utf-8") as f:
        f.write(texto.replace(ANCLA, BLOQUE, 1))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
