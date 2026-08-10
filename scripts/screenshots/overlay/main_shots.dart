// PUNTO DE ENTRADA PARA LAS CAPTURAS — no forma parte de la app que se publica.
//
// Arranca la app REAL (`PortalFamiliaApp`, con sus pantallas de verdad) contra
// el backend simulado de `mock_backend.mjs`, y añade lo que hace falta para que
// una ventana de Chromium se parezca a un iPhone/iPad:
//
//   · el navegador se hace pasar por iOS (user agent + `navigator.platform`),
//     así que `defaultTargetPlatform` vale `iOS` y la app se comporta como en
//     el dispositivo: transiciones, física del scroll y `Theme.of(context)
//     .platform`.
//   · zonas seguras (isla dinámica / indicador de inicio) inyectadas por
//     MediaQuery, para que la AppBar pinte su fondo bajo la barra de estado
//     igual que en el dispositivo.
//   · barra de estado de iOS dibujada encima (hora, cobertura, wifi, batería),
//     como la que sale en las capturas del simulador de Xcode.
//   · semántica siempre activa: así Playwright encuentra los botones por su
//     etiqueta en el DOM en vez de pulsar a ciegas por coordenadas.
//
// Parámetros por la URL:
//   ?top=59&bottom=34   zonas seguras en píxeles lógicos
//   ?statusbar=0        no dibujar la barra de estado
//   ?login=1            quedarse en la pantalla de acceso (sin iniciar sesión)
//   ?dark=1             forzar tema oscuro
//
// Ver scripts/screenshots/README.md.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:portal_familia/config.dart';
import 'package:portal_familia/main.dart';

/// Credenciales del backend simulado (ver `mock_backend.mjs`). No existen fuera
/// de la máquina que genera las capturas.
const _demoEmail = 'demo@sanchezrubal.net';
const _demoPassword = 'demo-capturas';

/// Traza del arranque. Un fallo aquí deja la página en blanco, y en una
/// compilación de release el error llega al navegador minificado y sin
/// contexto; con esto se ve en qué paso se rompió.
void _paso(String texto) => print('[capturas] $texto');

Future<void> main() async {
  try {
    await _arrancar();
  } catch (e, s) {
    _paso('FALLO: $e');
    _paso('$s');
    rethrow;
  }
}

Future<void> _arrancar() async {
  _paso('binding');
  WidgetsFlutterBinding.ensureInitialized();

  // El árbol de semántica se publica en el DOM: Playwright puede pulsar
  // `flt-semantics[aria-label="Domicilios"]` en lugar de adivinar coordenadas.
  SemanticsBinding.instance.ensureSemantics();

  // La app se cree que está en iOS porque el navegador lo dice: Playwright
  // emula el user agent y `navigator.platform` del dispositivo, y el motor de
  // Flutter deduce de ahí `defaultTargetPlatform`. (No se puede usar
  // `debugDefaultTargetPlatformOverride`: solo existe en compilaciones de
  // depuración, y las capturas se hacen en release para que se vean como la
  // app publicada.)
  _paso('plataforma detectada: $defaultTargetPlatform');

  final q = Uri.base.queryParameters;
  final top = double.tryParse(q['top'] ?? '') ?? 0;
  final bottom = double.tryParse(q['bottom'] ?? '') ?? 0;
  final conBarra = q['statusbar'] != '0';
  final soloLogin = q['login'] == '1';
  final ventanaMac = q['chrome'] == 'macos';

  themeNotifier.value = q['dark'] == '1' ? ThemeMode.dark : ThemeMode.light;

  _paso('fechas en español');
  await initializeDateFormatting('es', null);

  _paso('supabase → ${AppConfig.supabaseUrl}');
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  if (!soloLogin) {
    _paso('inicio de sesión');
    await Supabase.instance.client.auth.signInWithPassword(
      email: _demoEmail,
      password: _demoPassword,
    );
  }

  _paso('runApp');
  runApp(
    ventanaMac
        ? const _VentanaMac(child: PortalFamiliaApp())
        : _MarcoDispositivo(
            top: top,
            bottom: bottom,
            barraDeEstado: conBarra,
            child: const PortalFamiliaApp(),
          ),
  );
}

