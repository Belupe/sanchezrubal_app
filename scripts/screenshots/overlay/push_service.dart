// SUSTITUTO PARA LAS CAPTURAS — no forma parte de la app que se publica.
//
// El original arranca Firebase y pide el permiso de notificaciones. En la
// compilación web de las capturas no hay proyecto Firebase configurado, y
// además la franja "activa las notificaciones" saldría en TODAS las capturas.
// `plataformaSoportada = false` la deja oculta, que es justo lo que se ve en un
// iPhone con los avisos ya concedidos.
//
// Ver scripts/screenshots/README.md.
import 'package:flutter/foundation.dart';

class PushService {
  static String estado = 'Activadas.';

  static final ValueNotifier<bool?> avisosActivos = ValueNotifier(null);

  static bool get plataformaSoportada => false;

  static bool get permitido => true;

  static String get comoActivarlo =>
      'Ajustes → Portal Familia → Notificaciones.';

  static Future<bool> abrirAjustes() async => false;

  static Future<void> init() async {}

  static Future<void> saveToken(String token,
      {String platform = 'ios'}) async {}
}
