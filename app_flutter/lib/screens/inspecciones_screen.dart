import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/out_report.dart';
import '../services/data_service.dart';
import '../services/media_service.dart';

class InspeccionesScreen extends StatefulWidget {
  const InspeccionesScreen({super.key});

  @override
  State<InspeccionesScreen> createState() => _InspeccionesScreenState();
}

class _InspeccionesScreenState extends State<InspeccionesScreen> {
  List<OutReport> _reports = [];
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
      final data = await DataService.outReports();

      data.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() => _reports = data);
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar las inspecciones.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDetail(OutReport report) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _InspeccionDetalle(report: report)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(
                  onPressed: _load,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (_reports.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fact_check_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text('No hay inspecciones'),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _reports.length,
      itemBuilder: (_, i) => _ReportCard(
        report: _reports[i],
        onTap: () => _openDetail(_reports[i]),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final OutReport report;
  final VoidCallback onTap;
  const _ReportCard({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('d MMM yyyy', 'es');
    final fileCount = report.mediaUrls.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      report.propertyName ?? 'Casa',
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Chip(
                    label: Text(report.generalStatus),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (report.rating != null)
                    Text(
                      '⭐ ${report.rating}/10',
                      style: theme.textTheme.bodyMedium,
                    ),
                  if (report.checkOut != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.logout, size: 16),
                        const SizedBox(width: 4),
                        Text(df.format(report.checkOut!)),
                      ],
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.collections_outlined, size: 16),
                      const SizedBox(width: 4),
                      Text('$fileCount archivos'),
                    ],
                  ),
                ],
              ),
              if (report.notes != null && report.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  report.notes!,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InspeccionDetalle extends StatelessWidget {
  final OutReport report;
  const _InspeccionDetalle({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('d MMM yyyy', 'es');
    final reservationId = report.reservationId;

    return Scaffold(
      appBar: AppBar(title: Text(report.propertyName ?? 'Inspección')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  report.propertyName ?? 'Casa',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Chip(label: Text(report.generalStatus)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              if (report.rating != null) Text('⭐ ${report.rating}/10'),
              if (report.checkOut != null)
                Text('Salida: ${df.format(report.checkOut!)}'),
              Text('${report.mediaUrls.length} archivos'),
            ],
          ),
          if (report.notes != null && report.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Notas', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(report.notes!),
          ],
          const Divider(height: 32),
          Text('Archivos', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          if (reservationId == null)
            const Text('No hay archivos disponibles para esta inspección.')
          else if (report.mediaUrls.isEmpty)
            const Text('Sin archivos.')
          else
            ...report.mediaUrls.map(
              (m) => _MediaItem(
                reservationId: reservationId,
                type: (m['type'] as String?) ?? 'photo',
                mediaKey: (m['key'] as String?) ?? '',
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaItem extends StatelessWidget {
  final String reservationId;
  final String type;
  final String mediaKey;
  const _MediaItem({
    required this.reservationId,
    required this.type,
    required this.mediaKey,
  });

  String get _name {
    final parts = mediaKey.split('/');
    return parts.isEmpty ? mediaKey : parts.last;
  }

  @override
  Widget build(BuildContext context) {
    if (mediaKey.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FutureBuilder<String>(
        future: MediaService.signedUrl(reservationId, mediaKey),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError || !snap.hasData) {
            return _errorBox(context, 'No se pudo cargar el archivo.');
          }
          final url = snap.data!;
          return type == 'video'
              ? _videoCard(context, url)
              : _photo(context, url);
        },
      ),
    );
  }

  Widget _photo(BuildContext context, String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        },
        errorBuilder: (context, error, stack) =>
            _errorBox(context, 'No se pudo mostrar la imagen.'),
      ),
    );
  }

  Widget _videoCard(BuildContext context, String url) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.movie_outlined, size: 32),
        title: Text(_name, overflow: TextOverflow.ellipsis),
        subtitle: const Text('Vídeo'),
        trailing: FilledButton.tonalIcon(
          onPressed: () => _showVideoUrl(context, url),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Abrir'),
        ),
      ),
    );
  }

  void _showVideoUrl(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_name),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(BuildContext context, String msg) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined),
          const SizedBox(width: 8),
          Flexible(child: Text(msg)),
        ],
      ),
    );
  }
}
