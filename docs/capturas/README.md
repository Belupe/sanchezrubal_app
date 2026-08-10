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

## Peso

Son binarios y se quedan en el historial para siempre, así que conviene que
pesen poco. Un PNG de pantalla completa de un móvil moderno se va a varios
megas; redúcelo antes. Si en algún momento hacen falta muchas o muy grandes,
lo razonable es servirlas desde el NAS y enlazarlas, no meterlas en el
repositorio.
