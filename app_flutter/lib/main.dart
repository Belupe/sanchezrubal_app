import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/mfa_challenge_screen.dart';
import 'screens/auth/set_new_password_screen.dart';
import 'screens/home_shell.dart';
import 'services/deep_link_service.dart';
import 'services/mfa_service.dart';
import 'services/secure_session_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
    // [M-09] Sesión (JWT + refresh) y code_verifier PKCE cifrados en reposo.
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureSessionStorage(supabaseUrl: AppConfig.supabaseUrl),
      pkceAsyncStorage: const SecurePkceAsyncStorage(),
    ),
  );
  // [2M-04] Estado de "recuperación de contraseña pendiente". Debe sobrevivir a
  // un reinicio en frío: la sesión de recuperación se PERSISTE en disco, y al
  // reabrir la app supabase emite `initialSession` (no `passwordRecovery`), así
  // que además del evento en caliente se guarda un flag persistente cifrado.
  //  1) Al arrancar: si el flag está puesto y hay sesión, seguimos bloqueando;
  //     si el flag está puesto pero ya no hay sesión, se limpia (obsoleto).
  final pending = await _recoveryStore.read(key: _kPendingRecovery);
  if (pending == '1') {
    if (supabase.auth.currentSession != null) {
      passwordRecoveryNotifier.value = true;
    } else {
      await _recoveryStore.delete(key: _kPendingRecovery);
    }
  }
  //  2) En caliente: el enlace de recuperación puede abrir la app antes de que
  //     el AuthGate se suscriba; este listener global lo captura siempre.
  supabase.auth.onAuthStateChange.listen((state) async {
    if (state.event == AuthChangeEvent.passwordRecovery) {
      await _recoveryStore.write(key: _kPendingRecovery, value: '1');
      passwordRecoveryNotifier.value = true;
    } else if (state.event == AuthChangeEvent.signedOut) {
      await _recoveryStore.delete(key: _kPendingRecovery);
      passwordRecoveryNotifier.value = false;
    }
  });

  runApp(const PortalFamiliaApp());
}

/// Acceso global al cliente de Supabase.
final supabase = Supabase.instance.client;

/// [2M-04] Activo mientras haya una sesión de recuperación pendiente de fijar
/// una contraseña nueva. Lo consume el AuthGate para bloquear la app en
/// SetNewPasswordScreen. Se respalda en un flag persistente (ver abajo) para
/// que sobreviva a reinicios en frío.
final passwordRecoveryNotifier = ValueNotifier<bool>(false);

const _recoveryStore = FlutterSecureStorage();
const _kPendingRecovery = 'pending_pw_recovery';

/// [2M-04] Marca la recuperación como resuelta: borra el flag persistente y
/// desactiva el bloqueo. La llama SetNewPasswordScreen al fijar la contraseña.
Future<void> clearPasswordRecovery() async {
  await _recoveryStore.delete(key: _kPendingRecovery);
  passwordRecoveryNotifier.value = false;
}

/// Clave global del Navigator: permite abrir pantallas desde los deep links
/// (fuera del árbol de widgets).
final navigatorKey = GlobalKey<NavigatorState>();

/// Tema actual (lo cambia el usuario en Perfil; se persiste en ui_preferences).
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

ThemeMode themeModeFromString(String? s) {
  switch (s) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

String themeModeToString(ThemeMode m) {
  switch (m) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}

const _seed = Color(0xFF2563EB);

class PortalFamiliaApp extends StatefulWidget {
  const PortalFamiliaApp({super.key});

  @override
  State<PortalFamiliaApp> createState() => _PortalFamiliaAppState();
}

class _PortalFamiliaAppState extends State<PortalFamiliaApp> {
  @override
  void initState() {
    super.initState();
    DeepLinkService.init();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Portal Familia',
        debugShowCheckedModeBanner: false,
        locale: const Locale('es'),
        supportedLocales: const [Locale('es'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          colorSchemeSeed: _seed,
          brightness: Brightness.light,
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: _seed,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        themeMode: mode,
        home: const AuthGate(),
      ),
    );
  }
}

/// Muestra el login o la app según haya sesión activa.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, _) {
        final session = supabase.auth.currentSession;
        if (session == null) {
          // Sin sesión: no hay recuperación pendiente.
          passwordRecoveryNotifier.value = false;
          return const LoginScreen();
        }
        // [2M-04] La sesión de recuperación NO da acceso pleno: hasta fijar una
        // contraseña nueva, se muestra SetNewPasswordScreen (bloquea el resto).
        return ValueListenableBuilder<bool>(
          valueListenable: passwordRecoveryNotifier,
          builder: (context, recovering, __) {
            if (recovering) {
              // onDone (al fijar la contraseña) borra el flag persistente y
              // desbloquea la app. [2M-04]
              return const SetNewPasswordScreen(onDone: clearPasswordRecovery);
            }
            // [M-11] Si la cuenta tiene 2FA (TOTP verificado) y la sesión sigue
            // en AAL1, pedimos el código antes de entrar. Sin 2FA no se ve.
            if (MfaService.needsChallenge()) return const MfaChallengeScreen();
            return const HomeShell();
          },
        );
      },
    );
  }
}
