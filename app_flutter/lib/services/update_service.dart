import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../screens/update_screen.dart';
import 'log_service.dart';

/// Cómo puede actualizarse esta instalación.
enum UpdateChannel {
  /// Windows: descarga el `setup.exe` y lo lanza (Inno Setup reemplaza y
  /// relanza). Sin cambios respecto a como funcionaba antes.
  windows,

  /// Linux, AppImage: se reemplaza a sí mismo y se relanza. Sin contraseña.
  linuxAppImage,

  /// Linux, instalación de usuario (`~/.local`): reemplaza sus propios
  /// ficheros. Sin contraseña.
  linuxUsuario,

  /// Linux, instalación de sistema (`/opt` + `/usr`, del `.deb` o de
  /// `instalar.sh --sistema`): instala el `.deb` nuevo elevando con `pkexec`.
  /// **Pide contraseña en cada actualización**, a propósito.
  linuxSistema,

  /// Hay versión nueva pero no la podemos instalar nosotros: se avisa y se
  /// abre la página de descargas.
  soloAvisar,
}

/// Datos de una actualización disponible.
class UpdateInfo {
  final String versionName;
  final String url;
  final String sha256;
  final String notes;
  final bool mandatory;
  final UpdateChannel channel;

  const UpdateInfo({
    required this.versionName,
    required this.url,
    required this.sha256,
    required this.notes,
    required this.mandatory,
    required this.channel,
  });

  /// Si es false, la pantalla solo avisa y ofrece abrir la web (no descarga).
  bool get puedeInstalarSola => channel != UpdateChannel.soloAvisar;

  /// Si es true, la instalación pedirá autorización de administrador.
  bool get pideContrasena => channel == UpdateChannel.linuxSistema;
}

/// Auto-actualización de las apps de **escritorio** (canal self-hosted).
///
/// Consulta `${AppConfig.updateBaseUrl}/<plataforma>/version.json`. Si el
/// `versionCode` remoto es mayor que el instalado, abre la [UpdateScreen].
///
/// Android se actualiza por **Google Play** e iOS por el **App Store**: no
/// usan este mecanismo (en esas plataformas no hace nada).
///
/// Invariantes de seguridad, que valen para TODOS los canales:
///  - [C-02] solo se acepta una URL `https` del MISMO host que
///    `AppConfig.updateBaseUrl`, y el `sha256` es obligatorio.
///  - [C-02] el hash se verifica SIEMPRE **antes** de ejecutar o instalar
///    nada. En el canal de sistema eso significa que sin un hash válido ni
///    siquiera se llega a pedir la contraseña.
///  - [B-11] la descarga va a un subdirectorio de nombre impredecible.
class UpdateService {
  static bool _checked = false;
  static Map<String, dynamic>? _manifiesto;

  // ---------------------------------------------------------------------
  //  Detección del canal
  // ---------------------------------------------------------------------

  /// Ruta del AppImage en ejecución, o null si no lo estamos.
  ///
  /// El runtime del AppImage exporta `APPIMAGE` con la ruta absoluta del
  /// propio fichero. Si no está, esto es un `.deb`, un `.tar.gz` o un
  /// `flutter run`.
  static String? get _appImage {
    final p = Platform.environment['APPIMAGE'];
    if (p == null || p.isEmpty) return null;
    return File(p).existsSync() ? p : null;
  }

  /// `install-info.json`, que dejan `instalar.sh` y el `.deb` junto al
  /// ejecutable. Evita adivinar el modo de instalación mirando permisos.
  static Map<String, dynamic>? get _infoInstalacion {
    if (_manifiesto != null) return _manifiesto;
    try {
      final dir = File(Platform.resolvedExecutable).parent;
      final f = File('${dir.path}/install-info.json');
      if (!f.existsSync()) return null;
      _manifiesto = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return _manifiesto;
    } catch (_) {
      return null;
    }
  }

  static UpdateChannel? get _channel {
    if (kIsWeb) return null;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return UpdateChannel.windows;
    }
    if (defaultTargetPlatform != TargetPlatform.linux) {
      return null; // Android → Play, iOS/macOS → App Store
    }
    if (_appImage != null) return UpdateChannel.linuxAppImage;

