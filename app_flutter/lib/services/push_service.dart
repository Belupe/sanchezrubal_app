import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../main.dart';
import 'log_service.dart';

/// Notificaciones push (FCM). La tabla `device_tokens` guarda el token por
/// usuario; el envío lo hace la Edge Function `send-push` (FCM HTTP v1).
class PushService {
  /// Guarda el token de push del dispositivo para el usuario actual.
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

  /// Inicializa FCM y registra el token. Llamar tras el login.
  ///
  /// Es defensivo: solo en Android/iOS, y si Firebase aún no está configurado
  /// (faltan google-services.json / GoogleService-Info.plist) se desactiva sin
  /// romper la app. Requiere `flutterfire configure` y la config nativa.
  static Future<void> init() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return; // Windows/macOS/Linux: sin push nativo.
    }
    final esIOS = defaultTargetPlatform == TargetPlatform.iOS;
    final platform = esIOS ? 'ios' : 'android';
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      // El listener se registra ANTES de pedir el token, no después: si
      // getToken() falla, esta suscripción es la única vía por la que el token
      // puede llegar más tarde. Registrándola después, un fallo de getToken()
      // dejaba el dispositivo sin push para siempre.
      messaging.onTokenRefresh.listen((t) => saveToken(t, platform: platform));

      // iOS: FCM no puede emitir su token hasta que APNs ha entregado el suyo
      // al dispositivo, y eso tarda un momento tras aceptar el permiso. Pedirlo
      // antes hace que getToken() lance 'apns-token-not-set'. Se espera con
      // reintentos cortos en vez de asumir que ya está.
      if (esIOS) {
        var apns = await messaging.getAPNSToken();
        for (var i = 0; apns == null && i < 10; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          apns = await messaging.getAPNSToken();
        }
        if (apns == null) {
          // No es fatal: si APNs responde más tarde, onTokenRefresh lo recoge.
          LogService.evento(
            'Push: APNs no entregó su token en 10 s; se espera a onTokenRefresh.',
          );
          return;
        }
      }

      final token = await messaging.getToken();
      if (token != null) await saveToken(token, platform: platform);
    } catch (e, t) {
      // Deja rastro en el registro de diagnóstico: antes solo iba a debugPrint,
      // que no se ve en una build de release, y cualquier fallo se leía como
      // "Firebase no configurado" aunque fuese otra cosa. Push desactivado no
      // bloquea la app.
      LogService.error(e, t, 'PushService.init');
    }
  }
}
