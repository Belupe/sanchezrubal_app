// Notificaciones push (FCM) y gestión del permiso del sistema.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import 'log_service.dart';

class PushService {
  static Future<bool> abrirAjustes() async {
    final destino = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'app-settings:',
      TargetPlatform.macOS =>
        'x-apple.systempreferences:com.apple.preference.notifications',

      TargetPlatform.android =>
        'intent://#Intent;action=android.settings.APP_NOTIFICATION_SETTINGS;'
            'S.android.provider.extra.APP_PACKAGE=net.sanchezrubal.portal_familia;end',
      _ => null,
    };
    if (destino == null) return false;
    try {
      return await launchUrl(Uri.parse(destino));
    } catch (e, t) {
      LogService.error(e, t, 'PushService.abrirAjustes');
      return false;
    }
  }

  static Future<void> saveToken(
    String token, {
    String platform = 'android',
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    await supabase.from('device_tokens').upsert({
      'user_id': uid,
      'token': token,
      'platform': platform,
    }, onConflict: 'user_id,token');
  }

  static const _intentosApns = 30;

  static String estado = 'Sin iniciar.';

  static final ValueNotifier<bool?> avisosActivos = ValueNotifier(null);

  static bool get plataformaSoportada =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static bool get permitido => avisosActivos.value == true;

  static String get comoActivarlo => switch (defaultTargetPlatform) {
        TargetPlatform.iOS =>
          'Ajustes → Portal Familia → Notificaciones → Permitir notificaciones.',
        TargetPlatform.macOS =>
          'Ajustes del Sistema → Notificaciones → Portal Familia → Permitir notificaciones.',
        TargetPlatform.android =>
          'Ajustes → Aplicaciones → Portal Familia → Notificaciones.',
        _ => 'Esta plataforma no admite notificaciones.',
      };

  static Future<void> init() async {
    if (kIsWeb) return;
    const soportadas = {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    };
    if (!soportadas.contains(defaultTargetPlatform)) {
      estado = 'No aplica en esta plataforma.';
      return;
    }

    final esApple = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      _ => 'android',
    };
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;

      final resp = await messaging.requestPermission();

      avisosActivos.value =
          resp.authorizationStatus == AuthorizationStatus.authorized ||
              resp.authorizationStatus == AuthorizationStatus.provisional;
      if (!permitido) {
        estado = 'Desactivadas. Los avisos llegarán por correo. $comoActivarlo';
        LogService.evento('Push: permiso ${resp.authorizationStatus.name}');
        return;
      }
      estado = 'Permiso concedido. Pidiendo token…';

      messaging.onTokenRefresh.listen((t) => saveToken(t, platform: platform));

      if (esApple) {
        String? apns;
        for (var i = 0; i < _intentosApns; i++) {
          apns = await messaging.getAPNSToken().timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );
          if (apns != null) break;
          estado = 'Esperando token de APNs… (${i + 1}/$_intentosApns)';
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        if (apns == null) {
          estado =
              'APNs no entregó su token en ${_intentosApns * 2} s. Suele ser '
              'la red: APNs usa el puerto 5223 y algunas wifis lo bloquean. '
              '${defaultTargetPlatform == TargetPlatform.iOS ? 'Prueba con datos móviles.' : 'Prueba desde otra red.'}';
          LogService.evento('Push: $estado');
          return;
        }
      }

      final token = await messaging.getToken();
      if (token == null) {
        estado = 'FCM no devolvió token (getToken() = null).';
        LogService.evento('Push: $estado');
        return;
      }
      await saveToken(token, platform: platform);
      estado = 'Activo. Token registrado (${token.substring(0, 12)}…).';
      LogService.evento('Push: activo, token registrado.');
    } catch (e, t) {
      estado = 'Error: $e';
      LogService.error(e, t, 'PushService.init');
    }
  }
}
