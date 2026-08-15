// Auto-actualización: solo del propio dominio y con hash SHA-256 verificado
// antes de instalar.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../screens/update_screen.dart';
import 'log_service.dart';

enum UpdateChannel {
  windows,

  linuxAppImage,

  linuxUsuario,

  linuxSistema,

  soloAvisar,
}

class UpdateInfo {
  final String versionName;
  final String url;
  final String sha256;
  final String notes;
  final bool mandatory;
  final UpdateChannel channel;

  const UpdateInfo({
    required this.versionName,
    required this.url,
    required this.sha256,
    required this.notes,
    required this.mandatory,
    required this.channel,
  });

  bool get puedeInstalarSola => channel != UpdateChannel.soloAvisar;

  bool get pideContrasena => channel == UpdateChannel.linuxSistema;
}

class UpdateService {
  static bool _checked = false;
  static Map<String, dynamic>? _manifiesto;

  static String? get _appImage {
    final p = Platform.environment['APPIMAGE'];
    if (p == null || p.isEmpty) return null;
    return File(p).existsSync() ? p : null;
  }

  static Map<String, dynamic>? get _infoInstalacion {
    if (_manifiesto != null) return _manifiesto;
    try {
      final dir = File(Platform.resolvedExecutable).parent;
      final f = File('${dir.path}/install-info.json');
      if (!f.existsSync()) return null;
      _manifiesto = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return _manifiesto;
    } catch (_) {
      return null;
    }
  }

  static UpdateChannel? get _channel {
    if (kIsWeb) return null;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return UpdateChannel.windows;
    }
    if (defaultTargetPlatform != TargetPlatform.linux) {
      return null;
    }
    if (_appImage != null) return UpdateChannel.linuxAppImage;

