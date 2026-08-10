// Capturas de la App Store: recorre la app emulando un iPhone, un iPad y un Mac.
//
// La app corre de verdad en Chromium (compilada a web, servida por
// `mock_backend.mjs`). Aquí solo se emula el dispositivo y se navega:
//
//   · viewport en puntos + `deviceScaleFactor` = resolución exacta que pide
//     App Store Connect (1284x2778 iPhone, 2048x2732 iPad, 2880x1800 Mac).
//   · user agent y `navigator.platform` de iOS, para que Flutter resuelva
//     `defaultTargetPlatform == TargetPlatform.iOS` y la app se comporte como
//     en el dispositivo.
//   · las pulsaciones son toques reales sobre el árbol de semántica que Flutter
//     publica en el DOM, no coordenadas a ojo.
//
// Uso:  node capture.mjs --salida=<dir> [--url=http://127.0.0.1:8787]
//                       [--dispositivo=iphone|ipad|todos]
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

// Playwright suele estar instalado globalmente; `run.sh` pasa la raíz de npm.
// Al cargarlo por ruta absoluta Node no siempre reconoce las exportaciones
// con nombre del paquete (es CommonJS), así que se mira también en `default`.
const chromium = await (async () => {
  const intentos = ['playwright'];
  if (process.env.NPM_GLOBAL_ROOT) {
    intentos.push(join(process.env.NPM_GLOBAL_ROOT, 'playwright', 'index.js'));
  }
  for (const especificador of intentos) {
    try {
      const modulo = await import(especificador);
      const encontrado = modulo.chromium ?? modulo.default?.chromium;
      if (encontrado) return encontrado;
    } catch {
      // se prueba el siguiente
    }
  }
  throw new Error('No encuentro Playwright. Instálalo con:  npm i -g playwright');
})();

// ---------------------------------------------------------------------------
//  Argumentos
// ---------------------------------------------------------------------------
const arg = (nombre, pordefecto) => {
  const encontrado = process.argv.find((a) => a.startsWith(`--${nombre}=`));
  return encontrado ? encontrado.slice(nombre.length + 3) : pordefecto;
};

const SALIDA = arg('salida', 'dist/screenshots');
const URL_BASE = arg('url', 'http://127.0.0.1:8787');
const QUE = arg('dispositivo', 'todos');

// ---------------------------------------------------------------------------
//  Dispositivos
//
//  Las medidas en puntos por el factor de escala dan EXACTAMENTE las
//  resoluciones que acepta App Store Connect. Las zonas seguras son las del
//  dispositivo real (isla dinámica arriba, indicador de inicio abajo).
// ---------------------------------------------------------------------------
const UA_IPHONE =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 '
  + '(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';
const UA_IPAD =
  'Mozilla/5.0 (iPad; CPU OS 18_5 like Mac OS X) AppleWebKit/605.1.15 '
  + '(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';
const UA_MACOS =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
  + '(KHTML, like Gecko) Version/18.5 Safari/605.1.15';

