// PLANTILLA DE ARRANQUE PARA LAS CAPTURAS — no forma parte de la app publicada.
//
// Igual que la que genera Flutter, salvo por una línea: los tipos de letra de
// respaldo se piden al servidor local en lugar de a fonts.gstatic.com.
//
// Hacen falta porque Roboto no trae todos los caracteres que usa la app (la
// flecha "→" de los rangos de fechas, el "⭐" de las valoraciones): en el móvil
// los pone el sistema, y en el navegador el motor los descarga. `mock_backend.mjs`
// atiende `/gfonts/` haciendo de espejo con caché, así la segunda vez y las
// siguientes no hace falta ni salir a internet.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: `${window.location.origin}/gfonts/`,
  },
});
