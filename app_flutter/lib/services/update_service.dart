import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';

/// Auto-actualización de las apps de escritorio/móvil self-hosted.
///
/// Consulta `${AppConfig.updateBaseUrl}/<plataforma>/version.json`. Si el
/// `versionCode` remoto es mayor que el instalado, ofrece descargar e instalar
/// el nuevo paquete que sirve tu servidor Docker (servicio `updates`):
///   - **Android** → descarga el `.apk` y lanza el instalador del sistema.
///   - **Windows** → descarga el `setup.exe`, lo lanza y cierra la app para que
///     el instalador reemplace los archivos y la relance.
/// En **iOS/macOS/web no hace nada** (iOS se actualiza por TestFlight/App Store).
class UpdateService {
  static bool _checked = false;

  /// Carpeta de plataforma en el servidor de updates, o null si la plataforma
  /// no usa este mecanismo.
  static String? get _platform {
    if (kIsWeb) return null;
    if (defaultTargetPlatform == TargetPlatform.android) return 'android';
    if (defaultTargetPlatform == TargetPlatform.windows) return 'windows';
    return null;
  }

  /// Comprueba si hay versión nueva y, si la hay, ofrece instalarla. Pensado
  /// para llamarse una vez tras el login. Silencioso ante errores de red.
  static Future<void> checkForUpdate(BuildContext context,
      {bool force = false}) async {
    // Build de Google Play: el auto-update por APK va desactivado (política de
    // Play). Play actualiza a los usuarios por su cuenta. Ver docs/GOOGLE.md.
    if (!AppConfig.enableSelfUpdate) return;
    final platform = _platform;
    if (platform == null) return;
    if (_checked && !force) return;
    _checked = true;

    final Map<String, dynamic> remote;
    final int currentCode;
    try {
      final info = await PackageInfo.fromPlatform();
      currentCode = int.tryParse(info.buildNumber) ?? 0;

      final res = await Dio().get<Map<String, dynamic>>(
        '${AppConfig.updateBaseUrl}/$platform/version.json',
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

    final versionName = remote['versionName']?.toString() ?? '';
    final url = remote['url']?.toString();
    final notes = remote['notes']?.toString() ?? '';
    final mandatory = remote['mandatory'] == true;
    if (url == null || url.isEmpty || !context.mounted) return;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: !mandatory,
      builder: (ctx) => AlertDialog(
        title: Text(
            'Nueva versión${versionName.isNotEmpty ? ' $versionName' : ''}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hay una versión nueva de Portal Familia disponible.'),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(notes),
            ],
          ],
        ),
        actions: [
          if (!mandatory)
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ahora no'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );

    if (accepted != true || !context.mounted) return;
    await _downloadAndInstall(context, url, platform);
  }

  static Future<void> _downloadAndInstall(
      BuildContext context, String url, String platform) async {
    // Android exige permiso explícito para que una app instale paquetes.
    if (platform == 'android') {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Para actualizar, permite "Instalar apps desconocidas" para Portal Familia.'),
          ));
        }
        return;
      }
    }

    final progress = ValueNotifier<double>(0);
    if (context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Descargando actualización'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, p, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: p > 0 ? p : null),
                const SizedBox(height: 12),
                Text(p > 0 ? '${(p * 100).toStringAsFixed(0)} %' : 'Iniciando…'),
              ],
            ),
          ),
        ),
      );
    }

    final String filePath;
    try {
      final dir = await getTemporaryDirectory();
      final fileName = platform == 'windows'
          ? 'portal-familia-setup.exe'
          : 'portal-familia-update.apk';
      filePath = '${dir.path}/$fileName';
      final existing = File(filePath);
      if (await existing.exists()) await existing.delete();

      await Dio().download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) progress.value = received / total;
        },
        options: Options(receiveTimeout: const Duration(minutes: 5)),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // cierra el progreso
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo descargar la actualización: $e')),
        );
      }
      progress.dispose();
      return;
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // cierra el progreso
    }
    progress.dispose();

    if (platform == 'windows') {
      // Lanza el instalador (que cierra/reemplaza/relanza) y sale para liberar
      // los archivos de la app.
      await Process.start(filePath, const [],
          mode: ProcessStartMode.detached);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      exit(0);
    }

    // Android: lanza el instalador del sistema con el APK descargado.
    final result = await OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('No se pudo abrir el instalador: ${result.message}')),
      );
    }
  }
}