const DISPOSITIVOS = {
  iphone: {
    // iPhone 12/13 Pro Max, 14 Plus — pantalla de 6,5". Es el tamaño que pide
    // la ficha de esta app; App Store Connect también acepta 1242 x 2688
    // (iPhone 11 Pro Max, 414 x 896). Muesca de 47 pt, no isla dinámica.
    carpeta: 'iphone-6.5',
    etiqueta: 'iPhone 6,5"',
    ancho: 428,
    alto: 926,
    escala: 3,
    seguraArriba: 47,
    seguraAbajo: 34,
    ua: UA_IPHONE,
    plataforma: 'iPhone',
    movil: true,
  },
  'iphone-6.9': {
    // iPhone 16 Pro Max. NO entra en `--dispositivo=todos`: la ficha de esta
    // app pide el de 6,5". Se genera a mano con `--dispositivo=iphone-6.9` si
    // algún día App Store Connect enseña esa ranura.
    //
    // OJO: antes ponía 430 x 932, que es el iPhone 15 Pro Max y a escala 3 da
    // 1290 x 2796 — el tamaño de 6,7", no el de 6,9". El nombre prometía una
    // cosa y salía otra. Los 6,9" son 440 x 956, que dan los 1320 x 2868 que
    // espera App Store Connect.
    carpeta: 'iphone-6.9',
    etiqueta: 'iPhone 6,9"',
    ancho: 440,
    alto: 956,
    escala: 3,
    seguraArriba: 62,
    seguraAbajo: 34,
    ua: UA_IPHONE,
    plataforma: 'iPhone',
    movil: true,
    aparte: true,
  },
  ipad: {
    // iPad Pro de 13". Obligatorio si la app se publica también para iPad.
    carpeta: 'ipad-13',
    etiqueta: 'iPad 13"',
    ancho: 1024,
    alto: 1366,
    escala: 2,
    seguraArriba: 24,
    seguraAbajo: 20,
    ua: UA_IPAD,
    plataforma: 'iPad',
    movil: false,
  },
  macos: {
    // Mac con pantalla Retina: 1440 x 900 a x2. De las cuatro medidas que
    // acepta App Store Connect (1280x800, 1440x900, 2560x1600, 2880x1800) es
    // la mayor, así que se ve nítida en cualquier sitio.
    //
    // Aquí no hay zonas seguras: lo que hay es una VENTANA. La barra de título
    // la pinta el sistema por encima de la vista de Flutter, no por debajo,
    // así que se dibuja con `chrome=macos` y la app se desplaza de verdad.
    carpeta: 'macos',
    etiqueta: 'Mac',
    ancho: 1440,
    alto: 900,
    escala: 2,
    seguraArriba: 0,
    seguraAbajo: 0,
    ua: UA_MACOS,
    plataforma: 'MacIntel',
    movil: false,
    tactil: false,
    ventana: 'macos',
  },
};

// ---------------------------------------------------------------------------
//  Guion: qué se fotografía y cómo se llega
// ---------------------------------------------------------------------------
const GUION = [
  {
    fichero: '01-anuncios',
    esperarTitulo: 'Anuncios',
    descripcion: 'Tablón de anuncios de la familia',
  },
  {
    fichero: '02-domicilios',
    esperarTitulo: 'Domicilios',
    descripcion: 'Las casas de la familia',
    ir: async (p) => abrirDesdeElMenu(p, 'Domicilios'),
  },
  {
    fichero: '03-calendario',
    // El botón flotante solo existe en el calendario de un domicilio.
    esperar: 'Reservar',
    descripcion: 'Calendario de ocupación de una casa',
    ir: async (p) => {
      await abrirDesdeElMenu(p, 'Domicilios');
      await pulsar(p, 'Casa de Zahara');
    },
  },
  {
    fichero: '04-inspecciones',
    esperarTitulo: 'Inspecciones',
    descripcion: 'Partes de salida con fotos y valoración',
    ir: async (p) => abrirDesdeElMenu(p, 'Inspecciones'),
  },
  {
    fichero: '05-sorteos',
    esperarTitulo: 'Sorteos',
    descripcion: 'Reparto de quincenas por sorteo',
    ir: async (p) => abrirDesdeElMenu(p, 'Sorteos'),
    // La pantalla abre por el formulario de "nuevo sorteo"; lo que se quiere
    // enseñar es el historial con los resultados, que está más abajo.
    desplazarHasta: 'Historial',
  },
  {
    fichero: '06-grupos-y-usuarios',
    esperarTitulo: 'Grupos y usuarios',
    descripcion: 'Familias, miembros y permisos',
    ir: async (p) => abrirDesdeElMenu(p, 'Grupos y usuarios'),
  },
  {
    fichero: '07-usuarios',
    esperarTitulo: 'Grupos y usuarios',
    descripcion: 'Las personas de la familia y su rango',
    ir: async (p) => {
      await abrirDesdeElMenu(p, 'Grupos y usuarios');
      await pulsar(p, 'Usuarios'); // la otra pestaña de la misma pantalla
      await p.waitForTimeout(700);
    },
  },
  {
    fichero: '08-registros',
    esperarTitulo: 'Registros',
    descripcion: 'Quién ha creado, cambiado o borrado cada reserva',
    ir: async (p) => abrirDesdeElMenu(p, 'Registros'),
  },
  {
    fichero: '09-menu',
    descripcion: 'Menú de navegación desplegado',
    ir: async (p) => {
      await pulsar(p, 'Abrir el menú de navegación');
      await p.waitForTimeout(900);
    },
  },
];

