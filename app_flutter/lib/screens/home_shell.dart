import 'package:flutter/material.dart';

import '../main.dart';
import '../services/data_service.dart';
import '../services/push_service.dart';
import '../services/update_service.dart';
import '../utils/password_policy.dart';
import 'anuncios_screen.dart';
import 'casas_screen.dart';
import 'config_screen.dart';
import 'inspecciones_screen.dart';
import 'mfa_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
    // Registra el dispositivo para push (no bloqueante; se auto-desactiva si
    // Firebase aún no está configurado).
    PushService.init();
    // Tras entrar, comprueba si hay APK nuevo (solo Android; no bloqueante).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.checkForUpdate(context);
    });
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
        if (_isPrincipal)
          const _NavItem('Sorteos', Icons.casino, SorteosScreen()),
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
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cerrar sesión')),
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
                    color: Theme.of(context).colorScheme.primary),
                child: const Align(
                  alignment: Alignment.bottomLeft,
                  child: Text('Portal Familia',
                      style: TextStyle(color: Colors.white, fontSize: 22)),
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
      body: current.screen,
    );
  }
}

/// Pestaña de perfil: datos, cambiar correo/contraseña, tema y logout.
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
        return 'Miembro';
    }
  }

  Future<String?> _prompt(String title, String label,
      {String initial = '', bool obscure = false, String? helper}) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          obscureText: obscure,
          decoration: InputDecoration(
              labelText: label, helperText: helper, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Guardar')),
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
      _snack('Error: $e');
    }
  }

  Future<void> _changeEmail() async {
    // [M-12] Confirma identidad con la contraseña actual antes de cambiar.
    final current = await _prompt('Confirma tu identidad', 'Contraseña actual',
        obscure: true, helper: 'Por seguridad, confirma tu contraseña actual.');
    if (current == null || current.isEmpty) return;
    final v = await _prompt('Cambiar correo', 'Nuevo correo',
        helper: 'Se enviará un enlace de confirmación al nuevo correo.');
    if (v == null || v.isEmpty) return;
    try {
      await DataService.changeEmail(current, v);
      _reload();
      _snack('Te enviamos un correo de confirmación a $v.');
    } on InvalidCurrentPasswordException {
      _snack('La contraseña actual no es correcta.');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _changePassword() async {
    // [M-12] Confirma identidad con la contraseña actual antes de cambiar.
    final current = await _prompt('Confirma tu identidad', 'Contraseña actual',
        obscure: true, helper: 'Por seguridad, confirma tu contraseña actual.');
    if (current == null || current.isEmpty) return;
    final v = await _prompt('Cambiar contraseña', 'Nueva contraseña',
        obscure: true, helper: PasswordPolicy.helpText);
    if (v == null) return;
    // [M-13] Espejo de la política del servidor (mínimo 10, no solo dígitos).
    final err = PasswordPolicy.validate(v);
    if (err != null) {
      _snack(err);
      return;
    }
    try {
      await DataService.changePassword(current, v);
      _snack('Contraseña actualizada.');
    } on InvalidCurrentPasswordException {
      _snack('La contraseña actual no es correcta.');
    } catch (e) {
      _snack('Error: $e');
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
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MfaScreen())),
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
                          tooltip: 'Sistema'),
                      ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                          tooltip: 'Claro'),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                          tooltip: 'Oscuro'),
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
          ],
        );
      },
    );
  }
}
