import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log_service.dart';

/// Integración con el escritorio de Linux **para el AppImage**.
///
/// Un AppImage es un fichero suelto: no instala nada, así que el sistema no
/// sabe que existe y —lo importante aquí— **no hay ningún `.desktop` que
/// declare el esquema `portalfamilia://`**, con lo que los enlaces de los
/// correos no abrirían la app. El `.deb` y `instalar.sh` sí lo instalan ellos;
/// el AppImage se registra solo la primera vez que se abre.
///
/// Es el equivalente al bloque `[Registry]` del instalador de Windows
/// (`scripts/windows-installer.iss`).
///
/// Todo va en `try/catch`: si el escritorio no coopera, la app funciona igual
/// (solo se pierde abrir desde los enlaces del correo).
class LinuxDesktopIntegration {
  static const _appId = 'net.sanchezrubal.portal_familia';
  static const _esquema = 'x-scheme-handler/portalfamilia';

  /// Escribe el `.desktop` y el icono en `~/.local/share/` si hace falta.
  /// No hace nada fuera de Linux ni si no estamos ejecutando un AppImage.
  static Future<void> registrarSiHaceFalta() async {
    if (kIsWeb || !Platform.isLinux) return;

    final appImage = Platform.environment['APPIMAGE'];
    if (appImage == null || appImage.isEmpty) return; // .deb o .tar.gz: ya está

    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;
      final datos = Platform.environment['XDG_DATA_HOME']?.isNotEmpty == true
          ? Platform.environment['XDG_DATA_HOME']!
          : '$home/.local/share';

      final destino = File('$datos/applications/$_appId.desktop');
      final contenido = _plantillaDesktop(appImage);

      // Reescribir solo si cambió (el AppImage puede haberse movido de sitio).
      if (destino.existsSync() && destino.readAsStringSync() == contenido) {
        return;
      }

      Directory('$datos/applications').createSync(recursive: true);
      _copiarIcono(datos);
      destino.writeAsStringSync(contenido, flush: true);

      // Refrescar la base de datos y declararnos dueños del esquema. Si estos
      // binarios no están (sistema muy pelado), el .desktop ya escrito suele
      // bastar en la mayoría de escritorios.
      await _ejecutar('update-desktop-database', ['$datos/applications']);
      await _ejecutar('xdg-mime', ['default', '$_appId.desktop', _esquema]);

      LogService.evento('Escritorio: registrado $_appId.desktop para $appImage');
    } catch (e, s) {
      LogService.error(e, s, 'LinuxDesktopIntegration');
    }
  }

  /// El icono se **copia**, no se enlaza: `$APPDIR` es el punto de montaje
  /// FUSE del AppImage y desaparece en cuanto se cierra la app, así que un
  /// symlink dejaría el icono roto.
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
Categories=Utility;Office;
Terminal=false
StartupWMClass=$_appId
MimeType=$_esquema;
''';

  static Future<void> _ejecutar(String cmd, List<String> args) async {
    try {
      await Process.run(cmd, args);
    } catch (_) {
      // Binario ausente: no es motivo para molestar al usuario.
    }
  }
}
