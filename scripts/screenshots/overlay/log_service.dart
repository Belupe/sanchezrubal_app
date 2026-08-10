// SUSTITUTO PARA LAS CAPTURAS — no forma parte de la app que se publica.
//
// El LogService real escribe ficheros con `dart:io`, que no existe en el
// navegador. Para generar las capturas la app se compila a web, así que aquí
// va un doble con la MISMA API pública que no escribe nada.
//
// Ver scripts/screenshots/README.md.
import 'package:flutter/foundation.dart';

/// Doble de `File`/`Directory` con lo justo que usa ConfigScreen.
class LogFileRef {
  const LogFileRef(this.path);

  final String path;

  Uri get uri => Uri.parse('file://$path');

  DateTime lastModifiedSync() => DateTime.now();

  Future<String> readAsString() async => '';
}

class LogService {
  static Future<void> init() async {}

  static LogFileRef? get carpeta => null;

  static String get rutaCarpeta => '(no disponible en la vista previa)';

  static LogFileRef? get sesionActual => null;

  static LogFileRef? get ultimoFallo => null;

  static void evento(String mensaje) => debugPrint('INFO  $mensaje');

  static void error(Object err, [StackTrace? traza, String? origen]) =>
      debugPrint('ERROR ${origen ?? ''} $err');

  static void errorFlutter(FlutterErrorDetails d) =>
      debugPrint('ERROR flutter ${d.exception}');

  static void cierreLimpio() {}

  static Future<void> reabrirSesion() async {}

  static String redactar(String s) => s;
}