/// Ventana de macOS maximizada: barra de título del sistema arriba y la app
/// justo debajo.
///
/// No se usa el mecanismo de zonas seguras del móvil porque en macOS la barra
/// de título **no** es parte de la vista de Flutter: la pinta el sistema y la
/// app empieza por debajo. Por eso aquí la app se desplaza de verdad en un
/// Column, en vez de dejar que la AppBar se meta bajo el recorte.
class _VentanaMac extends StatelessWidget {
  const _VentanaMac({required this.child});

  /// Alto de la barra de título estándar de macOS, en puntos.
  static const double alto = 28;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        // Sin esto la barra de título se encogería al ancho de su texto: el
        // Column centra por defecto y no estira a sus hijos.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _BarraDeTitulo(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Barra de título con los tres botones de semáforo y el nombre de la app,
/// que en macOS es el `PRODUCT_NAME` de `AppInfo.xcconfig`: "Portal Familia".
///
/// Es cromo del sistema, no interfaz de la app, igual que la barra de estado
/// de iOS: sale así en cualquier captura de una ventana de Mac.
class _BarraDeTitulo extends StatelessWidget {
  const _BarraDeTitulo();

  @override
  Widget build(BuildContext context) {
    const semaforo = [
      Color(0xFFFF5F57), // cerrar
      Color(0xFFFEBC2E), // minimizar
      Color(0xFF28C840), // pantalla completa
    ];

    return Container(
      height: _VentanaMac.alto,
      decoration: const BoxDecoration(
        color: Color(0xFFECECEC),
        border: Border(bottom: BorderSide(color: Color(0xFFD3D3D3))),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Text(
            'Portal Familia',
            style: TextStyle(
              color: Color(0xFF41424A),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Positioned(
            left: 13,
            child: Row(
              children: [
                for (final color in semaforo)
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Envuelve la app con las zonas seguras del dispositivo y, encima de todo, la
/// barra de estado de iOS.
class _MarcoDispositivo extends StatelessWidget {
  const _MarcoDispositivo({
    required this.top,
    required this.bottom,
    required this.barraDeEstado,
    required this.child,
  });

  final double top;
  final double bottom;
  final bool barraDeEstado;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final base = MediaQueryData.fromView(view);

    return MediaQuery(
      data: base.copyWith(
        padding: EdgeInsets.only(top: top, bottom: bottom),
        viewPadding: EdgeInsets.only(top: top, bottom: bottom),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (barraDeEstado && top > 0)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: top,
                child: _BarraDeEstado(alto: top),
              ),
          ],
        ),
      ),
    );
  }
}

/// Barra de estado de iOS: hora a la izquierda, cobertura + wifi + batería a la
/// derecha. Es decoración del dispositivo, no interfaz de la app — la misma que
/// aparece en cualquier captura hecha con el simulador de Xcode.
class _BarraDeEstado extends StatelessWidget {
  const _BarraDeEstado({required this.alto});

  final double alto;

  @override
  Widget build(BuildContext context) {
    // La barra va sobre el fondo que pinta la AppBar bajo la zona segura, así
    // que el color del texto lo decide el brillo del tema.
    final oscuro = themeNotifier.value == ThemeMode.dark;
    final color = oscuro ? Colors.white : Colors.black;

    return Padding(
      // El texto se apoya en la mitad inferior del recorte, como en iOS.
      padding: EdgeInsets.only(top: alto * 0.36, left: 34, right: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // 9:41 es la hora canónica de Apple en todo su material.
            '9:41',
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              height: 1,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Cobertura(color: color),
              const SizedBox(width: 6),
              Icon(Icons.wifi, size: 17, color: color),
              const SizedBox(width: 6),
              _Bateria(color: color),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cobertura extends StatelessWidget {
  const _Cobertura({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final h in const [4.0, 6.5, 9.0, 11.5])
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Container(
                width: 3,
                height: h,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bateria extends StatelessWidget {
  const _Bateria({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 25,
          height: 12,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
            borderRadius: BorderRadius.circular(3.5),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.82,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: 1.5,
          height: 4,
          margin: const EdgeInsets.only(left: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }
}
