import 'package:flutter/material.dart';
import '../main.dart';
import '../models/property.dart';
import '../services/data_service.dart';
import '../services/push_service.dart';
import '../services/update_service.dart';
import '../utils/errors.dart';
import '../utils/password_policy.dart';
import '../widgets/password_widgets.dart';
import 'anuncios_screen.dart';
import 'casas_screen.dart';
import 'config_screen.dart';
import 'inspecciones_screen.dart';
import 'inspection_screen.dart';
import 'intercambios_screen.dart';
import 'mfa_screen.dart';
import 'property_calendar_screen.dart';
import 'registros_screen.dart';
import 'sorteos_screen.dart';
import 'usuarios_screen.dart';

class _NavItem {
  final String title;
  final IconData icon;
  final Widget screen;
  const _NavItem(this.title, this.icon, this.screen);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String? _role;
  int _selected = 0;

  bool _avisoPushOculto = false;

  @override
  void initState() {
    super.initState();
    _load();

    PushService.init();

    PushService.destinoPendiente.addListener(_procesarDestino);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      UpdateService.checkForUpdate(context);
      _procesarDestino();
    });
  }

  @override
  void dispose() {
    PushService.destinoPendiente.removeListener(_procesarDestino);
    super.dispose();
  }

  Future<void> _procesarDestino() async {
    final data = PushService.destinoPendiente.value;
    if (data == null || !mounted) return;
    PushService.destinoPendiente.value = null; // consumir: no repetir el salto

    final type = (data['type'] ?? '').toString().toLowerCase();
    final propertyId = (data['propertyId'] ?? '').toString();
    final reservationId = (data['reservationId'] ?? '').toString();

    if (type.contains('swap')) {
      _irAPanel('Intercambios');
      return;
    }
    if ((type.contains('inspection') || type.contains('out_report')) &&
        reservationId.isNotEmpty) {
      _irAPanel('Domicilios');
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => InspectionScreen(reservationId: reservationId),
        ),
      );
      return;
    }
    if (propertyId.isNotEmpty) {
      _irAPanel('Domicilios');
      try {
        final props = await DataService.properties();
        Property? prop;
        for (final p in props) {
          if (p.id == propertyId) {
            prop = p;
            break;
          }
        }
        if (prop != null && mounted) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => PropertyCalendarScreen(property: prop!),
            ),
          );
        }
      } catch (_) {}
    }
  }

  void _irAPanel(String titulo) {
    final i = _items.indexWhere((it) => it.title == titulo);
    if (i >= 0 && mounted) setState(() => _selected = i);
  }

  Future<void> _load() async {
    final p = await DataService.myProfile();
    if (!mounted) return;
    setState(() => _role = p?['role'] as String?);
    final prefs = p?['ui_preferences'];
    if (prefs is Map && prefs['theme'] is String) {
      themeNotifier.value = themeModeFromString(prefs['theme'] as String);
    }
  }

  bool get _isPrincipal => _role == 'MEGA_ADMIN' || _role == 'PRINCIPAL_ADMIN';

  List<_NavItem> get _items => [
    const _NavItem('Anuncios', Icons.campaign, AnunciosScreen()),
    const _NavItem('Domicilios', Icons.home_work, CasasScreen()),
    if (_isPrincipal)
      const _NavItem('Inspecciones', Icons.fact_check, InspeccionesScreen()),
    const _NavItem('Registros', Icons.history, RegistrosScreen()),
    const _NavItem('Intercambios', Icons.swap_horiz, IntercambiosScreen()),
    if (_isPrincipal) const _NavItem('Sorteos', Icons.casino, SorteosScreen()),
    const _NavItem('Grupos y usuarios', Icons.group, UsuariosScreen()),
    const _NavItem('Configuración', Icons.settings, ConfigScreen()),
    const _NavItem('Perfil', Icons.person, ProfileTab()),
  ];

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que quieres cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok == true) await supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final index = _selected.clamp(0, items.length - 1);
    final current = items[index];

    return Scaffold(
      appBar: AppBar(
        title: Text(current.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: _logout,
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: const Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    'Portal Familia',
                    style: TextStyle(color: Colors.white, fontSize: 22),
                  ),
                ),
              ),
              for (var i = 0; i < items.length; i++)
                ListTile(
                  leading: Icon(items[i].icon),
                  title: Text(items[i].title),
                  selected: i == index,
                  onTap: () {
                    setState(() => _selected = i);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          _AvisoNotificaciones(
            oculto: _avisoPushOculto,
            onOcultar: () => setState(() => _avisoPushOculto = true),
          ),
          Expanded(child: current.screen),
        ],
      ),
    );
  }
}

