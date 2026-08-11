// Punto de entrada: arranque, sesión, deep links y navegación raíz.
import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
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
import 'services/linux_desktop_integration.dart';
import 'services/log_service.dart';
import 'services/mfa_service.dart';
import 'services/secure_session_storage.dart';

Future<void> main(List<String> args) async {
  runZonedGuarded(
    () => _arrancar(args),
    (e, s) => LogService.error(e, s, 'zona raíz'),
  );
}

Future<void> _arrancar(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  await LogService.init();

  final erroresPrevios = FlutterError.onError;
  FlutterError.onError = (details) {
    LogService.errorFlutter(details);
    erroresPrevios?.call(details);
  };
  PlatformDispatcher.instance.onError = (e, s) {
    LogService.error(e, s, 'PlatformDispatcher');
    return true;
  };

  await LinuxDesktopIntegration.registrarSiHaceFalta();

  await initializeDateFormatting('es', null);
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,

    authOptions: FlutterAuthClientOptions(
      localStorage: SecureSessionStorage(supabaseUrl: AppConfig.supabaseUrl),
      pkceAsyncStorage: const SecurePkceAsyncStorage(),
    ),
  );

  final pending = await _leerFlagRecuperacion();
  if (pending == '1') {
    if (supabase.auth.currentSession != null) {
      passwordRecoveryNotifier.value = true;
    } else {
      await _borrarFlagRecuperacion();
    }
  }

  supabase.auth.onAuthStateChange.listen((state) async {
    if (state.event == AuthChangeEvent.passwordRecovery) {
      await _escribirFlagRecuperacion();
      passwordRecoveryNotifier.value = true;
    } else if (state.event == AuthChangeEvent.signedOut) {
      await _borrarFlagRecuperacion();
      passwordRecoveryNotifier.value = false;
    }
  });

  runApp(PortalFamiliaApp(argumentosDeArranque: args));
}

final supabase = Supabase.instance.client;

final passwordRecoveryNotifier = ValueNotifier<bool>(false);

const _recoveryStore = FlutterSecureStorage();
const _kPendingRecovery = 'pending_pw_recovery';

Future<String?> _leerFlagRecuperacion() async {
  try {
    return await _recoveryStore.read(key: _kPendingRecovery);
  } catch (e, s) {
    LogService.error(e, s, 'flag de recuperación (lectura)');
    return null;
  }
}

Future<void> _escribirFlagRecuperacion() async {
  try {
    await _recoveryStore.write(key: _kPendingRecovery, value: '1');
  } catch (e, s) {
    LogService.error(e, s, 'flag de recuperación (escritura)');
  }
}

Future<void> _borrarFlagRecuperacion() async {
  try {
    await _recoveryStore.delete(key: _kPendingRecovery);
  } catch (e, s) {
    LogService.error(e, s, 'flag de recuperación (borrado)');
  }
}

Future<void> clearPasswordRecovery() async {
  await _borrarFlagRecuperacion();
  passwordRecoveryNotifier.value = false;
}

final navigatorKey = GlobalKey<NavigatorState>();

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
  const PortalFamiliaApp({super.key, this.argumentosDeArranque = const []});

  final List<String> argumentosDeArranque;

  @override
  State<PortalFamiliaApp> createState() => _PortalFamiliaAppState();
}

class _PortalFamiliaAppState extends State<PortalFamiliaApp> {
  AppLifecycleListener? _ciclo;

  @override
  void initState() {
    super.initState();
    DeepLinkService.init(argumentosDeArranque: widget.argumentosDeArranque);

    _ciclo = AppLifecycleListener(
      onExitRequested: () async {
        LogService.cierreLimpio();
        return AppExitResponse.exit;
      },
      onDetach: LogService.cierreLimpio,
      onPause: LogService.cierreLimpio,
      onResume: LogService.reabrirSesion,
    );
  }

  @override
  void dispose() {
    _ciclo?.dispose();
    super.dispose();
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

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, _) {
        final session = supabase.auth.currentSession;
        if (session == null) {
          passwordRecoveryNotifier.value = false;
          return const LoginScreen();
        }

        return ValueListenableBuilder<bool>(
          valueListenable: passwordRecoveryNotifier,
          builder: (context, recovering, __) {
            if (recovering) {
              return const SetNewPasswordScreen(onDone: clearPasswordRecovery);
            }

            if (MfaService.needsChallenge()) return const MfaChallengeScreen();
            return const HomeShell();
          },
        );
      },
    );
  }
}
