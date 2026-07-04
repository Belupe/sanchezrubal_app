import 'package:flutter/material.dart';

import '../models/system_config.dart';
import '../services/data_service.dart';

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
        _error = 'No se pudo cargar la configuración: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuración')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuración')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _init,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isMega) {
      return DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Configuración'),
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'SMTP y general'),
                Tab(text: 'Plantillas'),
                Tab(text: 'Mis notificaciones'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              _SystemConfigTab(),
              _TemplatesTab(),
              _NotificationsTab(),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: const _NotificationsTab(),
    );
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
  final _maxDaysCap = TextEditingController();
  final _testEmail = TextEditingController();
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
        _error = 'No se pudo cargar la configuración: $e';
        _loading = false;
      });
    }
  }

  void _fill(SystemConfig? cfg) {
    _smtpHost.text = cfg?.smtpHost ?? '';
    _smtpPort.text = cfg?.smtpPort?.toString() ?? '';
    _smtpUser.text = cfg?.smtpUser ?? '';
    _smtpPass.text = cfg?.smtpPass ?? '';
    _smtpSecure = cfg?.smtpSecure ?? false;
    _maxDays.text = cfg?.maxReservationDays.toString() ?? '';
    _maxDaysCap.text = cfg?.maxReservationDaysCap.toString() ?? '';
  }

  Future<void> _test() async {
    final to = _testEmail.text.trim();
    if (to.isEmpty) {
      setState(() => _testResult = 'Indica un correo de destino.');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final err = await DataService.testSmtp(to);
      setState(() => _testResult =
          err == null ? '✅ Correo de prueba enviado a $to.' : '❌ $err');
    } catch (e) {
      setState(() => _testResult = '❌ $e');
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
    _maxDaysCap.dispose();
    _testEmail.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final port = int.tryParse(_smtpPort.text.trim());
    final days = int.tryParse(_maxDays.text.trim());
    final daysCap = int.tryParse(_maxDaysCap.text.trim());
    if (_smtpPort.text.trim().isNotEmpty && port == null) {
      setState(() => _error = 'El puerto SMTP debe ser un número.');
      return;
    }
    if (days == null || days < 1) {
      setState(() =>
          _error = 'Los días mínimos de reserva deben ser un número mayor o igual a 1.');
      return;
    }
    if (daysCap == null || daysCap < days) {
      setState(() => _error =
          'Los días máximos de reserva deben ser un número mayor o igual al mínimo.');
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
        'smtp_pass': _smtpPass.text,
        'smtp_secure': _smtpSecure,
        'max_reservation_days': days,
        'max_reservation_days_cap': daysCap,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración guardada')),
        );
      }
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
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
                Text('General',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _maxDays,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Días mínimos de reserva',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _maxDaysCap,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Días máximos de reserva',
                      border: OutlineInputBorder()),
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
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _smtpPort,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Puerto', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _smtpUser,
                  decoration: const InputDecoration(
                      labelText: 'Usuario', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _smtpPass,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Contraseña', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Conexión segura (SSL/TLS)'),
                  value: _smtpSecure,
                  onChanged: (v) => setState(() => _smtpSecure = v),
                ),
                const Divider(height: 24),
                Text('Probar envío',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _testEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo de destino para la prueba',
                    helperText: 'Usa la configuración ya GUARDADA. Guarda antes de probar.',
                    border: OutlineInputBorder(),
                  ),
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
                            child: CircularProgressIndicator(strokeWidth: 2))
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
                    child: CircularProgressIndicator(strokeWidth: 2))
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
        _error = 'No se pudieron cargar las plantillas: $e';
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
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton.tonal(
                  onPressed: _load, child: const Text('Reintentar')),
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
  late final TextEditingController _subject =
      TextEditingController(text: widget.subject);
  late final TextEditingController _body =
      TextEditingController(text: widget.body);
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
          SnackBar(content: Text('Plantilla "${_label(widget.type)}" guardada')),
        );
      }
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
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
            Text(_label(widget.type),
                style: Theme.of(context).textTheme.titleMedium),
            Text(widget.type,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    )),
            const SizedBox(height: 12),
            TextField(
              controller: _subject,
              decoration: const InputDecoration(
                  labelText: 'Asunto', border: OutlineInputBorder()),
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
                        child: CircularProgressIndicator(strokeWidth: 2))
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
// Mis notificaciones (cualquier rol)
// ====================================================================
class _NotificationsTab extends StatefulWidget {
  const _NotificationsTab();

  @override
  State<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<_NotificationsTab> {
  static const _type = 'PRE_STAY';

  bool _isActive = true;
  final _customText = TextEditingController();

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
      final rows = await DataService.myNotificationSettings();
      final existing = rows.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['type'] == _type,
            orElse: () => null,
          );
      setState(() {
        _isActive = (existing?['is_active'] as bool?) ?? true;
        _customText.text = (existing?['custom_text'] as String?) ?? '';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No se pudieron cargar tus notificaciones: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _customText.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DataService.saveNotificationSetting(
        _type,
        isActive: _isActive,
        customText: _customText.text.trim().isEmpty
            ? null
            : _customText.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notificaciones guardadas')),
        );
      }
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
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
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton.tonal(
                  onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
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
                Text('Mis notificaciones',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Recordatorio previo a la estancia'),
                  subtitle: const Text(
                      'Recibe un aviso antes de tu reserva (PRE_STAY).'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _customText,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Texto personalizado (opcional)',
                    border: OutlineInputBorder(),
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
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Guardar'),
          ),
        ),
      ],
    );
  }
}
