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

  /// Cuántas veces se pregunta por el token de APNs antes de rendirse, con 2 s
  /// entre intentos: 30 × 2 s = un minuto de margen. El valor anterior (10 s)
  /// se quedaba corto en un primer registro.
  static const _intentosApns = 30;

  /// Qué pasó en el último [init], para enseñarlo en Configuración →
  /// Diagnóstico. Sin esto, un fallo de push es invisible: la app sigue
  /// funcionando y el error solo quedaba en un registro que en móvil no se
  /// podía sacar.
  static String estado = 'Sin iniciar.';

  /// Inicializa FCM y registra el token. Llamar tras el login.
  ///
  /// Es defensivo: solo en Android/iOS, y si Firebase aún no está configurado
  /// (faltan google-services.json / GoogleService-Info.plist) se desactiva sin
  /// romper la app. Requiere `flutterfire configure` y la config nativa.
  static Future<void> init() async {
    if (kIsWeb) return;
    const soportadas = {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    };
    if (!soportadas.contains(defaultTargetPlatform)) {
      estado = 'No aplica en esta plataforma.';
      return; // Windows/Linux: Flutter no tiene push nativo ahí.
    }
    // iOS y macOS van los DOS por APNs, así que comparten toda la espera del
    // token de APNs de más abajo. Es la razón de que esto sea "esApple" y no
    // "esIOS": en macOS, sin esa espera, el primer registro se queda igual de
    // colgado que se quedaba en el iPhone.
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
      final permiso = await messaging.requestPermission();
      estado = 'Permiso: ${permiso.authorizationStatus.name}. Pidiendo token…';

      // El listener se registra ANTES de pedir el token, no después: si
      // getToken() falla, esta suscripción es la única vía por la que el token
      // puede llegar más tarde. Registrándola después, un fallo de getToken()
      // dejaba el dispositivo sin push para siempre.
      messaging.onTokenRefresh.listen((t) => saveToken(t, platform: platform));

      // Apple (iOS y macOS): FCM no puede emitir su token hasta que APNs ha
      // entregado el suyo al dispositivo. En un PRIMER registro eso puede tardar
      // bastante más de lo que uno espera —hasta minutos con mala cobertura—,
      // así que se espera con margen. No bloquea nada: init() se llama sin await
      // desde HomeShell.
      //
      // Cada llamada lleva su propio timeout porque getAPNSToken() puede
      // quedarse colgada sin devolver ni token ni null: visto en un iPhone real,
      // dejaba el estado en "Pidiendo token…" para siempre y el bucle de espera
      // ni siquiera empezaba a contar.
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
          // No es fatal: si APNs responde más tarde, onTokenRefresh lo recoge.
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
      // Deja rastro en el registro de diagnóstico: antes solo iba a debugPrint,
      // que no se ve en una build de release, y cualquier fallo se leía como
      // "Firebase no configurado" aunque fuese otra cosa. Push desactivado no
      // bloquea la app.
      estado = 'Error: $e';
      LogService.error(e, t, 'PushService.init');
    }
  }
}
