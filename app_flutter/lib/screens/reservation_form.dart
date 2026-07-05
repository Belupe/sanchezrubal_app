import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/property.dart';
import '../services/data_service.dart';
import '../utils/errors.dart';

class ReservationForm extends StatefulWidget {
  final DateTime? initialDay;
  final Property? property;
  const ReservationForm({super.key, this.initialDay, this.property});

  @override
  State<ReservationForm> createState() => _ReservationFormState();
}

class _ReservationFormState extends State<ReservationForm> {
  List<Property> _properties = [];
  String? _propertyId;
  String? _familyGroupId;
  String? _role;
  late DateTime _start;
  late DateTime _end;
  int _guests = 1;
  int _minDays = 15;
  final _notes = TextEditingController();
  bool _maintenance = false;
  bool _saving = false;
  String? _error;

  bool get _isPrincipal =>
      _role == 'MEGA_ADMIN' || _role == 'PRINCIPAL_ADMIN';

  @override
  void initState() {
    super.initState();
    final base = widget.initialDay ?? DateTime.now();
    _start = DateTime(base.year, base.month, base.day);
    _end = _start.add(const Duration(days: 1));
    _init();
  }

  Future<void> _init() async {
    final profile = await DataService.myProfile();
    final minDays = await DataService.maxReservationDays();
    final props = widget.property != null
        ? [widget.property!]
        : await DataService.properties();
    if (!mounted) return;
    setState(() {
      _minDays = minDays;
      _end = _start.add(Duration(days: minDays));
      _properties = props;
      _propertyId =
          widget.property?.id ?? (props.isNotEmpty ? props.first.id : null);
      _role = profile?['role'] as String?;
      _familyGroupId = profile?['family_group_id'] as String?;
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        // Al elegir la entrada, la salida salta automáticamente al mínimo.
        _end = _start.add(Duration(days: _minDays));
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_propertyId == null) {
      setState(() => _error = 'No hay casas. Un administrador debe crearlas primero.');
      return;
    }
    if (!_end.isAfter(_start)) {
      setState(() => _error = 'La fecha de salida debe ser posterior a la de entrada.');
      return;
    }
    if (_end.difference(_start).inDays < _minDays) {
      setState(() => _error = 'La reserva debe ser de al menos $_minDays días.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await DataService.createReservation(
        propertyId: _propertyId!,
        start: _start,
        end: _end,
        guestCount: _guests,
        familyGroupId: _familyGroupId,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        isMaintenance: _maintenance,
      );
      await DataService.sendReservationEmail(r.id, maintenance: _maintenance);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Si el rechazo es por solapamiento, ofrecemos la lista de espera.
      if (e.toString().contains('Ya existe una reserva')) {
        if (mounted) await _offerWaitlist();
      } else {
        setState(() => _error =
            friendlyError(e, fallback: 'No se pudo crear la reserva.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Diálogo: apuntarse a la lista de espera de esas fechas ocupadas.
  Future<void> _offerWaitlist() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fechas ocupadas'),
        content: const Text(
            'Esas fechas ya están reservadas. ¿Quieres apuntarte a la lista de '
            'espera? Si quien la tiene la cancela, la reserva pasará a ser tuya '
            'automáticamente y te avisaremos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No, gracias')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apuntarme')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await DataService.joinWaitlist(
        propertyId: _propertyId!,
        start: _start,
        end: _end,
        guestCount: _guests,
        familyGroupId: _familyGroupId,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Te has apuntado a la lista de espera.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = friendlyError(e,
          fallback: 'No se pudo apuntar a la lista de espera.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE d MMM yyyy', 'es');
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva reserva')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.property != null)
            InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Domicilio', border: OutlineInputBorder()),
              child: Text(widget.property!.name),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _propertyId,
              decoration: const InputDecoration(
                  labelText: 'Casa', border: OutlineInputBorder()),
              items: _properties
                  .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                  .toList(),
              onChanged: (v) => setState(() => _propertyId = v),
            ),
          const SizedBox(height: 16),
          ListTile(
            shape: const RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey),
                borderRadius: BorderRadius.all(Radius.circular(4))),
            title: const Text('Entrada'),
            subtitle: Text(df.format(_start)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () => _pickDate(start: true),
          ),
          const SizedBox(height: 8),
          ListTile(
            shape: const RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey),
                borderRadius: BorderRadius.all(Radius.circular(4))),
            title: const Text('Salida'),
            subtitle: Text(df.format(_end)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () => _pickDate(start: false),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Personas'),
              const Spacer(),
              IconButton(
                onPressed: _guests > 1 ? () => setState(() => _guests--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_guests', style: const TextStyle(fontSize: 18)),
              IconButton(
                onPressed: () => setState(() => _guests++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Comentarios', border: OutlineInputBorder()),
          ),
          if (_isPrincipal) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Bloqueo de mantenimiento'),
              value: _maintenance,
              onChanged: (v) => setState(() => _maintenance = v),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Crear reserva'),
            ),
          ),
        ],
      ),
    );
  }
}