// ---------------------------------------------------------------------------
//  Utilidades sobre el árbol de semántica de Flutter
// ---------------------------------------------------------------------------

/// Centro del nodo semántico cuya etiqueta coincide, o null si no está.
///
/// Flutter publica el texto unas veces en `aria-label` y otras como contenido
/// del elemento, así que se miran los dos. Y como los nodos anidan (la raíz
/// contiene el texto de toda la pantalla), entre los que encajan se elige el
/// más pequeño: ese es el control concreto, no su contenedor.
const buscar = (page, etiqueta) =>
  page.evaluate((et) => {
    const candidatos = [];
    for (const n of document.querySelectorAll('flt-semantics')) {
      const r = n.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) continue;
      const texto = (n.getAttribute('aria-label') ?? n.textContent ?? '').trim();
      if (!texto) continue;
      candidatos.push({ exacto: texto === et, empieza: texto.startsWith(et), r });
    }
    const encajan = candidatos.filter((c) => c.exacto);
    const lista = encajan.length ? encajan : candidatos.filter((c) => c.empieza);
    if (!lista.length) return null;
    lista.sort((a, b) => a.r.width * a.r.height - b.r.width * b.r.height);
    const { r } = lista[0];
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, etiqueta);

/// Etiquetas visibles ahora mismo, para que un fallo diga algo útil.
const etiquetasVisibles = (page) =>
  page.evaluate(() =>
    [...document.querySelectorAll('flt-semantics')]
      .map((n) => (n.getAttribute('aria-label') ?? n.textContent ?? '').trim())
      .filter((t) => t && t.length < 40),
  );

/// En el Mac no hay pantalla táctil: allí se pulsa con el ratón. Lo fija
/// `capturarDispositivo` antes de empezar con cada dispositivo.
let usarToque = true;

/// Toca (o hace clic en) un elemento por su etiqueta accesible, esperando a
/// que aparezca.
async function pulsar(page, etiqueta, { intentos = 40 } = {}) {
  for (let i = 0; i < intentos; i++) {
    const punto = await buscar(page, etiqueta);
    if (punto) {
      if (usarToque) {
        await page.touchscreen.tap(punto.x, punto.y);
      } else {
        await page.mouse.click(punto.x, punto.y);
      }
      return;
    }
    await page.waitForTimeout(250);
  }
  const hay = [...new Set(await etiquetasVisibles(page))].slice(0, 25);
  throw new Error(
    `No aparece ningún elemento con la etiqueta "${etiqueta}".\n`
    + `  En pantalla hay: ${hay.join(' · ')}`,
  );
}

/// El título de la AppBar no es un nodo suelto: Flutter lo funde en el texto
/// del nodo raíz, justo detrás del botón del menú. Buscarlo ahí es lo que
/// confirma que la pantalla del cajón ya está abierta.
async function esperarTitulo(page, titulo, { intentos = 60 } = {}) {
  for (let i = 0; i < intentos; i++) {
    const ok = await page.evaluate((t) => {
      const raiz = document.querySelector('flt-semantics');
      return (raiz?.textContent ?? '').includes(`Abrir el menú de navegación${t}`);
    }, titulo);
    if (ok) return;
    await page.waitForTimeout(250);
  }
  const raiz = await page.evaluate(
    () => (document.querySelector('flt-semantics')?.textContent ?? '').slice(0, 200),
  );
  throw new Error(`La pantalla "${titulo}" no llegó a abrirse.\n  Texto raíz: ${raiz}`);
}

