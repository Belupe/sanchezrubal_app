import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/audit_log.dart';
import '../services/data_service.dart';

/// Ventana de registros/auditoría: quién ha creado, modificado o eliminado
/// reservas (los datos los registra automáticamente la base de datos).
class RegistrosScreen extends StatefulWidget {
  const RegistrosScreen({super.key});

  @override
  State<RegistrosScreen> createState() => _RegistrosScreenState();
}

class _RegistrosScreenState extends State<RegistrosScreen> {
  List<AuditLog> _logs = [];
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
      final logs = await DataService.auditLogs();
      if (!mounted) return;
      setState(() => _logs = logs);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudieron cargar los registros.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  (IconData, Color) _icon(String action) {
    switch (action) {
      case 'CREATE':
        return (Icons.add, Colors.green);
      case 'UPDATE':
        return (Icons.edit, Colors.blue);
      case 'DELETE':
        return (Icons.delete, Colors.red);
      default:
        return (Icons.info_outline, Colors.grey);
    }
  }

  String _range(AuditLog log) {
    final s = log.snapshot;
    final start = s?['start_date'];
    final end = s?['end_date'];
    if (start is String && end is String) {
      final df = DateFormat('d MMM yyyy', 'es');
      return '${df.format(DateTime.parse(start))} → ${df.format(DateTime.parse(end))}';
    }
    return '';
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
    if (_logs.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text('Aún no hay registros de actividad.'),
        ]),
      );
    }

    final dfFull = DateFormat("d MMM yyyy, HH:mm", 'es');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _logs.length,
        itemBuilder: (_, i) {
          final log = _logs[i];
          final (icon, color) = _icon(log.action);
          final range = _range(log);
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color),
              ),
              title: Text('${log.actionLabel} ${log.entityLabel}'),
              subtitle: Text(
                '${range.isNotEmpty ? '$range\n' : ''}'
                'Por ${log.userName ?? 'Sistema'} · ${dfFull.format(log.createdAt.toLocal())}',
              ),
              isThreeLine: range.isNotEmpty,
            ),
          );
        },
      ),
    );
  }
}
