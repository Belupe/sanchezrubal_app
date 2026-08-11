import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/property.dart';
import '../models/reservation.dart';
import '../services/data_service.dart';
import '../utils/errors.dart';
import 'inspection_screen.dart';

Future<void> showReservationDetail(
    BuildContext context, Reservation r, VoidCallback onChanged) async {
  final role = await DataService.currentRole();
  final profile = await DataService.myProfile();
  final uid = DataService.uid;
  final isPrincipal = role == 'MEGA_ADMIN' || role == 'PRINCIPAL_ADMIN';

  final groupRole = profile?['group_role'] as String?;
  final isGroupAdmin = isPrincipal ||
      ((groupRole == 'FAMILY_ADMIN' || groupRole == 'FAMILY_SECOND_ADMIN') &&
          profile?['family_group_id'] == r.familyGroupId);
  final isCreator = r.createdById == uid;

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
        canFix: isGroupAdmin,
        isOwner: isCreator,
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
  final bool canFix;
  final bool isOwner;
  final VoidCallback onChanged;

  const _ReservationDetailSheet({
    required this.r,
    required this.canEditDates,
    required this.canEditDetails,
    required this.canDelete,
    required this.canFix,
    required this.isOwner,
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
  late bool _isFixed = widget.r.isFixed;
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

  Future<void> _toggleFix(bool value) async {
    setState(() => _busy = true);
    try {
      await DataService.setReservationFixed(widget.r.id, value);
      if (mounted) setState(() => _isFixed = value);
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo cambiar.'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _proposeSwap() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _ProposeSwapSheet(reservation: widget.r),
      ),
    );
    if (ok == true && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Propuesta enviada. La otra persona debe aceptarla.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE d MMM yyyy', 'es');
    final eur = NumberFormat.currency(locale: 'es', symbol: '€', decimalDigits: 2);
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
          if (_isFixed) ...[
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: Icon(Icons.push_pin, size: 16),
                label: Text('Reserva fija'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
          if (!r.isMaintenance && (r.totalPrice ?? 0) > 0) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.euro, size: 18),
              const SizedBox(width: 6),
              Text('${eur.format(r.totalPrice)}  ',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('· ${r.nights} ${r.nights == 1 ? 'noche' : 'noches'} × '
                  '${eur.format(r.pricePerNight ?? 0)}',
                  style: TextStyle(color: Theme.of(context).hintColor)),
            ]),
          ],
          const Divider(height: 24),

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

          if (widget.isOwner && !r.isMaintenance) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Proponer intercambio'),
              onPressed: _busy ? null : _proposeSwap,
            ),
          ],

          if (widget.canFix && !r.isMaintenance) ...[
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.push_pin_outlined),
              title: const Text('Reserva fija'),
              subtitle: const Text(
                  'Solo se puede mover por intercambio; el dueño no la cancela.'),
              value: _isFixed,
              onChanged: _busy ? null : _toggleFix,
            ),
          ],

          if (widget.canDelete && !(_isFixed && !widget.canFix)) ...[
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

class _ProposeSwapSheet extends StatefulWidget {
  final Reservation reservation;
  const _ProposeSwapSheet({required this.reservation});

  @override
  State<_ProposeSwapSheet> createState() => _ProposeSwapSheetState();
}

class _ProposeSwapSheetState extends State<_ProposeSwapSheet> {
  late DateTime _offerStart = widget.reservation.startDate;
  late DateTime _offerEnd = widget.reservation.endDate;
  List<Property> _properties = [];
  String? _wantProperty;
  late DateTime _wantStart = DateTime.now();
  late DateTime _wantEnd = DateTime.now().add(const Duration(days: 7));
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final props = await DataService.properties();
    if (!mounted) return;
    setState(() {
      _properties = props;
      _wantProperty = props.isNotEmpty ? props.first.id : null;
      _loading = false;
    });
  }

  Future<void> _pick(DateTime initial, DateTime first, DateTime last,
      ValueChanged<DateTime> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) setState(() => onPicked(picked));
  }

  Future<void> _submit() async {
    if (_wantProperty == null) {
      setState(() => _error = 'Elige la casa que quieres.');
      return;
    }
    if (!_offerEnd.isAfter(_offerStart) || !_wantEnd.isAfter(_wantStart)) {
      setState(() => _error = 'Las fechas no son válidas.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DataService.proposeSwap(
        offerProperty: widget.reservation.propertyId,
        offerStart: _offerStart,
        offerEnd: _offerEnd,
        wantProperty: _wantProperty!,
        wantStart: _wantStart,
        wantEnd: _wantEnd,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error =
          friendlyError(e, fallback: 'No se pudo proponer el intercambio.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE d MMM yyyy', 'es');
    final r = widget.reservation;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Proponer intercambio',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Text('Ofreces (de tu reserva en ${r.propertyName ?? 'tu casa'})',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(_offerStart, r.startDate, r.endDate,
                          (d) => _offerStart = d),
                      child: Text(df.format(_offerStart)),
                    ),
                  ),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward, size: 16)),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(_offerEnd, r.startDate, r.endDate,
                          (d) => _offerEnd = d),
                      child: Text(df.format(_offerEnd)),
                    ),
                  ),
                ]),
                const Divider(height: 28),
                Text('Quieres (fechas acordadas con la otra persona)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _wantProperty,
                  decoration: const InputDecoration(
                      labelText: 'Casa', border: OutlineInputBorder()),
                  items: _properties
                      .map((p) =>
                          DropdownMenuItem(value: p.id, child: Text(p.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _wantProperty = v),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(_wantStart, DateTime(2020),
                          DateTime(2035), (d) => _wantStart = d),
                      child: Text(df.format(_wantStart)),
                    ),
                  ),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward, size: 16)),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(_wantEnd, DateTime(2020),
                          DateTime(2035), (d) => _wantEnd = d),
                      child: Text(df.format(_wantEnd)),
                    ),
                  ),
                ]),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Enviar propuesta'),
                  ),
                ),
              ],
            ),
    );
  }
}
