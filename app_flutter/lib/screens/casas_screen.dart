import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../models/property.dart';
import '../services/data_service.dart';
import '../services/realtime_service.dart';
import 'property_calendar_screen.dart';

class CasasScreen extends StatefulWidget {
  const CasasScreen({super.key});

  @override
  State<CasasScreen> createState() => _CasasScreenState();
}

class _CasasScreenState extends State<CasasScreen> {
  List<Property> _props = [];
  String? _role;
  bool _loading = true;
  String? _error;

  RealtimeChannel? _channel;

  bool get _isPrincipal => _role == 'MEGA_ADMIN' || _role == 'PRINCIPAL_ADMIN';

  @override
  void initState() {
    super.initState();
    _load();
    _channel = subscribeTables('casas', ['properties'], () {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) supabase.removeChannel(ch);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final props = await DataService.properties();
      final role = await DataService.currentRole();
      if (!mounted) return;
      setState(() {
        _props = props;
        _role = role;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudieron cargar los domicilios.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(Property p) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PropertyCalendarScreen(property: p)),
    );
  }

  Future<void> _addOrEdit({Property? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final desc = TextEditingController(text: existing?.description ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Nuevo domicilio' : 'Editar domicilio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                  labelText: 'Nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: desc,
              decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  border: OutlineInputBorder()),
            ),
          ],
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
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      if (existing == null) {
        await DataService.createProperty(
            name: name.text.trim(), description: desc.text.trim());
      } else {
        await DataService.updateProperty(existing.id,
            name: name.text.trim(), description: desc.text.trim());
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _delete(Property p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar domicilio'),
        content: Text('¿Eliminar "${p.name}"? Se borrarán también sus reservas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DataService.deleteProperty(p.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _isPrincipal
          ? FloatingActionButton.extended(
              onPressed: () => _addOrEdit(),
              icon: const Icon(Icons.add),
              label: const Text('Añadir'),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        ]),
      );
    }
    if (_props.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.maps_home_work, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('No hay domicilios todavía.'),
          if (_isPrincipal)
            TextButton(
                onPressed: () => _addOrEdit(),
                child: const Text('Añadir el primero')),
        ]),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 150,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _props.length,
      itemBuilder: (_, i) {
        final p = _props[i];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _open(p),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.home_work,
                          color: Theme.of(context).colorScheme.primary),
                      const Spacer(),
                      if (_isPrincipal)
                        PopupMenuButton<String>(
                          onSelected: (v) =>
                              v == 'edit' ? _addOrEdit(existing: p) : _delete(p),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Editar')),
                            PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(p.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if ((p.description ?? '').isNotEmpty)
                    Text(p.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  Row(
                    children: [
                      Text('Ver calendario',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary)),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
