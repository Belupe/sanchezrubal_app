import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../models/announcement.dart';
import '../models/property.dart';
import '../services/data_service.dart';
import '../utils/errors.dart';
import '../services/realtime_service.dart';

class AnunciosScreen extends StatefulWidget {
  const AnunciosScreen({super.key});

  @override
  State<AnunciosScreen> createState() => _AnunciosScreenState();
}

class _AnunciosScreenState extends State<AnunciosScreen> {
  List<Announcement> _announcements = [];
  List<Property> _properties = [];
  String? _role;
  bool _loading = true;
  String? _error;

  RealtimeChannel? _channel;

  bool get _isPrincipal =>
      _role == 'MEGA_ADMIN' || _role == 'PRINCIPAL_ADMIN';

  @override
  void initState() {
    super.initState();
    _load();
    _channel = subscribeTables('anuncios', ['announcements'], () {
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
      final announcements = await DataService.announcements();
      final role = await DataService.currentRole();
      final isPrincipal = role == 'MEGA_ADMIN' || role == 'PRINCIPAL_ADMIN';
      final props = isPrincipal ? await DataService.properties() : <Property>[];
      setState(() {
        _announcements = announcements;
        _role = role;
        _properties = props;
      });
    } catch (e) {
      setState(() => _error = 'No se pudieron cargar los anuncios.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _publish() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AnnouncementDialog(properties: _properties),
    );
    if (created == true) _load();
  }

  Future<void> _delete(Announcement a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar anuncio'),
        content: Text('¿Seguro que quieres borrar "${a.title}"?'),
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
      await DataService.deleteAnnouncement(a.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo borrar el anuncio.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
      floatingActionButton: _isPrincipal
          ? FloatingActionButton.extended(
              onPressed: _publish,
              icon: const Icon(Icons.add),
              label: const Text('Publicar'),
            )
          : null,
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
    if (_announcements.isEmpty) {
      return const Center(child: Text('No hay anuncios todavía'));
    }

    final df = DateFormat('d MMM yyyy', 'es');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _announcements.length,
        itemBuilder: (_, i) {
          final a = _announcements[i];
          final chips = a.propertyNames.isEmpty
              ? [const Chip(label: Text('General'))]
              : a.propertyNames
                  .map((n) => Chip(label: Text(n)))
                  .toList();
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          a.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      if (_isPrincipal)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Borrar',
                          onPressed: () => _delete(a),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(a.content),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: chips,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Publicado por ${a.authorName ?? 'Desconocido'} · ${df.format(a.createdAt)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AnnouncementDialog extends StatefulWidget {
  final List<Property> properties;
  const _AnnouncementDialog({required this.properties});

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  final Set<String> _selected = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (title.isEmpty || content.isEmpty) {
      setState(() => _error = 'El título y el contenido son obligatorios.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DataService.createAnnouncement(
        title: title,
        content: content,
        propertyIds: _selected.toList(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error =
          friendlyError(e, fallback: 'No se pudo publicar el anuncio.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Publicar anuncio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Título',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _content,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Contenido',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.properties.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Casas (opcional)'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.properties.map((p) {
                  final sel = _selected.contains(p.id);
                  return FilterChip(
                    label: Text(p.name),
                    selected: sel,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selected.add(p.id);
                      } else {
                        _selected.remove(p.id);
                      }
                    }),
                  );
                }).toList(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Publicar'),
        ),
      ],
    );
  }
}
