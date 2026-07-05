import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../screens/update_screen.dart';

/// Datos de una actualización disponible (Windows self-hosted).
class UpdateInfo {
  final String versionName;
  final String url;
  final String sha256;
  final String notes;
  final bool mandatory;
  const UpdateInfo({
    required this.versionName,
    required this.url,
    required this.sha256,
    required this.notes,
    required this.mandatory,
  });
}

/// Auto-actualización de la app de **Windows** (único canal self-hosted).
///
/// Consulta `${AppConfig.updateBaseUrl}/windows/version.json`. Si el
/// `versionCode` remoto es mayor que el instalado, abre la [UpdateScreen], que
/// descarga el `setup.exe`, **verifica su SHA-256** [C-02] y lo instala sola.
///
/// Android se actualiza por **Google Play** e iOS por el **App Store**: no usan
/// este mecanismo (en esas plataformas no hace nada).
class UpdateService {
  static bool _checked = false;

  static bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// [C-02] Solo se confía en URLs `https` del MISMO host que
  /// `AppConfig.updateBaseUrl`. Rechaza http, otros dominios o URLs malformadas
  /// → cierra el vector de RCE de redirigir la actualización a un binario ajeno.
  static bool _isTrustedUrl(String url) {
    final u = Uri.tryParse(url);
    final base = Uri.tryParse(AppConfig.updateBaseUrl);
    if (u == null || base == null) return false;
    return u.scheme == 'https' && u.host.isNotEmpty && u.host == base.host;
  }

  /// Comprueba si hay versión nueva y, si la hay, abre la pantalla de
  /// actualización. Pensado para llamarse una vez tras el login. Silencioso
  /// ante errores de red.
  static Future<void> checkForUpdate(BuildContext context,
      {bool force = false}) async {
    // Solo Windows tiene auto-update self-hosted (Android=Play, iOS=App Store).
    if (!AppConfig.enableSelfUpdate || !_isWindows) return;
    if (_checked && !force) return;
    _checked = true;

    final Map<String, dynamic> remote;
    final int currentCode;
    try {
      final info = await PackageInfo.fromPlatform();
      currentCode = int.tryParse(info.buildNumber) ?? 0;

      final res = await Dio().get<Map<String, dynamic>>(
        '${AppConfig.updateBaseUrl}/windows/version.json',
        options: Options(
          responseType: ResponseType.json,
          headers: {'Cache-Control': 'no-cache'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      remote = res.data ?? const {};
    } catch (_) {
      return; // sin red o sin servidor: no molestamos al usuario.
    }

    final remoteCode = (remote['versionCode'] as num?)?.toInt() ?? 0;
    if (remoteCode <= currentCode) return;

    final url = remote['url']?.toString();
    final sha256Hex = remote['sha256']?.toString().trim();
    if (url == null || url.isEmpty || !context.mounted) return;
    // [C-02] Solo una descarga HTTPS del propio dominio de updates y con hash
    // SHA-256 declarado. Cualquier otra cosa se descarta en silencio.
    if (!_isTrustedUrl(url) || sha256Hex == null || sha256Hex.isEmpty) {
      debugPrint('Actualización rechazada: URL no confiable o sin hash.');
      return;
    }

    final info = UpdateInfo(
      versionName: remote['versionName']?.toString() ?? '',
      url: url,
      sha256: sha256Hex,
      notes: remote['notes']?.toString() ?? '',
      mandatory: remote['mandatory'] == true,
    );

    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UpdateScreen(info: info),
      fullscreenDialog: true,
    ));
  }

  /// Descarga el instalador en un directorio aleatorio, **verifica el SHA-256**
  /// [C-02] y lo lanza (Windows), cerrando la app para que el instalador
  /// reemplace los archivos y la relance. Reporta progreso por [onProgress].
  /// Devuelve un mensaje de error, o null si va a instalar (la app se cierra).
  static Future<String?> downloadVerifyInstall(
      UpdateInfo info, void Function(double) onProgress) async {
    final String filePath;
    try {
      final dir = await getTemporaryDirectory();
      // [B-11] Descarga en un SUBDIRECTORIO ALEATORIO (nombre impredecible,
      // 16 bytes CSPRNG) creado en exclusiva para esta actualización: cierra el
      // TOCTOU de una ruta fija/predecible.
      final rnd = Random.secure();
      final token = List<int>.generate(16, (_) => rnd.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final downloadDir = Directory('${dir.path}/update-$token');
      await downloadDir.create(recursive: true);
      filePath = '${downloadDir.path}/portal-familia-setup.exe';

      await Dio().download(
        info.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress(received / total);
        },
        options: Options(receiveTimeout: const Duration(minutes: 5)),
      );
    } catch (e) {
      return 'No se pudo descargar la actualización: $e';
    }

    // [C-02] Verifica el hash SHA-256 del binario descargado ANTES de ejecutarlo.
    bool hashOk;
    try {
      final bytes = await File(filePath).readAsBytes();
      hashOk = sha256.convert(bytes).toString().toLowerCase() ==
          info.sha256.toLowerCase();
    } catch (_) {
      hashOk = false;
    }
    if (!hashOk) {
      try {
        await File(filePath).delete();
      } catch (_) {}
      return 'Actualización descartada: la verificación de seguridad falló.';
    }

    // Lanza el instalador (que cierra/reemplaza/relanza) y sale para liberar
    // los archivos de la app.
    await Process.start(filePath, const [], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    exit(0);
  }
}