/// Espera a que un elemento con esa etiqueta esté en pantalla. Para las
/// pantallas que se abren encima (sin cajón) y tienen algo propio y visible,
/// como el botón flotante del calendario.
async function esperarEtiqueta(page, etiqueta, { intentos = 60 } = {}) {
  for (let i = 0; i < intentos; i++) {
    if (await buscar(page, etiqueta)) return;
    await page.waitForTimeout(250);
  }
  const hay = [...new Set(await etiquetasVisibles(page))].slice(0, 25);
  throw new Error(
    `La pantalla no llegó a mostrar "${etiqueta}".\n  En pantalla hay: ${hay.join(' · ')}`,
  );
}

/// Espera a que Flutter haya arrancado y publicado la semántica.
async function esperarArranque(page) {
  await page.waitForFunction(
    () => document.querySelectorAll('flt-semantics').length > 3,
    null,
    { timeout: 90_000 },
  );
}

async function abrirDesdeElMenu(page, entrada) {
  await pulsar(page, 'Abrir el menú de navegación');
  await page.waitForTimeout(700); // el cajón se despliega
  await pulsar(page, entrada);
  await page.waitForTimeout(700); // y se recoge
}

/// Desplaza la pantalla hasta que ese elemento quede arriba del todo.
///
/// Se mide contra el elemento en vez de usar una cantidad fija de píxeles
/// porque el mismo contenido cae a distinta altura en el iPhone y en el iPad.
/// Al terminar, el puntero se retira a la barra de estado (que no reacciona),
/// para que ningún elemento se quede resaltado por tenerlo encima.
async function desplazarHasta(page, etiqueta, disp, { intentos = 25 } = {}) {
  const objetivo = disp.alto * 0.22;
  for (let i = 0; i < intentos; i++) {
    const punto = await buscar(page, etiqueta);
    if (!punto || punto.y <= objetivo) break;
    await page.mouse.move(disp.ancho / 2, disp.alto / 2);
    await page.mouse.wheel(0, Math.min(360, punto.y - objetivo));
    await page.waitForTimeout(350);
  }
  await page.mouse.move(disp.ancho / 2, 10);
  await page.waitForTimeout(400);
}

/// Deja que terminen las peticiones y las animaciones antes de disparar.
async function asentar(page) {
  try {
    await page.waitForLoadState('networkidle', { timeout: 15_000 });
  } catch {
    // Realtime mantiene un socket abierto: `networkidle` puede no llegar.
  }
  await page.waitForTimeout(1200);
}