class _AvisoNotificaciones extends StatelessWidget {
  const _AvisoNotificaciones({required this.oculto, required this.onOcultar});

  final bool oculto;
  final VoidCallback onOcultar;

  Future<void> _abrirAjustes(BuildContext context) async {
    final abierto = await PushService.abrirAjustes();
    if (abierto || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ábrelos a mano: ${PushService.comoActivarlo}'),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (oculto || !PushService.plataformaSoportada) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool?>(
      valueListenable: PushService.avisosActivos,
      builder: (context, activos, __) {
        if (activos != false) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Material(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_off,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tienes las notificaciones desactivadas. No te avisaremos '
                    'de reservas ni cambios en este dispositivo.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _abrirAjustes(context),
                  child: const Text('Activar'),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Ocultar hasta la próxima vez',
                  color: theme.colorScheme.onErrorContainer,
                  onPressed: onOcultar,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Future<Map<String, dynamic>?> _future = DataService.myProfile();

  void _reload() => setState(() => _future = DataService.myProfile());

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _roleLabel(String? r) {
    switch (r) {
      case 'MEGA_ADMIN':
        return 'Mega administrador';
      case 'PRINCIPAL_ADMIN':
        return 'Administrador principal';
      case 'FAMILY_ADMIN':
        return 'Administrador familiar';
      case 'FAMILY_SECOND_ADMIN':
        return 'Administrador secundario';
      default:
        return 'Usuario';
    }
  }

  Future<String?> _prompt(
    String title,
    String label, {
    String initial = '',
    bool obscure = false,
    String? helper,
  }) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: obscure
            ? PasswordField(controller: ctrl, label: label, helper: helper)
            : TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: label,
                  helperText: helper,
                  border: const OutlineInputBorder(),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _editName(String current) async {
    final v = await _prompt('Cambiar nombre', 'Nombre', initial: current);
    if (v == null || v.isEmpty) return;
    try {
      await DataService.updateMyProfile(name: v);
      _reload();
      _snack('Nombre actualizado.');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _changeEmail() async {
    final current = await _prompt(
      'Confirma tu identidad',
      'Contraseña actual',
      obscure: true,
      helper: 'Por seguridad, confirma tu contraseña actual.',
    );
    if (current == null || current.isEmpty) return;
    final v = await _prompt(
      'Cambiar correo',
      'Nuevo correo',
      helper: 'Se enviará un enlace de confirmación al nuevo correo.',
    );
    if (v == null || v.isEmpty) return;
    try {
      await DataService.changeEmail(current, v);
      _reload();
      _snack('Te enviamos un correo de confirmación a $v.');
    } on InvalidCurrentPasswordException {
      _snack('La contraseña actual no es correcta.');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _changePassword() async {
    final current = await _prompt(
      'Confirma tu identidad',
      'Contraseña actual',
      obscure: true,
      helper: 'Por seguridad, confirma tu contraseña actual.',
    );
    if (current == null || current.isEmpty || !mounted) return;
    final v = await showDialog<String>(
      context: context,
      builder: (_) => const _NuevaPasswordDialog(),
    );
    if (v == null) return;
    try {
      await DataService.changePassword(current, v);
      _snack('Contraseña actualizada.');
    } on InvalidCurrentPasswordException {
      _snack('La contraseña actual no es correcta.');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final p = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(p['name'] ?? ''),
              subtitle: Text(p['email'] ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Cambiar nombre',
                onPressed: () => _editName((p['name'] as String?) ?? ''),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.badge),
              title: const Text('Rol'),
              subtitle: Text(_roleLabel(p['role'] as String?)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.alternate_email),
              title: const Text('Cambiar correo'),
              onTap: _changeEmail,
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Cambiar contraseña'),
              onTap: _changePassword,
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Verificación en dos pasos (2FA)'),
              subtitle: const Text('Opcional: un código extra al entrar'),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const MfaScreen())),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.palette_outlined),
                  const SizedBox(width: 16),
                  const Text('Tema'),
                  const Spacer(),
                  SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        tooltip: 'Sistema',
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        tooltip: 'Claro',
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        tooltip: 'Oscuro',
                      ),
                    ],
                    selected: {themeNotifier.value},
                    onSelectionChanged: (s) {
                      final m = s.first;
                      themeNotifier.value = m;
                      DataService.saveThemeMode(themeModeToString(m));
                    },
                  ),
                ],
              ),
            ),
            const Divider(),
            ValueListenableBuilder<A11yPrefs>(
              valueListenable: a11yNotifier,
              builder: (context, a, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.accessibility_new),
                        SizedBox(width: 16),
                        Text('Accesibilidad'),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 40),
                      const Text('A', style: TextStyle(fontSize: 13)),
                      Expanded(
                        child: Slider(
                          value: a.escalaTexto,
                          min: 0.85,
                          max: 1.45,
                          divisions: 4,
                          label: '${(a.escalaTexto * 100).round()} %',
                          onChanged: (v) =>
                              guardarA11y(a.copyWith(escalaTexto: v)),
                        ),
                      ),
                      const Text('A', style: TextStyle(fontSize: 22)),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 40),
                    title: const Text('Alto contraste'),
                    value: a.altoContraste,
                    onChanged: (v) => guardarA11y(a.copyWith(altoContraste: v)),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 40),
                    title: const Text('Texto en negrita'),
                    value: a.negrita,
                    onChanged: (v) => guardarA11y(a.copyWith(negrita: v)),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 40),
                    title: const Text('Reducir animaciones'),
                    value: a.sinAnimaciones,
                    onChanged: (v) =>
                        guardarA11y(a.copyWith(sinAnimaciones: v)),
                  ),
                ],
              ),
            ),
            const _AvisosSection(),
          ],
        );
      },
    );
  }
}

