# Capturas de la app

Sitio para las capturas de pantalla: documentación, la ficha de la App Store,
o enseñarle a alguien cómo se hace algo.

Se referencian desde cualquier `.md` de `docs/` con una ruta relativa:

```markdown
![Pantalla de reservas](capturas/reservas-ios.png)
```

## ⚠️ Este repositorio es PÚBLICO

Lo que se suba aquí lo puede ver cualquiera, y **queda en el historial de git
aunque luego se borre el fichero**. Borrar una captura en un commit posterior no
la retira: sigue accesible en el commit donde se añadió.

Antes de subir una captura, comprueba que no salga:

- **Nombres y correos reales** de la familia.
- **Fechas de reservas.** Es lo que más se pasa por alto y lo más delicado: un
  calendario público de cuándo están vacías las casas es información útil para
  quien no debe tenerla.
- **Direcciones o nombres identificables** de los domicilios.
- **Tokens, enlaces firmados de fotos o cualquier cosa de la pestaña Soporte**,
  que muestra rutas de ficheros y estado de las notificaciones.

La forma cómoda de evitarlo es hacer las capturas con datos inventados, no con
la cuenta de alguien real. Si ya tienes la captura hecha, tapa esas zonas antes
de guardarla, no después de subirla.

## Cómo nombrarlas

`<pantalla>-<plataforma>.png` en minúsculas y sin acentos:

```
reservas-ios.png
soporte-macos.png
calendario-windows.png
```

## Las de la App Store van aparte, en subcarpetas

`iphone-6.5/`, `ipad-13/` y `macos/` se saltan la norma de arriba a propósito:

- **Una carpeta por ficha**, porque son los tres tamaños que App Store Connect
  sube por separado (1284 × 2778, 2048 × 2732 y 2880 × 1800). La carpeta ya dice
  la plataforma, así que el nombre del fichero no la repite.
- **Numeradas** (`01-…`, `02-…`), porque ese es el orden en que la ficha las
  enseña y **la primera es la que sale en los resultados de búsqueda**. El
  número es información, no decoración.

Las genera [`scripts/screenshots/run.sh`](../../scripts/screenshots/run.sh) con
datos de una familia inventada, que es justo lo que pide el aviso de arriba: la
app se compila apuntando a un Supabase simulado, así que ni tocan la base de
datos ni pueden colarse nombres o fechas reales. Si cambias la interfaz, vuelve
a lanzarlo en lugar de retocarlas a mano.

## Peso

Son binarios y se quedan en el historial para siempre, así que conviene que
pesen poco. Un PNG de pantalla completa de un móvil moderno se va a varios
megas; redúcelo antes. Si en algún momento hacen falta muchas o muy grandes,
lo razonable es servirlas desde el NAS y enlazarlas, no meterlas en el
repositorio.