// ---------------------------------------------------------------------------
//  Captura
// ---------------------------------------------------------------------------
async function capturarDispositivo(navegador, disp) {
  const destino = join(SALIDA, disp.carpeta);
  await mkdir(destino, { recursive: true });

  const contexto = await navegador.newContext({
    viewport: { width: disp.ancho, height: disp.alto },
    deviceScaleFactor: disp.escala,
    isMobile: disp.movil,
    hasTouch: disp.tactil ?? true,
    userAgent: disp.ua,
    locale: 'es-ES',
    timezoneId: 'Europe/Madrid',
    colorScheme: 'light',
    reducedMotion: 'reduce',
  });

  // Playwright emula el user agent pero no `navigator.platform`, y Flutter mira
  // las dos cosas para decidir en qué sistema cree que está.
  await contexto.addInitScript((d) => {
    Object.defineProperty(navigator, 'platform', { get: () => d.plataforma });
    // Ojo: Flutter identifica un iPad como "MacIntel" CON puntos táctiles. En
    // el Mac tienen que ser 0 o la app se creería que está en un iPad.
    Object.defineProperty(navigator, 'maxTouchPoints', { get: () => d.toques });
  }, { plataforma: disp.plataforma, toques: (disp.tactil ?? true) ? 5 : 0 });

  usarToque = disp.tactil ?? true;

  const page = await contexto.newPage();
  const fallos = [];
  page.on('pageerror', (e) => fallos.push(String(e.message ?? e).slice(0, 200)));

  // La app anuncia por consola qué sistema ha deducido del navegador. Si se
  // equivocara (un Mac tomado por iPad, por ejemplo) las capturas saldrían mal
  // sin avisar, así que se comprueba en voz alta.
  let plataformaVista = null;
  page.on('console', (m) => {
    const t = m.text();
    if (t.includes('plataforma detectada')) {
      plataformaVista ??= t.split('plataforma detectada:').pop().trim();
    }
  });

  const url = `${URL_BASE}/?top=${disp.seguraArriba}&bottom=${disp.seguraAbajo}`
    + (disp.ventana ? `&chrome=${disp.ventana}` : '');
  const hechas = [];

  for (const escena of GUION) {
    // Cada escena parte de cero: así una pantalla no arrastra el estado de la
    // anterior y el orden del guion no cambia el resultado.
    await page.goto(url, { waitUntil: 'load' });
    await esperarArranque(page);
    await asentar(page);

    if (escena.ir) await escena.ir(page);
    if (escena.esperarTitulo) await esperarTitulo(page, escena.esperarTitulo);
    if (escena.esperar) await esperarEtiqueta(page, escena.esperar);
    if (escena.desplazarHasta) await desplazarHasta(page, escena.desplazarHasta, disp);
    await asentar(page);

    const fichero = join(destino, `${escena.fichero}.png`);
    await page.screenshot({ path: fichero, scale: 'device' });
    hechas.push({ fichero: `${escena.fichero}.png`, descripcion: escena.descripcion });
    console.log(`  ✓ ${disp.carpeta}/${escena.fichero}.png — ${escena.descripcion}`);
  }

  await writeFile(
    join(destino, 'INDICE.txt'),
    [
      `${disp.etiqueta} — ${disp.ancho * disp.escala} x ${disp.alto * disp.escala} px`,
      '',
      ...hechas.map((h) => `${h.fichero}  ${h.descripcion}`),
      '',
      'Generado por scripts/screenshots/run.sh',
      '',
    ].join('\n'),
    'utf8',
  );

  console.log(`  · la app se ve en: ${plataformaVista ?? '(no lo dijo)'}`);
  if (fallos.length) {
    console.log(`  · avisos de la app: ${[...new Set(fallos)].join(' | ')}`);
  }
  await contexto.close();
}

// ---------------------------------------------------------------------------
const elegidos =
  QUE === 'todos'
    ? Object.values(DISPOSITIVOS).filter((d) => !d.aparte)
    : [DISPOSITIVOS[QUE]].filter(Boolean);

if (elegidos.length === 0) {
  console.error(
    `Dispositivo desconocido: ${QUE}\n`
    + `  Usa: ${Object.keys(DISPOSITIVOS).join(', ')} o todos`,
  );
  process.exit(1);
}

const navegador = await chromium.launch({
  args: [
    // Todo es local: sin esto Chromium intentaría salir por el proxy.
    '--no-proxy-server',
    // Sin GPU real, CanvasKit necesita el WebGL por software.
    '--enable-unsafe-swiftshader',
    '--hide-scrollbars',
    '--font-render-hinting=none',
  ],
});

for (const disp of elegidos) {
  console.log(`\n${disp.etiqueta} — ${disp.ancho * disp.escala} x ${disp.alto * disp.escala} px`);
  await capturarDispositivo(navegador, disp);
}

await navegador.close();
console.log(`\nListo. Capturas en ${SALIDA}/`);
