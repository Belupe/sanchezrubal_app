import 'package:flutter/material.dart';

import '../models/family_group.dart';
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
  bool _loading = true;
  String? _error;

  bool get _isPrincipal => _role == 'MEGA_ADMIN' || _role == 'PRINCIPAL_ADMIN';

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
      if (!mounted) return;
      setState(() {
        _role = role;
        _groups = groups;
        _myProfile = profile;
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

  Future<void> _openGroup(FamilyGroup g) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupDetailScreen(group: g, isPrincipal: _isPrincipal),
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
                items: const [
                  DropdownMenuItem(value: 'MEMBER', child: Text('Miembro')),
                  DropdownMenuItem(
                      value: 'FAMILY_ADMIN',
                      child: Text('Administrador familiar')),
                  DropdownMenuItem(
                      value: 'FAMILY_SECOND_ADMIN',
                      child: Text('Administrador secundario')),
                  DropdownMenuItem(
                      value: 'PRINCIPAL_ADMIN',
                      child: Text('Administrador principal')),
                ],
                onChanged: (v) => setLocal(() => role = v ?? 'MEMBER'),
              ),
              const SizedBox(height: 12),
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
      // No principal: solo su grupo, en ventana, solo lectura.
      final myGroupId = _myProfile?['family_group_id'] as String?;
      final mine = _groups.where((g) => g.id == myGroupId).toList();
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (mine.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No perteneces a ningún grupo.')),
            )
          else
            _groupCard(mine.first),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Para gestionar usuarios contacta con un administrador principal.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      );
    }

    return Column(
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
        Expanded(
          child: _groups.isEmpty
              ? const Center(child: Text('No hay grupos todavía.'))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisExtent: 120,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _groups.length,
                  itemBuilder: (_, i) => _groupCard(_groups[i]),
                ),
        ),
      ],
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