    switch (_infoInstalacion?['modo']) {
      case 'sistema':
        return UpdateChannel.linuxSistema;
      case 'usuario':

        return _esEscribible(File(Platform.resolvedExecutable).parent.path)
            ? UpdateChannel.linuxUsuario
            : UpdateChannel.soloAvisar;
      default:

        return UpdateChannel.soloAvisar;
    }
  }

  static String get _carpetaCanal =>
      defaultTargetPlatform == TargetPlatform.windows ? 'windows' : 'linux';

  static bool _esEscribible(String ruta) {
    try {
      final sonda = File('$ruta/.pf-escritura-${DateTime.now().microsecondsSinceEpoch}');
      sonda.writeAsStringSync('x');
      sonda.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static bool esUrlDeConfianza(String url) => _isTrustedUrl(url);

  static bool _isTrustedUrl(String url) {
    final u = Uri.tryParse(url);
    final base = Uri.tryParse(AppConfig.updateBaseUrl);
    if (u == null || base == null) return false;
    return u.scheme == 'https' && u.host.isNotEmpty && u.host == base.host;
  }

  static Future<void> checkForUpdate(BuildContext context,
      {bool force = false}) async {
    final canal = _channel;
    if (!AppConfig.enableSelfUpdate || canal == null) return;
    if (_checked && !force) return;
    _checked = true;

    final Map<String, dynamic> remote;
    final int currentCode;
    try {
      final info = await PackageInfo.fromPlatform();
      currentCode = int.tryParse(info.buildNumber) ?? 0;

      final res = await Dio().get<Map<String, dynamic>>(
        '${AppConfig.updateBaseUrl}/$_carpetaCanal/version.json',
        options: Options(
          responseType: ResponseType.json,
          headers: {'Cache-Control': 'no-cache'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      remote = res.data ?? const {};
    } catch (_) {
      return;
    }

    final remoteCode = (remote['versionCode'] as num?)?.toInt() ?? 0;
    if (remoteCode <= currentCode) return;

    final esDeb = canal == UpdateChannel.linuxSistema;
    final url = (esDeb ? remote['urlDeb'] : remote['url'])?.toString();
    final sha = (esDeb ? remote['sha256Deb'] : remote['sha256'])
        ?.toString()
        .trim();
    if (!context.mounted) return;

    final valido = url != null &&
        url.isNotEmpty &&
        _isTrustedUrl(url) &&
        sha != null &&
        sha.isNotEmpty;
    if (!valido) {
      LogService.evento(
          'Actualización sin URL de confianza o sin hash: solo se avisa.');
    }

    final info = UpdateInfo(
      versionName: remote['versionName']?.toString() ?? '',
      url: valido ? url : AppConfig.updateBaseUrl,
      sha256: valido ? sha : '',
      notes: remote['notes']?.toString() ?? '',
      mandatory: remote['mandatory'] == true,
      channel: valido ? canal : UpdateChannel.soloAvisar,
    );

    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UpdateScreen(info: info),
      fullscreenDialog: true,
    ));
  }

  static Future<void> abrirPaginaDeDescargas() async {
    final u = Uri.tryParse(AppConfig.updateBaseUrl);
    if (u == null) return;
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (e, s) {
      LogService.error(e, s, 'abrir página de descargas');
    }
  }

  static Future<String?> downloadVerifyInstall(
      UpdateInfo info, void Function(double) onProgress) async {
    if (!info.puedeInstalarSola) {
      await abrirPaginaDeDescargas();
      return null;
    }

    final Directory base;
    try {
      final appImage = info.channel == UpdateChannel.linuxAppImage
          ? File(_appImage!)
          : null;
      base = appImage?.parent ?? await getTemporaryDirectory();
    } catch (e) {
      return 'No se pudo preparar la actualización: $e';
    }

    final rnd = Random.secure();
    final token = List<int>.generate(16, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final downloadDir = Directory('${base.path}/.update-$token');

    final String filePath;
    try {
      downloadDir.createSync(recursive: true);
      filePath = '${downloadDir.path}/${_nombreDescarga(info.channel)}';

      await Dio().download(
        info.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress(received / total);
        },
        options: Options(receiveTimeout: const Duration(minutes: 5)),
      );
    } catch (e) {
      _limpiar(downloadDir);
      LogService.error(e, StackTrace.current, 'descarga de actualización');
      if (info.channel == UpdateChannel.linuxAppImage) {
        return 'No se pudo escribir junto a la app. Mueve Portal Familia a una '
            'carpeta tuya (por ejemplo ~/Aplicaciones) y vuelve a intentarlo, '
            'o descarga la versión nueva desde ${AppConfig.updateBaseUrl}.';
      }
      return 'No se pudo descargar la actualización: $e';
    }

    bool hashOk;
    try {
      final bytes = await File(filePath).readAsBytes();
      hashOk = sha256.convert(bytes).toString().toLowerCase() ==
          info.sha256.toLowerCase();
    } catch (_) {
      hashOk = false;
    }
    if (!hashOk) {
      _limpiar(downloadDir);
      LogService.evento('Actualización descartada: el SHA-256 no coincide.');
      return 'Actualización descartada: la verificación de seguridad falló.';
    }

    switch (info.channel) {
      case UpdateChannel.windows:
        return _instalarWindows(filePath);
      case UpdateChannel.linuxAppImage:
        return _instalarAppImage(filePath, downloadDir);
      case UpdateChannel.linuxUsuario:
        return _instalarUsuario(filePath, downloadDir);
      case UpdateChannel.linuxSistema:
        return _instalarSistema(filePath, downloadDir);
      case UpdateChannel.soloAvisar:
        return null;
    }
  }

  static String _nombreDescarga(UpdateChannel c) => switch (c) {
        UpdateChannel.windows => 'portal-familia-setup.exe',
        UpdateChannel.linuxSistema => 'portal-familia.deb',
        UpdateChannel.linuxAppImage => 'portal-familia.AppImage',
        _ => 'portal-familia.tar.gz',
      };

  static void _limpiar(Directory d) {
    try {
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }

  static Future<String?> _instalarWindows(String filePath) async {
    await Process.start(filePath, const [], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    exit(0);
  }

  static Future<String?> _instalarAppImage(
      String filePath, Directory downloadDir) async {
    final destino = _appImage;
    if (destino == null) return 'No se encontró el AppImage en ejecución.';
    try {
      final nuevo = File(filePath);

      await nuevo.rename(destino);
      await Process.run('chmod', ['0755', destino]);
      _limpiar(downloadDir);
    } catch (e) {
      _limpiar(downloadDir);
      LogService.error(e, StackTrace.current, 'reemplazo del AppImage');
      return 'No se pudo reemplazar la app: $e';
    }
    await _relanzar([destino]);
    return null;
  }

  static Future<String?> _instalarUsuario(
      String filePath, Directory downloadDir) async {
    final prefijo = _infoInstalacion?['prefijo']?.toString();
    if (prefijo == null) return 'No sé dónde está instalada la app.';
    try {
      final extraido = Directory('${downloadDir.path}/x')..createSync();
      final r = await Process.run(
          'tar', ['xzf', filePath, '-C', extraido.path, '--strip-components=1']);
      if (r.exitCode != 0) return 'No se pudo descomprimir: ${r.stderr}';

      for (final e in extraido.listSync()) {
        final nombre = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (nombre == 'instalar.sh') continue;
        final destino = '$prefijo/$nombre';
        if (e is Directory) {
          await Process.run('cp', ['-a', '-T', e.path, destino]);
        } else {
          await File(e.path).copy(destino);
        }
      }
      await Process.run('chmod', ['0755', '$prefijo/portal_familia']);
      _limpiar(downloadDir);
    } catch (e) {
      _limpiar(downloadDir);
      LogService.error(e, StackTrace.current, 'actualización de usuario');
      return 'No se pudo actualizar: $e';
    }
    await _relanzar(['$prefijo/portal_familia']);
    return null;
  }

  static Future<String?> _instalarSistema(
      String filePath, Directory downloadDir) async {
    final intentos = <List<String>>[
      ['pkexec', '/usr/bin/apt-get', 'install', '-y', '--reinstall', filePath],
      ['pkexec', '/usr/bin/dpkg', '-i', filePath],
    ];

    ProcessResult? ultimo;
    for (final cmd in intentos) {
      try {
        ultimo = await Process.run(cmd.first, cmd.sublist(1),
            environment: {'DEBIAN_FRONTEND': 'noninteractive'});
      } catch (e) {
        LogService.error(e, StackTrace.current, 'pkexec');
        continue;
      }
      if (ultimo.exitCode == 0) {
        _limpiar(downloadDir);
        await _relanzar(['/opt/portal-familia/portal_familia']);
        return null;
      }

      if (ultimo.exitCode == 126) {
        _limpiar(downloadDir);
        return 'Actualización cancelada: hace falta la contraseña de '
            'administrador para instalarla.';
      }
      if (ultimo.exitCode == 127) break;
    }

    _limpiar(downloadDir);
    LogService.evento(
        'No se pudo instalar el .deb (pkexec: ${ultimo?.exitCode}).');
    return 'No se pudo instalar la actualización automáticamente. '
        'Descárgala desde ${AppConfig.updateBaseUrl} e instálala con:\n'
        'sudo apt install ./portal-familia_amd64.deb';
  }

  static Future<void> _relanzar(List<String> cmd) async {
    try {
      await Process.start(
        '/bin/sh',
        ['-c', 'sleep 1; exec "\$0" "\$@"', ...cmd],
        mode: ProcessStartMode.detached,
      );
    } catch (e, s) {
      LogService.error(e, s, 'relanzar tras actualizar');
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    exit(0);
  }
}