class _NuevaPasswordDialog extends StatefulWidget {
  const _NuevaPasswordDialog();

  @override
  State<_NuevaPasswordDialog> createState() => _NuevaPasswordDialogState();
}

class _NuevaPasswordDialogState extends State<_NuevaPasswordDialog> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();

  bool get _todoBien =>
      PasswordPolicy.cumple(_pass.text) && _pass.text == _confirm.text;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PasswordField(
              controller: _pass,
              label: 'Nueva contraseña',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _confirm,
              label: 'Repite la contraseña',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            PasswordChecklist(password: _pass.text, confirm: _confirm.text),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _todoBien ? () => Navigator.pop(context, _pass.text) : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _AvisosSection extends StatefulWidget {
  const _AvisosSection();

  @override
  State<_AvisosSection> createState() => _AvisosSectionState();
}

class _AvisosSectionState extends State<_AvisosSection> {
  Map<String, bool>? _prefs;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    DataService.preferenciasAviso().then((p) {
      if (mounted) setState(() => _prefs = p);
    }).catchError((_) {});
  }

  Future<void> _cambiar(String clave, bool valor) async {
    final antes = Map<String, bool>.from(_prefs!);
    setState(() {
      _prefs![clave] = valor;
      _guardando = true;
    });
    try {
      await DataService.guardarPreferenciasAviso(_prefs!);
    } catch (e) {
      if (mounted) {
        setState(() => _prefs = antes);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo guardar.'))));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _prefs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.notifications_active_outlined),
              SizedBox(width: 16),
              Text('Notificaciones'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 40, bottom: 4),
          child: Text('Elige de qué quieres recibir avisos.',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).hintColor)),
        ),
        if (p == null)
          const Padding(
            padding: EdgeInsets.only(left: 40, top: 8, bottom: 8),
            child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          ...DataService.categoriasAviso.entries.map((e) => SwitchListTile(
                contentPadding: const EdgeInsets.only(left: 40),
                title: Text(e.value),
                value: p[e.key] ?? true,
                onChanged:
                    _guardando ? null : (v) => _cambiar(e.key, v),
              )),
      ],
    );
  }
}
