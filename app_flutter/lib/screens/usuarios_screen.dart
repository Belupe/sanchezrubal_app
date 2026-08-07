import 'package:flutter/material.dart';

import '../models/family_group.dart';
import '../models/profile.dart';
import '../services/admin_service.dart';
import '../services/data_service.dart';
import '../utils/colors.dart';
import '../utils/errors.dart';
import 'group_detail_screen.dart';

class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  String? _role;
  Map<String, dynamic>? _myProfile;
  List<FamilyGroup> _groups = [];
  List<Profile> _profiles = [];
  bool _loading = true;
  String? _error;

  String? get _myId => _myProfile?['id'] as String?;

  bool get _isPrincipal => _role == 'MEGA_ADMIN' || _role == 'PRINCIPAL_ADMIN';

  /// Qué eres DENTRO de tu casa. Desde la migración 0025 es un dato distinto
  /// del rango global: un mega administrador puede ser un miembro más.
  String? get _miPapelEnCasa => _myProfile?['group_role'] as String?;

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
      final role = await DataService.currentRole();
      final groups = await DataService.familyGroups();
      final profile = await DataService.myProfile();
      // Solo los principales pueden listar a todo el mundo; para el resto la
      // consulta la corta el RLS, así que ni se pide.
      final esPrincipal = role == 'MEGA_ADMIN' || role == 'PRINCIPAL_ADMIN';
      final profiles = esPrincipal ? await DataService.allProfiles() : <Profile>[];
      // Los administradores primero y, dentro de cada rango, por nombre.
      // Primero por rango global y, a igualdad, por el papel en la casa. Son
      // dos escalas distintas desde la migración 0025.
      profiles.sort((a, b) {
        const global = {'MEGA_ADMIN': 0, 'PRINCIPAL_ADMIN': 1, 'USER': 2};
        const casa = {'FAMILY_ADMIN': 0, 'FAMILY_SECOND_ADMIN': 1, 'MEMBER': 2};
        var c = (global[a.role] ?? 9).compareTo(global[b.role] ?? 9);
        if (c != 0) return c;
        c = (casa[a.groupRole] ?? 9).compareTo(casa[b.groupRole] ?? 9);
        return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _role = role;
        _groups = groups;
        _myProfile = profile;
        _profiles = profiles;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudieron cargar los datos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Ejecuta una acción de gestión y recarga; si falla, lo cuenta sin romper.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<bool> _confirm(String titulo, String cuerpo) async =>
      (await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(titulo),
          content: Text(cuerpo),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmar')),
          ],
        ),
      )) ??
      false;

  String _nombreGrupo(String? id) {
    if (id == null) return 'Sin grupo';
    for (final g in _groups) {
      if (g.id == id) return g.name;
    }
    return 'Grupo desconocido';
  }

  /// El admin familiar gestiona los miembros de SU grupo (permiso y expulsión);
  /// los principales, los de cualquiera. Dar de baja cuentas sigue siendo solo
  /// de principal, y va por `puedeEliminarCuentas`.
  bool _gestionaGrupo(FamilyGroup g) =>
      _isPrincipal ||
      (_miPapelEnCasa == 'FAMILY_ADMIN' &&
          g.id == (_myProfile?['family_group_id'] as String?));

  Future<void> _openGroup(FamilyGroup g) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupDetailScreen(
        group: g,
        isPrincipal: _gestionaGrupo(g),
        puedeEliminarCuentas: _isPrincipal,
      ),
    ));
    _load();
  }

  Future<void> _showCreateGroupDialog() async {
    final groupName = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Crear grupo'),
        content: TextField(
          controller: groupName,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Nombre del grupo', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Crear')),
        ],
      ),
    );
    if (ok != true || groupName.text.trim().isEmpty) return;
    try {
      await AdminService.createGroup(
        groupName: groupName.text.trim(),
        color: familyColorForIndex(_groups.length),
      );
      _snack('Grupo creado. Añade sus miembros desde el grupo.');
      _load();
    } catch (e) {
      _snack(friendlyError(e, fallback: 'No se pudo crear el grupo.'));
    }
  }

  Future<void> _showInviteUserDialog() async {
    final name = TextEditingController();
    final email = TextEditingController();
    String role = 'MEMBER';
    String? groupId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Invitar usuario'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'Nombre', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(
                    labelText: 'Rol', border: OutlineInputBorder()),
                // Un admin familiar solo reparte POR DEBAJO de sí mismo. La
                // función admin-users lo rechazaría igualmente, pero no tiene
                // sentido ofrecer opciones que van a fallar.
                items: [
                  const DropdownMenuItem(
                      value: 'MEMBER', child: Text('Miembro')),
                  const DropdownMenuItem(
                      value: 'FAMILY_SECOND_ADMIN',
                      child: Text('Administrador secundario')),
                  if (_isPrincipal) ...[
                    const DropdownMenuItem(
                        value: 'FAMILY_ADMIN',
                        child: Text('Administrador familiar')),
                    const DropdownMenuItem(
                        value: 'PRINCIPAL_ADMIN',
                        child: Text('Administrador principal')),
                  ],
                ],
                onChanged: (v) => setLocal(() => role = v ?? 'MEMBER'),
              ),
              const SizedBox(height: 12),
              // El admin familiar solo da de alta en SU grupo: no elige. El
              // servidor impone el suyo aunque el cliente mande otro.
              if (_isPrincipal)
                DropdownButtonFormField<String>(
                  initialValue: groupId,
                  decoration: const InputDecoration(
                      labelText: 'Grupo (opcional)',
                      border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<String>(
                        value: null, child: Text('Sin grupo')),
                    ..._groups.map((g) =>
                        DropdownMenuItem(value: g.id, child: Text(g.name))),
                  ],
                  onChanged: (v) => setLocal(() => groupId = v),
                )
              else
                InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Grupo', border: OutlineInputBorder()),
                  child: Text(_nombreGrupo(
                      _myProfile?['family_group_id'] as String?)),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Invitar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final res = await AdminService.inviteUser(
        name: name.text.trim(),
        email: email.text.trim(),
        role: role,
        familyGroupId: groupId,
      );
      // [B-03] La cuenta ya existe y reasignaría grupo/rol: confirmar y reintentar.
      if (res['requiresConfirm'] == true) {
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('La cuenta ya existe'),
            content: Text(res['message']?.toString() ??
                'Ya existe una cuenta con ese email. Al continuar se '
                    'reasignará su grupo y/o rol.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Vincular de todos modos')),
            ],
          ),
        );
        if (confirm != true) return;
        await AdminService.inviteUser(
          name: name.text.trim(),
          email: email.text.trim(),
          role: role,
          familyGroupId: groupId,
          confirmRelink: true,
        );
      }
      _snack('Invitación enviada por correo.');
      _load();
    } catch (e) {
      _snack(friendlyError(e, fallback: 'No se pudo enviar la invitación.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        ]),
      );
    }

    if (!_isPrincipal) {
      // No principal: solo su grupo. El admin familiar puede además dar de alta
      // gente en él y gestionarla desde dentro; el resto lo ve en solo lectura.
      final myGroupId = _myProfile?['family_group_id'] as String?;
      final mine = _groups.where((g) => g.id == myGroupId).toList();
      final esAdminFamiliar = _miPapelEnCasa == 'FAMILY_ADMIN' && mine.isNotEmpty;
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (esAdminFamiliar)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.tonalIcon(
                onPressed: _showInviteUserDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('Invitar usuario'),
              ),
            ),
          if (mine.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No perteneces a ningún grupo.')),
            )
          else
            _groupCard(mine.first),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              esAdminFamiliar
                  ? 'Puedes invitar y gestionar a los miembros de tu grupo. '
                      'Para dar de baja una cuenta por completo, habla con un '
                      'administrador principal.'
                  : 'Para gestionar usuarios contacta con un administrador principal.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      );
    }

    // Dos pestañas: los grupos por un lado y TODOS los usuarios por otro. Antes
    // solo se listaban grupos, así que quien no pertenecía a ninguno no aparecía
    // en ninguna parte y no había forma de cambiarle el rol ni de eliminarlo.
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _showCreateGroupDialog,
                  icon: const Icon(Icons.group_add),
                  label: const Text('Crear grupo'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _showInviteUserDialog,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Invitar usuario'),
                ),
              ),
            ]),
          ),
          const TabBar(tabs: [
            Tab(text: 'Grupos'),
            Tab(text: 'Usuarios'),
          ]),
          Expanded(
            child: TabBarView(
              children: [_pestanyaGrupos(), _pestanyaUsuarios()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pestanyaGrupos() {
    if (_groups.isEmpty) {
      return const Center(child: Text('No hay grupos todavía.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 120,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _groups.length,
      itemBuilder: (_, i) => _groupCard(_groups[i]),
    );
  }

  Widget _pestanyaUsuarios() {
    if (_profiles.isEmpty) {
      return const Center(child: Text('No hay usuarios todavía.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _profiles.length,
      itemBuilder: (_, i) => _userCard(_profiles[i]),
    );
  }

  Future<void> _eliminarUsuario(Profile p) async {
    final quien = p.name.trim().isNotEmpty ? p.name.trim() : (p.email ?? 'este usuario');
    final ok = await _confirm(
      'Eliminar usuario',
      'Se eliminará la cuenta de $quien y no podrá volver a entrar. '
      'Esta acción no se puede deshacer.',
    );
    if (!ok) return;
    await _run(() => AdminService.deleteUser(p.id));
  }

  Widget _userCard(Profile p) {
    final esYo = p.id == _myId;
    // No se edita ni la cuenta propia ni la de un mega administrador: lo primero
    // evita quitarte los permisos sin querer y quedarte fuera; lo segundo, que la
    // instalación se quede sin nadie capaz de administrarla.
    final editable = !esYo && p.role != 'MEGA_ADMIN';
    final quien = p.name.trim().isNotEmpty ? p.name.trim() : (p.email ?? '?');
    // Si el grupo guardado ya no existe, el desplegable no puede preseleccionarlo.
    final grupoActual =
        _groups.any((g) => g.id == p.familyGroupId) ? p.familyGroupId : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(child: Text(quien.substring(0, 1).toUpperCase())),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(quien,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (p.email != null && p.email != quien)
                      Text(p.email!,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (esYo) const Chip(label: Text('Tú')),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, children: [
              // Rango global: solo se enseña si es alguien que administra la
              // app. 'Usuario' a secas no aporta nada.
              if (p.role != 'USER') Chip(label: Text(p.roleLabel)),
              Chip(label: Text(_nombreGrupo(p.familyGroupId))),
              if (p.groupRoleLabel != null)
                Chip(label: Text(p.groupRoleLabel!)),
            ]),
            if (editable) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: const [
                  'MEMBER',
                  'FAMILY_ADMIN',
                  'FAMILY_SECOND_ADMIN',
                ].contains(p.groupRole)
                    ? p.groupRole
                    : 'MEMBER',
                isDense: true,
                decoration: const InputDecoration(
                    labelText: 'Permiso en la casa',
                    isDense: true,
                    border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'MEMBER', child: Text('Miembro')),
                  DropdownMenuItem(
                      value: 'FAMILY_SECOND_ADMIN',
                      child: Text('Administrador secundario')),
                  DropdownMenuItem(
                      value: 'FAMILY_ADMIN',
                      child: Text('Administrador familiar')),
                ],
                onChanged: (v) {
                  if (v != null && v != p.groupRole) {
                    _run(() => DataService.setGroupRole(p.id, v));
                  }
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: grupoActual,
                isDense: true,
                decoration: const InputDecoration(
                    labelText: 'Grupo',
                    isDense: true,
                    border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('Sin grupo')),
                  ..._groups.map(
                      (g) => DropdownMenuItem(value: g.id, child: Text(g.name))),
                ],
                onChanged: (v) {
                  if (v != grupoActual) {
                    _run(() => DataService.setMemberGroup(p.id, v));
                  }
                },
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => _eliminarUsuario(p),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Eliminar usuario'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _groupCard(FamilyGroup g) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openGroup(g),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                    backgroundColor: colorFromHex(g.color), radius: 12),
                const Spacer(),
                const Icon(Icons.chevron_right),
              ]),
              const Spacer(),
              Text(g.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text('${g.members.length} miembros',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
