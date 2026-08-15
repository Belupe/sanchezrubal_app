import 'dart:io';
import 'package:flutter/foundation.dart';
import 'log_service.dart';

class LinuxDesktopIntegration {
  static const _appId = 'net.sanchezrubal.portal_familia';
  static const _esquema = 'x-scheme-handler/portalfamilia';

  static Future<void> registrarSiHaceFalta() async {
    if (kIsWeb || !Platform.isLinux) return;

    final appImage = Platform.environment['APPIMAGE'];
    if (appImage == null || appImage.isEmpty) return;

    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;
      final datos = Platform.environment['XDG_DATA_HOME']?.isNotEmpty == true
          ? Platform.environment['XDG_DATA_HOME']!
          : '$home/.local/share';

      final destino = File('$datos/applications/$_appId.desktop');
      final contenido = _plantillaDesktop(appImage);

      if (destino.existsSync() && destino.readAsStringSync() == contenido) {
        return;
      }

      Directory('$datos/applications').createSync(recursive: true);
      _copiarIcono(datos);
      destino.writeAsStringSync(contenido, flush: true);

      await _ejecutar('update-desktop-database', ['$datos/applications']);
      await _ejecutar('xdg-mime', ['default', '$_appId.desktop', _esquema]);

      LogService.evento('Escritorio: registrado $_appId.desktop para $appImage');
    } catch (e, s) {
      LogService.error(e, s, 'LinuxDesktopIntegration');
    }
  }

  static void _copiarIcono(String datos) {
    final appDir = Platform.environment['APPDIR'];
    if (appDir == null || appDir.isEmpty) return;
    for (final origen in [
      '$appDir/usr/share/icons/hicolor/256x256/apps/$_appId.png',
      '$appDir/$_appId.png',
    ]) {
      final f = File(origen);
      if (!f.existsSync()) continue;
      final dir = Directory('$datos/icons/hicolor/256x256/apps');
      dir.createSync(recursive: true);
      f.copySync('${dir.path}/$_appId.png');
      return;
    }
  }

  static String _plantillaDesktop(String appImage) => '''
[Desktop Entry]
Type=Application
Name=Portal Familia
Comment=Gestión de casas familiares
Exec=$appImage %u
Icon=$_appId
Categories=Office;Calendar;
Terminal=false
StartupWMClass=$_appId
MimeType=$_esquema;
''';

  static Future<void> _ejecutar(String cmd, List<String> args) async {
    try {
      await Process.run(cmd, args);
    } catch (_) {
    }
  }
}
