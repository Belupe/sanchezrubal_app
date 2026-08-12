import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/family_group.dart';
import '../models/sorteo.dart';
import '../services/data_service.dart';
import '../utils/errors.dart';

class SorteosScreen extends StatefulWidget {
  const SorteosScreen({super.key});

  @override
  State<SorteosScreen> createState() => _SorteosScreenState();
}

class _SorteosScreenState extends State<SorteosScreen> {
  String? _role;
  List<FamilyGroup> _groups = [];
  List<Sorteo> _sorteos = [];
  bool _loading = true;
  String? _error;

  final _name = TextEditingController();
  final List<TextEditingController> _quincenas = [TextEditingController()];
  final Set<String> _selectedGroupIds = {};
  bool _running = false;

  bool get _isPrincipal =>
      _role == 'MEGA_ADMIN' || _role == 'PRINCIPAL_ADMIN';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _quincenas) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final role = await DataService.currentRole();
      final groups = await DataService.familyGroups();
      final sorteos = await DataService.sorteos();
      setState(() {
        _role = role;
        _groups = groups;
        _sorteos = sorteos;
        _selectedGroupIds
          ..clear()
          ..addAll(groups.map((g) => g.id));
      });
    } catch (e) {
      setState(() => _error = 'No se pudieron cargar los sorteos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addQuincena() {
    setState(() => _quincenas.add(TextEditingController()));
  }

  void _removeQuincena(int index) {
    setState(() {
      final removed = _quincenas.removeAt(index);
      removed.dispose();
    });
  }

  void _resetForm() {
    _name.clear();
    for (final c in _quincenas) {
      c.dispose();
    }
    _quincenas
      ..clear()
      ..add(TextEditingController());
    _selectedGroupIds
      ..clear()
      ..addAll(_groups.map((g) => g.id));
  }

  Future<void> _runSorteo() async {
    final name = _name.text.trim();
    final quincenas = _quincenas
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (name.isEmpty) {
      _snack('Escribe el nombre del sorteo.');
      return;
    }
    if (quincenas.isEmpty) {
      _snack('Añade al menos una quincena o premio.');
      return;
    }
    if (_selectedGroupIds.isEmpty) {
      _snack('Selecciona al menos una familia.');
      return;
    }

    setState(() => _running = true);
    try {
      await DataService.runSorteo(
        name: name,
        quincenas: quincenas,
        groupIds: _selectedGroupIds.toList(),
      );
      final sorteos = await DataService.sorteos();
      if (!mounted) return;
      setState(() {
        _sorteos = sorteos;
        _resetForm();
      });
      _snack('Sorteo realizado.');
    } catch (e) {
      _snack(friendlyError(e, fallback: 'No se pudo realizar el sorteo.'));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _deleteSorteo(Sorteo s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar sorteo'),
        content: Text('¿Seguro que quieres borrar "${s.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await DataService.deleteSorteo(s.id);
      final sorteos = await DataService.sorteos();
      if (!mounted) return;
      setState(() => _sorteos = sorteos);
    } catch (e) {
      _snack(friendlyError(e, fallback: 'No se pudo borrar el sorteo.'));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Solo los administradores principales pueden ver los sorteos',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildNuevoSorteo(),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          _buildHistorial(),
        ],
      ),
    );
  }

  Widget _buildNuevoSorteo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nuevo sorteo',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Nombre del sorteo',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text('Quincenas / premios',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Puedes repetir un texto para sortear dos iguales.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        ...List.generate(_quincenas.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quincenas[i],
                    decoration: InputDecoration(
                      labelText: 'Premio ${i + 1}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Quitar',
                  onPressed: _quincenas.length > 1
                      ? () => _removeQuincena(i)
                      : null,
                ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addQuincena,
            icon: const Icon(Icons.add),
            label: const Text('Añadir premio'),
          ),
        ),
        const SizedBox(height: 16),
        Text('Familias',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (_groups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No hay familias disponibles.'),
          )
        else
          ..._groups.map((g) {
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(g.name),
              value: _selectedGroupIds.contains(g.id),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selectedGroupIds.add(g.id);
                } else {
                  _selectedGroupIds.remove(g.id);
                }
              }),
            );
          }),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _running ? null : _runSorteo,
          icon: _running
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.casino),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_running ? 'Sorteando...' : 'Iniciar sorteo'),
          ),
        ),
      ],
    );
  }

  Widget _buildHistorial() {
    final df = DateFormat('d MMM yyyy', 'es');
    final sorted = [..._sorteos]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Historial',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (sorted.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('Aún no hay sorteos')),
          )
        else
          ...sorted.map((s) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.name,
                            style:
                                Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Borrar sorteo',
                          onPressed: () => _deleteSorteo(s),
                        ),
                      ],
                    ),
                    Text(
                      df.format(s.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Avalado por: ${s.createdByName ?? 'Desconocido'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (s.seed != null)
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: s.seed!));
                          _snack('Semilla copiada.');
                        },
                        child: Text(
                          'Semilla: ${s.seed} (toca para copiar; con ella '
                          'cualquiera puede recomputar el resultado)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (s.resultados.isEmpty)
                      const Text('Sin resultados.')
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: s.resultados.map((r) {
                          return Chip(
                            label: Text('${r.groupName} → ${r.premio}'),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