    switch (_infoInstalacion?['modo']) {
      case 'sistema':
        return UpdateChannel.linuxSistema;
      case 'usuario':
        // Solo si de verdad podemos escribir donde está instalada.
        return _esEscribible(File(Platform.resolvedExecutable).parent.path)
            ? UpdateChannel.linuxUsuario
            : UpdateChannel.soloAvisar;
      default:
        // Sin manifiesto: `flutter run`, o una copia suelta. No tocamos nada.
        return UpdateChannel.soloAvisar;
    }
  }

  /// Subcarpeta del servidor de la que cuelga el `version.json`.
  static String get _carpetaCanal =>
      defaultTargetPlatform == TargetPlatform.windows ? 'windows' : 'linux';

  static bool _esEscribible(String ruta) {
    try {
      final sonda = File('$ruta/.pf-escritura-${DateTime.now().microsecondsSinceEpoch}');
      sonda.writeAsStringSync('x');
      sonda.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------
  //  Comprobación
  // ---------------------------------------------------------------------

  /// [C-02] Solo se confía en URLs `https` del MISMO host que
  /// `AppConfig.updateBaseUrl`. Rechaza http, otros dominios o URLs malformadas
  /// → cierra el vector de RCE de redirigir la actualización a un binario ajeno.
  ///
  /// Es pública a propósito para poder cubrirla con pruebas: junto con la
  /// verificación del SHA-256 es lo que impide que un `version.json`
  /// manipulado haga que la app ejecute (o instale como root) un binario
  /// ajeno. Ver `test/update_service_test.dart`.
  @visibleForTesting
  static bool esUrlDeConfianza(String url) => _isTrustedUrl(url);

  static bool _isTrustedUrl(String url) {
    final u = Uri.tryParse(url);
    final base = Uri.tryParse(AppConfig.updateBaseUrl);
    if (u == null || base == null) return false;
    return u.scheme == 'https' && u.host.isNotEmpty && u.host == base.host;
  }

  /// Comprueba si hay versión nueva y, si la hay, abre la pantalla de
  /// actualización. Pensado para llamarse una vez tras el login. Silencioso
  /// ante errores de red.
  static Future<void> checkForUpdate(BuildContext context,
      {bool force = false}) async {
    final canal = _channel;
    if (!AppConfig.enableSelfUpdate || canal == null) return;
    if (_checked && !force) return;
    _checked = true;

    final Map<String, dynamic> remote;
    final int currentCode;
    try {
      final info = await PackageInfo.fromPlatform();
      currentCode = int.tryParse(info.buildNumber) ?? 0;

      final res = await Dio().get<Map<String, dynamic>>(
        '${AppConfig.updateBaseUrl}/$_carpetaCanal/version.json',
        options: Options(
          responseType: ResponseType.json,
          headers: {'Cache-Control': 'no-cache'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      remote = res.data ?? const {};
    } catch (_) {
      return; // sin red o sin servidor: no molestamos al usuario.
    }

    final remoteCode = (remote['versionCode'] as num?)?.toInt() ?? 0;
    if (remoteCode <= currentCode) return;

    // El canal de sistema instala el .deb; los demás, el artefacto principal.
    final esDeb = canal == UpdateChannel.linuxSistema;
    final url = (esDeb ? remote['urlDeb'] : remote['url'])?.toString();
    final sha = (esDeb ? remote['sha256Deb'] : remote['sha256'])
        ?.toString()
        .trim();
    if (!context.mounted) return;

    // [C-02] Solo una descarga HTTPS del propio dominio de updates y con hash
    // SHA-256 declarado. Cualquier otra cosa se degrada a "solo avisar": el
    // usuario se entera de que hay versión nueva, pero no descargamos nada.
    final valido = url != null &&
        url.isNotEmpty &&
        _isTrustedUrl(url) &&
        sha != null &&
        sha.isNotEmpty;
    if (!valido) {
      LogService.evento(
          'Actualización sin URL de confianza o sin hash: solo se avisa.');
    }

    final info = UpdateInfo(
      versionName: remote['versionName']?.toString() ?? '',
      url: valido ? url : AppConfig.updateBaseUrl,
      sha256: valido ? sha : '',
      notes: remote['notes']?.toString() ?? '',
      mandatory: remote['mandatory'] == true,
      channel: valido ? canal : UpdateChannel.soloAvisar,
    );

    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UpdateScreen(info: info),
      fullscreenDialog: true,
    ));
  }

  /// Abre la página de descargas (canal "solo avisar").
  static Future<void> abrirPaginaDeDescargas() async {
    final u = Uri.tryParse(AppConfig.updateBaseUrl);
    if (u == null) return;
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (e, s) {
      LogService.error(e, s, 'abrir página de descargas');
    }
  }

  // ---------------------------------------------------------------------
  //  Descarga + verificación + instalación
  // ---------------------------------------------------------------------

  /// Descarga el paquete, **verifica el SHA-256** [C-02] y lo instala según el
  /// canal. Reporta progreso por [onProgress]. Devuelve un mensaje de error, o
  /// null si va a instalar (la app se cierra).
  ///
  /// La estructura es deliberada: descarga y verificación son **comunes** y
  /// van ANTES de repartir por canal, para que ninguna rama pueda saltarse el
  /// hash. Especialmente importante en [UpdateChannel.linuxSistema], donde lo
  /// que sigue se ejecuta como root.
  static Future<String?> downloadVerifyInstall(
      UpdateInfo info, void Function(double) onProgress) async {
    if (!info.puedeInstalarSola) {
      await abrirPaginaDeDescargas();
      return null;
    }

    // Dónde descargar. En el canal AppImage tiene que ser el MISMO sistema de
    // ficheros que el AppImage: rename(2) falla con EXDEV entre sistemas de
    // ficheros y /tmp suele ser tmpfs. Además así no hay ventana entre
    // verificar el hash y mover el fichero a su sitio.
    final Directory base;
    try {
      final appImage = info.channel == UpdateChannel.linuxAppImage
          ? File(_appImage!)
          : null;
      base = appImage?.parent ?? await getTemporaryDirectory();
    } catch (e) {
      return 'No se pudo preparar la actualización: $e';
    }

    // [B-11] Subdirectorio ALEATORIO (16 bytes CSPRNG) creado en exclusiva
    // para esta actualización: cierra el TOCTOU de una ruta predecible.
    final rnd = Random.secure();
    final token = List<int>.generate(16, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final downloadDir = Directory('${base.path}/.update-$token');

    final String filePath;
    try {
      downloadDir.createSync(recursive: true);
      filePath = '${downloadDir.path}/${_nombreDescarga(info.channel)}';

      await Dio().download(
        info.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress(received / total);
        },
        options: Options(receiveTimeout: const Duration(minutes: 5)),
      );
    } catch (e) {
      _limpiar(downloadDir);
      LogService.error(e, StackTrace.current, 'descarga de actualización');
      if (info.channel == UpdateChannel.linuxAppImage) {
        return 'No se pudo escribir junto a la app. Mueve Portal Familia a una '
            'carpeta tuya (por ejemplo ~/Aplicaciones) y vuelve a intentarlo, '
            'o descarga la versión nueva desde ${AppConfig.updateBaseUrl}.';
      }
      return 'No se pudo descargar la actualización: $e';
    }

    // [C-02] Verificación del hash. Va AQUÍ, antes de cualquier bifurcación:
    // ninguna forma de instalar puede alcanzarse sin haber pasado por esto.
    bool hashOk;
    try {
      final bytes = await File(filePath).readAsBytes();
      hashOk = sha256.convert(bytes).toString().toLowerCase() ==
          info.sha256.toLowerCase();
    } catch (_) {
      hashOk = false;
    }
    if (!hashOk) {
      _limpiar(downloadDir);
      LogService.evento('Actualización descartada: el SHA-256 no coincide.');
      return 'Actualización descartada: la verificación de seguridad falló.';
    }

    // A partir de aquí el paquete está verificado.
    switch (info.channel) {
      case UpdateChannel.windows:
        return _instalarWindows(filePath);
      case UpdateChannel.linuxAppImage:
        return _instalarAppImage(filePath, downloadDir);
      case UpdateChannel.linuxUsuario:
        return _instalarUsuario(filePath, downloadDir);
      case UpdateChannel.linuxSistema:
        return _instalarSistema(filePath, downloadDir);
      case UpdateChannel.soloAvisar:
        return null;
    }
  }

  static String _nombreDescarga(UpdateChannel c) => switch (c) {
        UpdateChannel.windows => 'portal-familia-setup.exe',
        UpdateChannel.linuxSistema => 'portal-familia.deb',
        UpdateChannel.linuxAppImage => 'portal-familia.AppImage',
        _ => 'portal-familia.tar.gz',
      };

  static void _limpiar(Directory d) {
    try {
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }

  // --- Windows: igual que siempre ---------------------------------------
  static Future<String?> _instalarWindows(String filePath) async {
    // Lanza el instalador (que cierra/reemplaza/relanza) y sale para liberar
    // los archivos de la app.
    await Process.start(filePath, const [], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    exit(0);
  }

  // --- Linux, AppImage: se reemplaza a sí mismo --------------------------
  static Future<String?> _instalarAppImage(
      String filePath, Directory downloadDir) async {
    final destino = _appImage;
    if (destino == null) return 'No se encontró el AppImage en ejecución.';
    try {
      final nuevo = File(filePath);
      // rename(2) sobre un ejecutable EN MARCHA sí está permitido en Linux:
      // sustituye la entrada de directorio, no el inodo, y el proceso vivo
      // conserva el suyo abierto.
      await nuevo.rename(destino);
      await Process.run('chmod', ['0755', destino]);
      _limpiar(downloadDir);
    } catch (e) {
      _limpiar(downloadDir);
      LogService.error(e, StackTrace.current, 'reemplazo del AppImage');
      return 'No se pudo reemplazar la app: $e';
    }
    await _relanzar([destino]);
    return null;
  }

  // --- Linux, instalación de usuario -------------------------------------
  static Future<String?> _instalarUsuario(
      String filePath, Directory downloadDir) async {
    final prefijo = _infoInstalacion?['prefijo']?.toString();
    if (prefijo == null) return 'No sé dónde está instalada la app.';
    try {
      // El .tar.gz trae una carpeta portal-familia-<ver>/ dentro.
      final extraido = Directory('${downloadDir.path}/x')..createSync();
      final r = await Process.run(
          'tar', ['xzf', filePath, '-C', extraido.path, '--strip-components=1']);
      if (r.exitCode != 0) return 'No se pudo descomprimir: ${r.stderr}';

      for (final e in extraido.listSync()) {
        final nombre = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (nombre == 'instalar.sh') continue;
        final destino = '$prefijo/$nombre';
        if (e is Directory) {
          await Process.run('cp', ['-a', '-T', e.path, destino]);
        } else {
          await File(e.path).copy(destino);
        }
      }
      await Process.run('chmod', ['0755', '$prefijo/portal_familia']);
      _limpiar(downloadDir);
    } catch (e) {
      _limpiar(downloadDir);
      LogService.error(e, StackTrace.current, 'actualización de usuario');
      return 'No se pudo actualizar: $e';
    }
    await _relanzar(['$prefijo/portal_familia']);
    return null;
  }

  // --- Linux, instalación de sistema: eleva con PolicyKit ----------------
  static Future<String?> _instalarSistema(
      String filePath, Directory downloadDir) async {
    // Se prefiere SIEMPRE pkexec: el diálogo de contraseña lo muestra el
    // escritorio, así que la contraseña no pasa nunca por este proceso.
    // `apt-get install` sobre un fichero resuelve dependencias nuevas; si no
    // está (Debian pelado), `dpkg -i` sirve mientras no cambien las deps.
    final intentos = <List<String>>[
      ['pkexec', '/usr/bin/apt-get', 'install', '-y', '--reinstall', filePath],
      ['pkexec', '/usr/bin/dpkg', '-i', filePath],
    ];

    ProcessResult? ultimo;
    for (final cmd in intentos) {
      try {
        ultimo = await Process.run(cmd.first, cmd.sublist(1),
            environment: {'DEBIAN_FRONTEND': 'noninteractive'});
      } catch (e) {
        LogService.error(e, StackTrace.current, 'pkexec');
        continue;
      }
      if (ultimo.exitCode == 0) {
        _limpiar(downloadDir);
        await _relanzar(['/opt/portal-familia/portal_familia']);
        return null;
      }
      // 126 = el usuario canceló el diálogo de autenticación.
      // 127 = no hay agente de PolicyKit con el que autenticarse.
      if (ultimo.exitCode == 126) {
        _limpiar(downloadDir);
        return 'Actualización cancelada: hace falta la contraseña de '
            'administrador para instalarla.';
      }
      if (ultimo.exitCode == 127) break;
    }

    _limpiar(downloadDir);
    LogService.evento(
        'No se pudo instalar el .deb (pkexec: ${ultimo?.exitCode}).');
    return 'No se pudo instalar la actualización automáticamente. '
        'Descárgala desde ${AppConfig.updateBaseUrl} e instálala con:\n'
        'sudo apt install ./portal-familia_amd64.deb';
  }

  /// Relanza la app y sale.
  ///
  /// El `sleep` no es cosmético: la app es de **instancia única** (ver
  /// `linux/runner/my_application.cc`), así que si el proceso nuevo arranca
  /// antes de que este libere su nombre en D-Bus, el nuevo se lo cede al viejo
  /// y sale enseguida — al usuario le parecería que la app "se cerró sola".
  static Future<void> _relanzar(List<String> cmd) async {
    try {
      await Process.start(
        '/bin/sh',
        ['-c', 'sleep 1; exec "\$0" "\$@"', ...cmd],
        mode: ProcessStartMode.detached,
      );
    } catch (e, s) {
      LogService.error(e, s, 'relanzar tras actualizar');
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    exit(0);
  }
}
