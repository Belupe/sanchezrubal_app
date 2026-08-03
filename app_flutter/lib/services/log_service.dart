import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';

/// Registro de fallos de la app, en las 5 plataformas.
///
/// Escribe en una carpeta **`Logs/`** dentro del directorio de soporte de la
/// app (`%APPDATA%\…` en Windows, `~/Library/Application Support/…` en macOS,
/// `~/.local/share/…` en Linux, y el sandbox en móvil). Como esa ruta no es
/// descubrible para alguien no técnico, Configuración tiene un botón que la
/// abre (escritorio) o comparte el informe (móvil).
///
/// **Tres ficheros, y nunca más de tres:**
///
///  - `sesion.log`       la sesión en curso
///  - `sesion.activa`    marcador de "hay una sesión abierta"
///  - `ultimo-fallo.log` el ÚLTIMO fallo conservado (solo uno)
///
/// El marcador es lo que hace funcionar la regla de borrado: si al arrancar
/// `sesion.activa` sigue ahí, la sesión anterior NO terminó limpia (fallo,
/// `kill`, corte de luz) y su `sesion.log` se asciende a `ultimo-fallo.log`.
/// Si el usuario cerró bien, no queda nada. Así el almacenamiento está acotado
/// por diseño y a la vez el último fallo sobrevive hasta que haya otro.
///
/// Cubre también los fallos NATIVOS (un segfault en GTK, un OOM del sistema),
/// que Dart no puede capturar porque el proceso muere sin ejecutar nada: no
/// habrá traza, pero el marcador delata la muerte y se conserva el registro
/// con lo último que se estaba haciendo.
///
/// Todo va en `try/catch`: el registro NUNCA debe tumbar la app (misma postura
/// que [PushService] y [SecureSessionStorage]).
class LogService {
  static Directory? _dir;
  static File? _sesion;
  static File? _marcador;
  static bool _listo = false;

  /// Tope del registro de la sesión. Si se pasa, se recorta por el PRINCIPIO
  /// (interesa lo último que ocurrió, que es lo que precede al fallo).
  static const int _maxBytes = 1024 * 1024; // 1 MB

  static const _nombreSesion = 'sesion.log';
  static const _nombreMarcador = 'sesion.activa';
  static const _nombreFallo = 'ultimo-fallo.log';

  /// Carpeta `Logs/`, o null si aún no se ha inicializado.
  static Directory? get carpeta => _dir;

  /// Ruta de la carpeta `Logs/` para enseñarla en Configuración.
  static String get rutaCarpeta => _dir?.path ?? '(no disponible)';

  /// El informe del último fallo, o null si no hay ninguno.
  static File? get ultimoFallo {
    final d = _dir;
    if (d == null) return null;
    final f = File('${d.path}/$_nombreFallo');
    return f.existsSync() ? f : null;
  }

  /// Prepara la carpeta, resuelve la sesión anterior y abre la nueva.
  /// Llamar lo antes posible en `main()`, antes de `runApp`.
  static Future<void> init() async {
    if (_listo) return;
    try {
      final soporte = await getApplicationSupportDirectory();
      final dir = Directory('${soporte.path}/Logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;
      _sesion = File('${dir.path}/$_nombreSesion');
      _marcador = File('${dir.path}/$_nombreMarcador');

      _resolverSesionAnterior();
      await _abrirSesion();
      _listo = true;
    } catch (e) {
      // Sin registro, pero la app arranca igual.
      debugPrint('LogService desactivado: $e');
    }
  }

  /// Si el marcador sigue existiendo, la sesión anterior murió sin cerrar:
  /// su registro se asciende a `ultimo-fallo.log` (sobrescribiendo el previo,
  /// para que nunca haya más de uno). Si no, se limpia el resto.
  static void _resolverSesionAnterior() {
    final dir = _dir!, sesion = _sesion!, marcador = _marcador!;
    try {
      if (marcador.existsSync()) {
        if (sesion.existsSync() && sesion.lengthSync() > 0) {
          sesion.copySync('${dir.path}/$_nombreFallo');
        }
        marcador.deleteSync();
      }
      if (sesion.existsSync()) sesion.deleteSync();
    } catch (_) {
      // Carpeta en mal estado: se seguirá intentando en el próximo arranque.
    }
  }

  /// Crea el marcador y escribe la cabecera de diagnóstico.
  static Future<void> _abrirSesion() async {
    try {
      _marcador!.writeAsStringSync('1', flush: true);
    } catch (_) {}

    String version = '?';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}

    final b = StringBuffer()
      ..writeln('=' * 70)
      ..writeln('Portal Familia — registro de sesión')
      ..writeln('Inicio      : ${_ahora()}')
      ..writeln('Versión     : $version')
      ..writeln(
        'Plataforma  : ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}',
      )
      ..writeln('Idioma      : ${Platform.localeName}')
      ..writeln('Ejecutable  : ${Platform.resolvedExecutable}')
      ..writeln('Carpeta log : ${_dir!.path}');
    final appImage = Platform.environment['APPIMAGE'];
    if (appImage != null && appImage.isNotEmpty) {
      b.writeln('AppImage    : $appImage');
    }
    b.writeln('=' * 70);
    _escribirCrudo(b.toString());
  }

  /// Un evento normal (navegación, acción del usuario, aviso).
  static void evento(String mensaje) => _linea('INFO ', mensaje);

