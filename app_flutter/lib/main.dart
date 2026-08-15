// Punto de entrada: arranque, sesión, deep links y navegación raíz.
import 'dart:async';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/mfa_challenge_screen.dart';
import 'screens/auth/set_new_password_screen.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
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
  await cargarA11y();
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

class A11yPrefs {
  final double escalaTexto;
  final bool altoContraste;
  final bool negrita;
  final bool sinAnimaciones;
  const A11yPrefs({
    this.escalaTexto = 1.0,
    this.altoContraste = false,
    this.negrita = false,
    this.sinAnimaciones = false,
  });

  A11yPrefs copyWith({
    double? escalaTexto,
    bool? altoContraste,
    bool? negrita,
    bool? sinAnimaciones,
  }) =>
      A11yPrefs(
        escalaTexto: escalaTexto ?? this.escalaTexto,
        altoContraste: altoContraste ?? this.altoContraste,
        negrita: negrita ?? this.negrita,
        sinAnimaciones: sinAnimaciones ?? this.sinAnimaciones,
      );
}

final a11yNotifier = ValueNotifier<A11yPrefs>(const A11yPrefs());

Future<void> cargarA11y() async {
  final sp = await SharedPreferences.getInstance();
  a11yNotifier.value = A11yPrefs(
    escalaTexto: sp.getDouble('a11y_escala') ?? 1.0,
    altoContraste: sp.getBool('a11y_contraste') ?? false,
    negrita: sp.getBool('a11y_negrita') ?? false,
    sinAnimaciones: sp.getBool('a11y_sin_animaciones') ?? false,
  );
}

Future<void> guardarA11y(A11yPrefs p) async {
  a11yNotifier.value = p;
  final sp = await SharedPreferences.getInstance();
  await sp.setDouble('a11y_escala', p.escalaTexto);
  await sp.setBool('a11y_contraste', p.altoContraste);
  await sp.setBool('a11y_negrita', p.negrita);
  await sp.setBool('a11y_sin_animaciones', p.sinAnimaciones);
}

class _SinTransicion extends PageTransitionsBuilder {
  const _SinTransicion();
  @override
  Widget buildTransitions<T>(route, context, animation, secondaryAnimation, child) =>
      child;
}

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

  ThemeData _tema(Brightness b, A11yPrefs a) => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: b,
          contrastLevel: a.altoContraste ? 1.0 : 0.0,
        ),
        useMaterial3: true,
        pageTransitionsTheme: a.sinAnimaciones
            ? PageTransitionsTheme(builders: {
                for (final p in TargetPlatform.values) p: const _SinTransicion(),
              })
            : null,
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) => ValueListenableBuilder<A11yPrefs>(
        valueListenable: a11yNotifier,
        builder: (context, a11y, _) => MaterialApp(
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
          theme: _tema(Brightness.light, a11y),
          darkTheme: _tema(Brightness.dark, a11y),
          themeMode: mode,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(a11y.escalaTexto),
                boldText: mq.boldText || a11y.negrita,
                disableAnimations: mq.disableAnimations || a11y.sinAnimaciones,
              ),
              child: child!,
            );
          },
          home: const AuthGate(),
        ),
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
            return const _HomeConOnboarding();
          },
        );
      },
    );
  }
}

class _HomeConOnboarding extends StatefulWidget {
  const _HomeConOnboarding();

  @override
  State<_HomeConOnboarding> createState() => _HomeConOnboardingState();
}

class _HomeConOnboardingState extends State<_HomeConOnboarding> {
  bool? _pendiente;

  @override
  void initState() {
    super.initState();
    OnboardingScreen.pendiente().then((v) {
      if (mounted) setState(() => _pendiente = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_pendiente == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_pendiente!) {
      return OnboardingScreen(onDone: () => setState(() => _pendiente = false));
    }
    return const HomeShell();
  }
}
