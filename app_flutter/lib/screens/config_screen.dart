import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/system_config.dart';
import '../services/data_service.dart';
import '../services/log_service.dart';
import '../services/push_service.dart';
import '../utils/errors.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  String? _role;
  bool _loading = true;
  String? _error;

  bool get _isMega => _role == 'MEGA_ADMIN';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final role = await DataService.currentRole();
      setState(() {
        _role = role;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyError(
          e,
          fallback: 'No se pudo cargar la configuración.',
        );
        _loading = false;
      });
    }
  }

  // Ninguna rama devuelve Scaffold ni AppBar: esta pantalla se monta dentro de
  // home_shell, que ya aporta ambas y pinta el título de la sección. Las cuatro
  // AppBar que había aquí (carga, error, con pestañas y sin ellas) apilaban una
  // segunda barra y repetían "Configuración". Mismo caso que inspecciones_screen.
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _init,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isMega) {
      // El TabBar iba colgado del `bottom:` de la AppBar. Al quitarla, va suelto
      // justo debajo de la barra del shell y el TabBarView ocupa el resto.
      return const DefaultTabController(
        length: 3,
        child: Column(
          children: [
            TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'SMTP y general'),
                Tab(text: 'Plantillas'),
                Tab(text: 'Soporte'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _SystemConfigTab(),
                  _TemplatesTab(),
                  _SoporteTab(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return const _SoporteTab();
  }
}

// ====================================================================
// (1) SMTP y general
// ====================================================================
class _SystemConfigTab extends StatefulWidget {
  const _SystemConfigTab();

  @override
  State<_SystemConfigTab> createState() => _SystemConfigTabState();
}

class _SystemConfigTabState extends State<_SystemConfigTab> {
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController();
  final _smtpUser = TextEditingController();
  final _smtpPass = TextEditingController();
  bool _smtpSecure = false;
  final _maxDays = TextEditingController();
  bool _testing = false;
  String? _testResult;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cfg = await DataService.systemConfig();
      _fill(cfg);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = friendlyError(
          e,
          fallback: 'No se pudo cargar la configuración.',
        );
        _loading = false;
      });
    }
  }

  void _fill(SystemConfig? cfg) {
    _smtpHost.text = cfg?.smtpHost ?? '';
    _smtpPort.text = cfg?.smtpPort?.toString() ?? '';
    _smtpUser.text = cfg?.smtpUser ?? '';
    _smtpPass.text =
        ''; // [M-07] no se descarga; en blanco = conservar la guardada.
    _smtpSecure = cfg?.smtpSecure ?? false;
    _maxDays.text = cfg?.maxReservationDays.toString() ?? '';
  }

  Future<void> _test() async {
    // [I-06] El correo de prueba va SIEMPRE al propio correo del mega (el
    // servidor ignora cualquier destino), así que no se pide uno.
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final err = await DataService.testSmtp();
      setState(
        () => _testResult = err == null
            ? '✅ Correo de prueba enviado a tu correo.'
            : friendlyError(
                err,
                fallback: '❌ No se pudo enviar el correo de prueba.',
              ),
      );
    } catch (e) {
      setState(
        () => _testResult = friendlyError(
          e,
          fallback: '❌ No se pudo enviar el correo de prueba.',
        ),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    _smtpHost.dispose();
    _smtpPort.dispose();
    _smtpUser.dispose();
    _smtpPass.dispose();
    _maxDays.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final port = int.tryParse(_smtpPort.text.trim());
    final days = int.tryParse(_maxDays.text.trim());
    if (_smtpPort.text.trim().isNotEmpty && port == null) {
      setState(() => _error = 'El puerto SMTP debe ser un número.');
      return;
    }
    if (days == null || days < 1) {
      setState(
        () => _error = 'Los días por reserva deben ser un número mayor que 0.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DataService.updateSystemConfig({
        'smtp_host': _smtpHost.text.trim(),
        'smtp_port': port,
        'smtp_user': _smtpUser.text.trim(),
        'smtp_secure': _smtpSecure,
        'max_reservation_days': days,
        'max_reservation_days_cap': days,
      });
      // [M-07] La contraseña SMTP va a Vault por separado; solo se cambia si el
      // mega escribió algo (campo en blanco = conservar la actual).
      if (_smtpPass.text.isNotEmpty) {
        await DataService.setSmtpPassword(_smtpPass.text);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Configuración guardada')));
      }
    } catch (e) {
      setState(
        () => _error = friendlyError(e, fallback: 'No se pudo guardar.'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('General', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                // Un único campo: la familia reserva siempre por quincenas, así
                // que mínimo y tope son el mismo número y se escriben a la vez.
                TextField(
                  controller: _maxDays,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Días por reserva',
                    helperText: 'Todas las reservas duran exactamente estos días.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('SMTP', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _smtpHost,
                  decoration: const InputDecoration(
                    labelText: 'Servidor (host)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _smtpPort,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Puerto',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _smtpUser,
                  decoration: const InputDecoration(
                    labelText: 'Usuario',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _smtpPass,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Conexión segura (SSL/TLS)'),
                  value: _smtpSecure,
                  onChanged: (v) => setState(() => _smtpSecure = v),
                ),
                const Divider(height: 24),
                Text(
                  'Probar envío',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Se enviará un correo de prueba a TU propio correo, usando la '
                  'configuración ya GUARDADA. Guarda antes de probar.',
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 8),
                  Text(_testResult!),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: const Text('Enviar correo de prueba'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ),
      ],
    );
  }
}

// ====================================================================
// (2) Plantillas de correo
// ====================================================================
class _TemplatesTab extends StatefulWidget {
  const _TemplatesTab();

  @override
  State<_TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends State<_TemplatesTab> {
  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await DataService.templates();
      setState(() {
        _templates = rows;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyError(
          e,
          fallback: 'No se pudieron cargar las plantillas.',
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _load,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (_templates.isEmpty) {
      return const Center(child: Text('No hay plantillas.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final t in _templates)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _TemplateCard(
              type: (t['type'] as String?) ?? '',
              subject: (t['subject'] as String?) ?? '',
              body: (t['body'] as String?) ?? '',
            ),
          ),
      ],
    );
  }
}

class _TemplateCard extends StatefulWidget {
  final String type;
  final String subject;
  final String body;
  const _TemplateCard({
    required this.type,
    required this.subject,
    required this.body,
  });

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  late final TextEditingController _subject = TextEditingController(
    text: widget.subject,
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.body,
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  String _label(String type) {
    switch (type) {
      case 'RESERVATION_CONFIRMATION':
        return 'Confirmación de reserva';
      case 'MAINTENANCE':
        return 'Mantenimiento';
      case 'INSPECTION_REMINDER':
        return 'Recordatorio de inspección';
      case 'PRE_STAY':
        return 'Antes de la estancia';
      default:
        return type;
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DataService.updateTemplate(
        widget.type,
        subject: _subject.text,
        body: _body.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plantilla "${_label(widget.type)}" guardada'),
          ),
        );
      }
    } catch (e) {
      setState(
        () => _error = friendlyError(e, fallback: 'No se pudo guardar.'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _label(widget.type),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              widget.type,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subject,
              decoration: const InputDecoration(
                labelText: 'Asunto',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              maxLines: 8,
              minLines: 4,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: 'Cuerpo',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
// Soporte (cualquier rol)
// ====================================================================
// Antes esto era "Mis notificaciones" y solo servía para activar o desactivar
// el recordatorio previo a la estancia. Se retiró: ese aviso pasa a estar
// SIEMPRE activo (send-email ya lo trataba así cuando el usuario no tenía
// fila) y su texto se edita desde la plantilla PRE_STAY en Supabase, sin
// recompilar. Lo que sí hacía falta era un sitio al que mandar a alguien
// cuando algo va mal, y de ahí el cambio de nombre.
class _SoporteTab extends StatelessWidget {
  const _SoporteTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [_DiagnosticoCard()],
    );
  }
}

// ====================================================================
// (4) Diagnóstico — registro de fallos
// ====================================================================

/// Deja a mano el informe del último fallo para poder pedírselo al usuario.
///
/// El botón principal lo manda a soporte por correo con un solo toque, en las
/// cinco plataformas: el destinatario lo fija la Edge Function `send-log`, así
/// que nadie tiene que escribir una dirección ni acertarla. Antes esto era
/// notablemente peor: en móvil había que pasar por el menú de compartir y
/// elegir un cliente de correo, y en escritorio no había forma de enviarlo,
/// solo "abrir la carpeta" y adjuntar el fichero a mano.
///
/// Se conservan las dos vías antiguas como respaldo, porque el envío depende
/// del SMTP y de la red: si el correo falla, el fichero sigue estando ahí.
class _DiagnosticoCard extends StatefulWidget {
  const _DiagnosticoCard();

  @override
  State<_DiagnosticoCard> createState() => _DiagnosticoCardState();
}

class _DiagnosticoCardState extends State<_DiagnosticoCard> {
  bool _enviando = false;
  String? _resultado;

  /// Manda el registro a soporte por correo. Es el camino principal.
  ///
  /// Se envía el informe del último fallo si lo hay y, si no, el registro de la
  /// sesión en curso: los errores que se tragan (push, red, permisos) no
  /// cierran la app y por tanto nunca generan un `ultimo-fallo.log`, que era
  /// justo el caso en el que más falta hace poder mirar algo.
  Future<void> _enviarASoporte() async {
    final f = LogService.ultimoFallo ?? LogService.sesionActual;
    if (f == null) {
      setState(() => _resultado = 'No hay ningún registro que enviar.');
      return;
    }
    setState(() {
      _enviando = true;
      _resultado = null;
    });
    try {
      final esFallo = LogService.ultimoFallo != null;
      // Segunda pasada de saneado. El registro ya se redacta al escribirse,
      // pero esto va a salir por correo hacia fuera y la función es barata.
      final contenido = LogService.redactar(await f.readAsString());
      final err = await DataService.enviarRegistroASoporte(
        registro: contenido,
        esFallo: esFallo,
        contexto: {
          'Plataforma': kIsWeb ? 'web' : defaultTargetPlatform.name,
          'Notificaciones': PushService.estado,
          'Origen': esFallo ? 'ultimo-fallo.log' : 'sesion.log',
        },
      );
      if (!mounted) return;
      setState(
        () => _resultado = err == null
            ? '✅ Registro enviado a soporte. Gracias.'
            : '❌ $err',
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _resultado = '❌ ${friendlyError(e, fallback: 'No se pudo enviar el registro.')}',
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  static bool get _esEscritorio =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<void> _abrirCarpeta() async {
    final dir = LogService.carpeta;
    if (dir == null) return;
    var abierta = false;
    try {
      abierta = await launchUrl(dir.uri);
    } catch (_) {
      abierta = false;
    }
    if (abierta || !mounted) return;
    // Sin gestor de archivos (o sin xdg-open): al menos que pueda copiar la ruta.
    await Clipboard.setData(ClipboardData(text: dir.path));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ruta copiada al portapapeles.')),
    );
  }

  /// Envía el informe del último fallo si lo hay y, si no, el registro de la
  /// sesión en curso. Antes solo se podía enviar cuando la app se había
  /// cerrado sola, que es justo cuando MENOS falta hace: los fallos que se
  /// tragan (push, red, permisos) no cierran la app y eran imposibles de
  /// diagnosticar en un móvil.
  Future<void> _compartirInforme() async {
    final f = LogService.ultimoFallo ?? LogService.sesionActual;
    if (f == null) return;
    final esFallo = LogService.ultimoFallo != null;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path)],
        subject: esFallo
            ? 'Portal Familia — informe de fallo'
            : 'Portal Familia — registro de sesión',
        text: esFallo
            ? 'Informe del último fallo de Portal Familia.'
            : 'Registro de la sesión en curso de Portal Familia.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fallo = LogService.ultimoFallo;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Diagnóstico', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Si la app se cierra sola o hace algo raro, pulsa el botón: nos '
              'llega el informe técnico y no tienes que hacer nada más. '
              'No contiene tu contraseña ni tu sesión.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              fallo == null
                  ? 'No hay ningún fallo registrado.'
                  : 'Hay un informe del ${_fecha(fallo.lastModifiedSync())}.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            // Estado de las notificaciones: un fallo de push no cierra la app,
            // así que sin esto no hay forma de saber por qué no llegan.
            SelectableText(
              'Notificaciones — ${PushService.estado}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            // Camino principal, igual en las cinco plataformas. Siempre
            // habilitado: si no hay fallo manda el registro de la sesión, que
            // es el único rastro de los errores que no cierran la app.
            FilledButton.icon(
              onPressed: _enviando ? null : _enviarASoporte,
              icon: _enviando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mail_outline),
              label: Text(
                _enviando ? 'Enviando…' : 'Enviar registro a soporte',
              ),
            ),
            if (_resultado != null) ...[
              const SizedBox(height: 10),
              Text(
                _resultado!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _resultado!.startsWith('✅')
                      ? null
                      : theme.colorScheme.error,
                ),
              ),
            ],
            // Respaldos, por si el correo no sale (SMTP caído, sin red).
            if (_esEscritorio) ...[
              const SizedBox(height: 12),
              SelectableText(
                LogService.rutaCarpeta,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _abrirCarpeta,
                icon: const Icon(Icons.folder_open),
                label: const Text('Abrir carpeta de registros'),
              ),
            ] else ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _compartirInforme,
                icon: const Icon(Icons.ios_share),
                label: Text(
                  fallo == null
                      ? 'Compartir registro de la sesión'
                      : 'Compartir informe del último fallo',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/'
      '${d.year} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
