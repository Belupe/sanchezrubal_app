import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../main.dart';

/// Notificaciones push (FCM). La tabla `device_tokens` guarda el token por
/// usuario; el envío lo hace la Edge Function `send-push` (FCM HTTP v1).
class PushService {
  /// Guarda el token de push del dispositivo para el usuario actual.
  static Future<void> saveToken(String token, {String platform = 'android'}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    await supabase.from('device_tokens').upsert(
      {'user_id': uid, 'token': token, 'platform': platform},
      onConflict: 'user_id,token',
    );
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
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final platform =
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      final token = await messaging.getToken();
      if (token != null) await saveToken(token, platform: platform);
      messaging.onTokenRefresh.listen((t) => saveToken(t, platform: platform));
    } catch (e) {
      // Firebase no configurado todavía: push desactivado (no bloquea la app).
      debugPrint('Push desactivado (Firebase no configurado): $e');
    }
  }
}
