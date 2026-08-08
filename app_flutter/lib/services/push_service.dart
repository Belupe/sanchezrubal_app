import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import 'log_service.dart';

/// Notificaciones push (FCM). La tabla `device_tokens` guarda el token por
/// usuario; el envío lo hace la Edge Function `send-push` (FCM HTTP v1).
class PushService {
  /// Abre los ajustes de notificaciones del sistema para esta app.
  ///
  /// Es el único camino cuando alguien ya ha dicho que no: la ventana del
  /// sistema no se puede volver a mostrar desde la app.
  ///
  /// Se resuelve con `url_launcher`, que ya era dependencia, en vez de añadir
  /// un paquete solo para esto: cualquier dependencia nueva obliga a recompilar
  /// iOS y macOS a la vez por el Package.resolved de SPM.
  ///
  /// Devuelve false si no se pudo abrir; entonces solo queda [comoActivarlo].
  static Future<bool> abrirAjustes() async {
    final destino = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'app-settings:',
      TargetPlatform.macOS =>
        'x-apple.systempreferences:com.apple.preference.notifications',
      // En Android no hay un esquema de URL para esto: se lanza el intent por
      // su sintaxis textual, que url_launcher entrega al sistema tal cual.
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

  /// Última respuesta del sistema al pedir permiso, o null si aún no se ha
  /// preguntado (o la plataforma no admite push).
  static AuthorizationStatus? permiso;

  /// Si esta plataforma puede recibir push. En Windows y Linux, Flutter no
  /// tiene push nativo: no hay permiso que pedir ni ventana que enseñar, así
  /// que a esa gente solo la alcanza el correo.
  static bool get plataformaSoportada =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Si de verdad van a llegar avisos. `provisional` cuenta: iOS lo concede sin
  /// preguntar y las entrega en silencio, que es mejor que nada.
  static bool get permitido =>
      permiso == AuthorizationStatus.authorized ||
      permiso == AuthorizationStatus.provisional;

  /// Qué hacer cuando el permiso está denegado.
  ///
  /// El sistema **solo enseña la ventana una vez**. A partir de ahí,
  /// `requestPermission()` devuelve la respuesta guardada sin mostrar nada, así
  /// que insistir desde la app no sirve de nada: el único camino son los
  /// ajustes del sistema.
  static String get comoActivarlo => switch (defaultTargetPlatform) {
        TargetPlatform.iOS =>
          'Ajustes → Portal Familia → Notificaciones → Permitir notificaciones.',
        TargetPlatform.macOS =>
          'Ajustes del Sistema → Notificaciones → Portal Familia → Permitir notificaciones.',
        TargetPlatform.android =>
          'Ajustes → Aplicaciones → Portal Familia → Notificaciones.',
        _ => 'Esta plataforma no admite notificaciones.',
      };

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
      // Esto es lo que hace salir la ventana del sistema, y solo sale UNA vez
      // en la vida de la instalación. Se pide en cada arranque a propósito: si
      // ya está contestada, el sistema devuelve la respuesta guardada sin
      // molestar, y así se detecta cuando alguien la ha desactivado después
      // desde los ajustes.
      final resp = await messaging.requestPermission();
      permiso = resp.authorizationStatus;
      if (!permitido) {
        // Sin permiso no habrá token, así que no tiene sentido seguir. Se deja
        // dicho con claridad porque es la única pista que tendrá el usuario.
        estado = 'Desactivadas. Los avisos llegarán por correo. $comoActivarlo';
        LogService.evento('Push: permiso ${resp.authorizationStatus.name}');
        return;
      }
      estado = 'Permiso concedido. Pidiendo token…';

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