  /// Un error con su traza. `origen` sitúa dónde ocurrió (pantalla, servicio).
  static void error(Object err, [StackTrace? traza, String? origen]) {
    final b = StringBuffer()
      ..writeln(origen == null ? 'ERROR: $err' : 'ERROR en $origen: $err');
    if (traza != null) b.writeln(traza.toString().trimRight());
    _linea('ERROR', b.toString().trimRight());
  }

  /// Un error del framework de Flutter, con su contexto de widget.
  static void errorFlutter(FlutterErrorDetails d) {
    final b = StringBuffer()
      ..writeln('ERROR Flutter: ${d.exceptionAsString()}');
    if (d.library != null) b.writeln('Librería: ${d.library}');
    if (d.context != null) b.writeln('Contexto: ${d.context}');
    if (d.stack != null) b.writeln(d.stack.toString().trimRight());
    _linea('ERROR', b.toString().trimRight());
  }

  /// Cierre LIMPIO: el usuario cerró la app (o el sistema la mandó a segundo
  /// plano en móvil, donde que el SO la mate después es normal, no un fallo).
  /// Borra marcador y registro de sesión; `ultimo-fallo.log` NO se toca.
  static void cierreLimpio() {
    try {
      _marcador?.deleteSync();
    } catch (_) {}
    try {
      final s = _sesion;
      if (s != null && s.existsSync()) s.deleteSync();
    } catch (_) {}
  }

  /// Vuelve a abrir la sesión tras un [cierreLimpio] (al volver del segundo
  /// plano en móvil).
  static Future<void> reabrirSesion() async {
    if (!_listo) return;
    try {
      if (_marcador!.existsSync()) return; // ya estaba abierta
      await _abrirSesion();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  //  Escritura
  // ---------------------------------------------------------------------

  static void _linea(String nivel, String texto) {
    debugPrint('[$nivel] $texto');
    // La redacción la aplica _escribirCrudo a todo lo que pasa por el registro,
    // para que no haya ninguna ruta de escritura que se la salte.
    _escribirCrudo('${_ahora()}  $nivel  $texto\n');
  }

  /// Escritura SÍNCRONA y con `flush`: si la app se muere justo después, lo
  /// escrito ya está en el fichero. Un `IOSink` con búfer perdería justo las
  /// últimas líneas, que son las que interesan.
  static void _escribirCrudo(String texto) {
    final f = _sesion;
    if (f == null) return;
    try {
      f.writeAsStringSync(redactar(texto), mode: FileMode.append, flush: true);
      if (f.lengthSync() > _maxBytes) _recortar(f);
    } catch (_) {
      // Disco lleno o sin permisos: no molestar al usuario por esto.
    }
  }

  /// Deja solo la última mitad del fichero cuando supera el tope.
  static void _recortar(File f) {
    try {
      final texto = f.readAsStringSync();
      final desde = texto.length - (_maxBytes ~/ 2);
      f.writeAsStringSync(
        '… (registro recortado por tamaño) …\n${texto.substring(desde)}',
        flush: true,
      );
    } catch (_) {}
  }

  static String _ahora() => DateTime.now().toIso8601String();

  // ---------------------------------------------------------------------
  //  Redacción de secretos
  // ---------------------------------------------------------------------

  /// Limpia el texto ANTES de escribirlo. Un registro que un familiar envía
  /// por correo **no puede llevar la sesión dentro**, y las excepciones de Dio
  /// y de Supabase arrastran URLs completas y cabeceras de autorización.
  ///
  /// Es pública a propósito para poder cubrirla con pruebas: es la única cosa
  /// de este fichero que, si falla, filtra credenciales
  /// (ver `test/log_service_test.dart`).
  static String redactar(String s) {
    var r = s;
    for (final p in _patrones) {
      r = r.replaceAllMapped(p.$1, (m) => p.$2(m));
    }
    // La clave pública horneada en la build: no es secreta, pero no aporta
    // nada al diagnóstico y ensucia el informe.
    if (AppConfig.supabaseAnonKey.isNotEmpty) {
      r = r.replaceAll(AppConfig.supabaseAnonKey, '<ANON_KEY>');
    }
    return r;
  }

  static final List<(RegExp, String Function(Match))> _patrones = [
    // JWT (access token / refresh de Supabase): tres segmentos base64url.
    (
      RegExp(r'eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]+'),
      (_) => '<JWT>',
    ),
    // Claves publicables/secretas de Supabase.
    (
      RegExp(r'sb_(publishable|secret)_[A-Za-z0-9_-]+'),
      (_) => '<SUPABASE_KEY>',
    ),
    // Tokens en JSON: "access_token":"…", "refresh_token":"…".
    (
      RegExp(r'"(access_token|refresh_token|apikey|api_key)"\s*:\s*"[^"]*"'),
      (m) => '"${m.group(1)}":"<REDACTADO>"',
    ),
    // Cabeceras HTTP. El valor se come ENTERO hasta el separador de cabecera
    // (coma, cierre de llave o fin de línea): parar en el primer espacio
    // dejaría el token a la vista en "Authorization: Bearer <token>".
    (
      RegExp(
        r'(authorization|apikey|x-api-key)\s*[:=]\s*[^,}\]\r\n]+',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}: <REDACTADO>',
    ),
    // Firmas de las URLs prefirmadas de MinIO (van en la query string y las
    // excepciones de Dio incluyen la URL entera).
    (
      RegExp(
        r'(X-Amz-Signature|X-Amz-Credential|X-Amz-Security-Token)=[^&\s"]+',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}=<REDACTADO>',
    ),
    // Correos: se deja el dominio, que a veces ayuda a situar el caso.
    (
      RegExp(r'[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})'),
      (m) => '<correo>@${m.group(1)}',
    ),
  ];
}
