import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../main.dart';
import '../services/media_service.dart';
import '../utils/errors.dart';

bool get _esEscritorio =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

class InspectionScreen extends StatefulWidget {
  final String reservationId;
  const InspectionScreen({super.key, required this.reservationId});

  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  final _picker = ImagePicker();
  final _notes = TextEditingController();
  final List<Map<String, String>> _media = [];
  String _status = 'OK';
  bool _busy = false;
  String? _msg;

  Map<String, dynamic>? _reservation;

  @override
  void initState() {
    super.initState();
    _loadReservation();
  }

  Future<void> _loadReservation() async {
    final r = await supabase
        .from('reservations')
        .select('property_id, start_date, end_date')
        .eq('id', widget.reservationId)
        .maybeSingle();
    setState(() => _reservation = r);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  String _contentType(String name, bool video) {
    final n = name.toLowerCase();
    if (video) return n.endsWith('.mov') ? 'video/quicktime' : 'video/mp4';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _add({required bool video, ImageSource source = ImageSource.gallery}) async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final XFile? x = video
          ? await _picker.pickVideo(source: source)
          // Compresión suave: se conserva el detalle, solo se acota el tamaño.
          : await _picker.pickImage(
              source: source,
              imageQuality: 85,
              maxWidth: 1920,
              maxHeight: 1920,
            );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final key = await MediaService.upload(
        reservationId: widget.reservationId,
        filename: x.name,
        bytes: bytes,
        contentType: _contentType(x.name, video),
      );
      setState(() => _media.add({
            'type': video ? 'video' : 'photo',
            'key': key,
            'name': x.name,
          }));
    } catch (e) {
      setState(() => _msg = friendlyError(e, fallback: 'No se pudo subir el archivo.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final r = _reservation;
    if (r == null) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await supabase.from('out_reports').insert({
        'reservation_id': widget.reservationId,
        'property_id': r['property_id'],
        'check_in': r['start_date'],
        'check_out': r['end_date'],
        'general_status': _status,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'media_urls': _media,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inspección guardada.')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _msg = friendlyError(e, fallback: 'No se pudo guardar.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inspección de salida')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(
                labelText: 'Estado general', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'OK', child: Text('Todo correcto')),
              DropdownMenuItem(value: 'DAÑOS', child: Text('Con daños')),
              DropdownMenuItem(value: 'FALTANTES', child: Text('Faltan cosas')),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'OK'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Notas', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Text('Fotos y vídeos (${_media.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [

              if (!_esEscritorio)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _add(video: false, source: ImageSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Cámara'),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _add(video: false),
                icon: Icon(_esEscritorio ? Icons.image_outlined : Icons.photo_library),
                label: Text(_esEscritorio ? 'Elegir foto' : 'Galería'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _add(video: true),
                icon: const Icon(Icons.videocam),
                label: Text(_esEscritorio ? 'Elegir vídeo' : 'Vídeo'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._media.map((m) => ListTile(
                dense: true,
                leading: Icon(m['type'] == 'video' ? Icons.movie : Icons.image),
                title: Text(m['name'] ?? m['key']!, overflow: TextOverflow.ellipsis),
              )),
          if (_msg != null) ...[
            const SizedBox(height: 12),
            Text(_msg!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy || _reservation == null ? null : _save,
            icon: _busy
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('Guardar inspección'),
          ),
        ],
      ),
    );
  }
}
