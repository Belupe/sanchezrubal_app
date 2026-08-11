// Log de diagnóstico local; redacta datos sensibles antes de mostrarlo o enviarlo.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';

class LogService {
  static Directory? _dir;
  static File? _sesion;
  static File? _marcador;
  static bool _listo = false;

  static const int _maxBytes = 1024 * 1024;

  static const _nombreSesion = 'sesion.log';
  static const _nombreMarcador = 'sesion.activa';
  static const _nombreFallo = 'ultimo-fallo.log';

  static Directory? get carpeta => _dir;

  static String get rutaCarpeta => _dir?.path ?? '(no disponible)';

  static File? get sesionActual {
    final f = _sesion;
    return (f != null && f.existsSync()) ? f : null;
  }

  static File? get ultimoFallo {
    final d = _dir;
    if (d == null) return null;
    final f = File('${d.path}/$_nombreFallo');
    return f.existsSync() ? f : null;
  }

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
      debugPrint('LogService desactivado: $e');
    }
  }

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
    }
  }

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

  static void evento(String mensaje) => _linea('INFO ', mensaje);

  static void error(Object err, [StackTrace? traza, String? origen]) {
    final b = StringBuffer()
      ..writeln(origen == null ? 'ERROR: $err' : 'ERROR en $origen: $err');
    if (traza != null) b.writeln(traza.toString().trimRight());
    _linea('ERROR', b.toString().trimRight());
  }

  static void errorFlutter(FlutterErrorDetails d) {
    final b = StringBuffer()
      ..writeln('ERROR Flutter: ${d.exceptionAsString()}');
    if (d.library != null) b.writeln('Librería: ${d.library}');
    if (d.context != null) b.writeln('Contexto: ${d.context}');
    if (d.stack != null) b.writeln(d.stack.toString().trimRight());
    _linea('ERROR', b.toString().trimRight());
  }

  static void cierreLimpio() {
    try {
      _marcador?.deleteSync();
    } catch (_) {}
    try {
      final s = _sesion;
      if (s != null && s.existsSync()) s.deleteSync();
    } catch (_) {}
  }

  static Future<void> reabrirSesion() async {
    if (!_listo) return;
    try {
      if (_marcador!.existsSync()) return;
      await _abrirSesion();
    } catch (_) {}
  }

  static void _linea(String nivel, String texto) {
    debugPrint('[$nivel] $texto');

    _escribirCrudo('${_ahora()}  $nivel  $texto\n');
  }

  static void _escribirCrudo(String texto) {
    final f = _sesion;
    if (f == null) return;
    try {
      f.writeAsStringSync(redactar(texto), mode: FileMode.append, flush: true);
      if (f.lengthSync() > _maxBytes) _recortar(f);
    } catch (_) {
    }
  }

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

  static String redactar(String s) {
    var r = s;
    for (final p in _patrones) {
      r = r.replaceAllMapped(p.$1, (m) => p.$2(m));
    }

    if (AppConfig.supabaseAnonKey.isNotEmpty) {
      r = r.replaceAll(AppConfig.supabaseAnonKey, '<ANON_KEY>');
    }
    return r;
  }

  static final List<(RegExp, String Function(Match))> _patrones = [

    (
      RegExp(r'eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]+'),
      (_) => '<JWT>',
    ),

    (
      RegExp(r'sb_(publishable|secret)_[A-Za-z0-9_-]+'),
      (_) => '<SUPABASE_KEY>',
    ),

    (
      RegExp(r'"(access_token|refresh_token|apikey|api_key)"\s*:\s*"[^"]*"'),
      (m) => '"${m.group(1)}":"<REDACTADO>"',
    ),

    (
      RegExp(
        r'(authorization|apikey|x-api-key)\s*[:=]\s*[^,}\]\r\n]+',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}: <REDACTADO>',
    ),

    (
      RegExp(
        r'(X-Amz-Signature|X-Amz-Credential|X-Amz-Security-Token)=[^&\s"]+',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}=<REDACTADO>',
    ),

    (
      RegExp(r'[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})'),
      (m) => '<correo>@${m.group(1)}',
    ),
  ];
}
