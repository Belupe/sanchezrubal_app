import 'package:flutter/material.dart';
import '../models/family_group.dart';
import '../models/profile.dart';
import '../services/admin_service.dart';
import '../services/data_service.dart';
import '../utils/colors.dart';
import '../utils/errors.dart';

class GroupDetailScreen extends StatefulWidget {
  final FamilyGroup group;

  final bool isPrincipal;

  final bool puedeEliminarCuentas;
  const GroupDetailScreen(
      {super.key,
      required this.group,
      required this.isPrincipal,
      this.puedeEliminarCuentas = false});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late FamilyGroup _group = widget.group;
  bool _loading = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final groups = await DataService.familyGroups();
      final g = groups.where((x) => x.id == _group.id).toList();
      if (!mounted) return;
      if (g.isEmpty) {
        Navigator.pop(context);
        return;
      }
      setState(() => _group = g.first);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _reload();
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      (await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
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

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _group.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar nombre del grupo'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Nombre', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      _run(() => DataService.updateFamilyGroup(_group.id, name: ctrl.text.trim()));
    }
  }

  Future<void> _deleteGroup() async {
    if (!await _confirm('Eliminar grupo', '¿Eliminar "${_group.name}"?')) return;
    try {
      await DataService.deleteFamilyGroup(_group.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack(friendlyError(e, fallback: 'No se pudo eliminar el grupo.'));
    }
  }

  Future<void> _addMember() async {
    final name = TextEditingController();
    final email = TextEditingController();
    String role = 'MEMBER';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Añadir miembro'),
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
                    labelText: 'Permiso', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'MEMBER', child: Text('Miembro')),
                  DropdownMenuItem(
                      value: 'FAMILY_ADMIN',
                      child: Text('Administrador familiar')),
                  DropdownMenuItem(
                      value: 'FAMILY_SECOND_ADMIN',
                      child: Text('Administrador secundario')),
                ],
                onChanged: (v) => setLocal(() => role = v ?? 'MEMBER'),
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
        familyGroupId: _group.id,
      );

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
          familyGroupId: _group.id,
          confirmRelink: true,
        );
      }
      _snack('Invitación enviada por correo.');
      await _reload();
    } catch (e) {
      _snack(friendlyError(e, fallback: 'No se pudo enviar la invitación.'));
    }
  }

  Future<void> _expulsar(Profile m) async {
    if (await _confirm('Expulsar del grupo',
        '¿Quitar a "${m.name}" de este grupo? Seguirá existiendo como usuario.')) {
      _run(() => DataService.setMemberGroup(m.id, null));
    }
  }

  Future<void> _deleteUser(Profile m) async {
    if (await _confirm('Eliminar usuario',
        '¿Eliminar por completo a "${m.name}"?')) {
      _run(() => AdminService.deleteUser(m.id));
    }
  }

  Widget _memberCard(Profile m) {
    final canManage = widget.isPrincipal;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                  radius: 18,
                  child: Text(
                      m.name.isNotEmpty ? m.name[0].toUpperCase() : '?')),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(m.email ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 10),
            if (canManage) ...[
              DropdownButtonFormField<String>(
                initialValue: const ['MEMBER', 'FAMILY_ADMIN', 'FAMILY_SECOND_ADMIN']
                        .contains(m.groupRole)
                    ? m.groupRole
                    : 'MEMBER',
                isDense: true,
                decoration: const InputDecoration(
                    labelText: 'Permiso',
                    isDense: true,
                    border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(
                      value: 'MEMBER', child: Text('Miembro')),
                  const DropdownMenuItem(
                      value: 'FAMILY_SECOND_ADMIN',
                      child: Text('Admin. secundario')),

                  if (widget.puedeEliminarCuentas)
                    const DropdownMenuItem(
                        value: 'FAMILY_ADMIN', child: Text('Admin. familiar')),
                ],
                onChanged: (v) {
                  if (v != null && v != m.groupRole) {
                    _run(() => DataService.setGroupRole(m.id, v));
                  }
                },
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _expulsar(m),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Expulsar'),
                  ),
                ),
                if (widget.puedeEliminarCuentas) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Eliminar usuario',
                    color: Colors.red,
                    onPressed: () => _deleteUser(m),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ]),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(label: Text(m.groupRoleLabel ?? m.roleLabel)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = _group.members;
    return Scaffold(
      appBar: AppBar(
        title: Text(_group.name),
        actions: widget.isPrincipal
            ? [
                IconButton(
                    onPressed: _editName,
                    icon: const Icon(Icons.edit),
                    tooltip: 'Editar nombre'),
                IconButton(
                    onPressed: _deleteGroup,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Eliminar grupo'),
              ]
            : null,
      ),
      floatingActionButton: widget.isPrincipal
          ? FloatingActionButton.extended(
              onPressed: _addMember,
              icon: const Icon(Icons.person_add),
              label: const Text('Añadir miembro'),
            )
          : null,
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: colorFromHex(_group.color).withValues(alpha: 0.12),
            child: Row(children: [
              CircleAvatar(
                  backgroundColor: colorFromHex(_group.color), radius: 14),
              const SizedBox(width: 12),
              Text('${members.length} miembros',
                  style: Theme.of(context).textTheme.titleMedium),
            ]),
          ),
          Expanded(
            child: members.isEmpty
                ? const Center(
                    child: Text('Este grupo no tiene miembros.\n'
                        'Usa "Añadir miembro" para invitar.'),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 340,
                      mainAxisExtent: 200,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: members.length,
                    itemBuilder: (_, i) => _memberCard(members[i]),
                  ),
          ),
        ],
      ),
    );
  }
}
