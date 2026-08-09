// SUSTITUTO PARA LAS CAPTURAS — no forma parte de la app que se publica.
//
// El original descarga e instala paquetes con `dart:io` + path_provider, que no
// existen en el navegador. `UpdateChannel` y `UpdateInfo` se copian tal cual
// porque UpdateScreen los usa; el servicio queda inerte (iOS nunca se
// auto-actualiza por esta vía: va por App Store).
//
// Ver scripts/screenshots/README.md.
import 'package:flutter/material.dart';

/// Cómo puede actualizarse esta instalación.
enum UpdateChannel {
  windows,
  linuxAppImage,
  linuxUsuario,
  linuxSistema,
  soloAvisar,
}

/// Datos de una actualización disponible.
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
  /// En las capturas nunca hay actualización pendiente: si la hubiera, la
  /// UpdateScreen taparía la pantalla que queremos fotografiar.
  static Future<void> checkForUpdate(BuildContext context,
      {bool force = false}) async {}

  static Future<void> abrirPaginaDeDescargas() async {}

  static Future<String?> downloadVerifyInstall(
          UpdateInfo info, void Function(double) onProgress) async =>
      null;

  @visibleForTesting
  static bool esUrlDeConfianza(String url) => false;
}
