import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/mfa_challenge_screen.dart';
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
  runApp(const PortalFamiliaApp());
}

/// Acceso global al cliente de Supabase.
final supabase = Supabase.instance.client;

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
        if (session == null) return const LoginScreen();
        // [M-11] Si la cuenta tiene 2FA (TOTP verificado) y la sesión sigue en
        // AAL1, pedimos el código antes de entrar. Quien no use 2FA no lo ve.
        if (MfaService.needsChallenge()) return const MfaChallengeScreen();
        return const HomeShell();
      },
    );
  }
}
