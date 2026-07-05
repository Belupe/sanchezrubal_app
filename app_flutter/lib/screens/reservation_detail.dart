import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reservation.dart';
import '../services/data_service.dart';
import '../utils/errors.dart';
import 'inspection_screen.dart';

/// Abre el detalle de una reserva con opciones de edición/borrado según el rol.
/// `onChanged` se llama cuando algo cambió (para recargar el calendario).
Future<void> showReservationDetail(
    BuildContext context, Reservation r, VoidCallback onChanged) async {
  final role = await DataService.currentRole();
  final profile = await DataService.myProfile();
  final uid = DataService.uid;
  final isPrincipal = role == 'MEGA_ADMIN' || role == 'PRINCIPAL_ADMIN';
  final isGroupAdmin = isPrincipal ||
      ((role == 'FAMILY_ADMIN' || role == 'FAMILY_SECOND_ADMIN') &&
          profile?['family_group_id'] == r.familyGroupId);
  final isCreator = r.createdById == uid;

  // [A-04] El calendario lee de la vista de ocupación (sin `notes`). Si el
  // usuario puede editar, recupera la fila completa de la tabla para conservar
  // los comentarios; el RLS la devuelve solo al creador/grupo/admin.
  Reservation full = r;
  if (isCreator || isGroupAdmin) {
    final fetched = await DataService.reservationById(r.id);
    if (fetched != null) full = fetched;
  }
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ReservationDetailSheet(
        r: full,
        canEditDates: isGroupAdmin,
        canEditDetails: isCreator || isGroupAdmin,
        canDelete: isCreator || isGroupAdmin,
        onChanged: onChanged,
      ),
    ),
  );
}

class _ReservationDetailSheet extends StatefulWidget {
  final Reservation r;
  final bool canEditDates;
  final bool canEditDetails;
  final bool canDelete;
  final VoidCallback onChanged;

  const _ReservationDetailSheet({
    required this.r,
    required this.canEditDates,
    required this.canEditDetails,
    required this.canDelete,
    required this.onChanged,
  });

  @override
  State<_ReservationDetailSheet> createState() => _ReservationDetailSheetState();
}

class _ReservationDetailSheetState extends State<_ReservationDetailSheet> {
  late int _guests = widget.r.guestCount;
  late final _notes = TextEditingController(text: widget.r.notes ?? '');
  late DateTime _start = widget.r.startDate;
  late DateTime _end = widget.r.endDate;
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    setState(() => _busy = true);
    try {
      await action();
      widget.onChanged();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(okMsg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e,
                fallback: 'No se pudo completar la operación.'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => start ? _start = picked : _end = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE d MMM yyyy', 'es');
    final r = widget.r;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(r.propertyName ?? 'Reserva',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(r.isMaintenance ? 'Bloqueo de mantenimiento' : 'Reserva familiar',
              style: TextStyle(color: Theme.of(context).hintColor)),
          const Divider(height: 24),

          // Fechas
          if (widget.canEditDates) ...[
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.login),
                  label: Text(df.format(_start)),
                  onPressed: _busy ? null : () => _pick(true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: Text(df.format(_end)),
                  onPressed: _busy ? null : () => _pick(false),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => _run(
                        () => DataService.updateReservationDates(r.id,
                            start: _start, end: _end),
                        'Fechas actualizadas.',
                      ),
              child: const Text('Guardar fechas'),
            ),
          ] else
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('${df.format(_start)} → ${df.format(_end)}'),
              subtitle: const Text('Solo un administrador puede cambiar las fechas'),
            ),

          const SizedBox(height: 8),

          // Personas + notas (creador o admin)
          if (widget.canEditDetails) ...[
            Row(children: [
              const Text('Personas'),
              const Spacer(),
              IconButton(
                onPressed:
                    _busy || _guests <= 1 ? null : () => setState(() => _guests--),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_guests', style: const TextStyle(fontSize: 18)),
              IconButton(
                onPressed: _busy ? null : () => setState(() => _guests++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Comentarios', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                        () => DataService.updateReservationDetails(r.id,
                            guestCount: _guests,
                            notes: _notes.text.trim().isEmpty
                                ? null
                                : _notes.text.trim()),
                        'Reserva actualizada.',
                      ),
              child: const Text('Guardar personas y comentarios'),
            ),
          ],

          if (widget.canEditDetails) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Inspección de salida'),
              onPressed: _busy
                  ? null
                  : () {
                      final nav = Navigator.of(context);
                      nav.pop();
                      nav.push(MaterialPageRoute(
                        builder: (_) =>
                            InspectionScreen(reservationId: widget.r.id),
                      ));
                    },
            ),
          ],
          if (widget.canDelete) ...[
            const Divider(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Cancelar y eliminar reserva'),
              onPressed: _busy
                  ? null
                  : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Eliminar reserva'),
                          content: const Text('¿Seguro que quieres eliminarla?'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('No')),
                            FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Sí, eliminar')),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        _run(() => DataService.deleteReservation(r.id),
                            'Reserva eliminada.');
                      }
                    },
            ),
          ],
        ],
      ),
    );
  }
}
