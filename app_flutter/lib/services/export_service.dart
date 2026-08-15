import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExportService {
  static Future<List<Map<String, dynamic>>> _reservas() async {
    final rows = await Supabase.instance.client
        .from('reservations')
        .select('start_date, end_date, guest_count, is_maintenance, is_fixed, '
            'price_per_night, total_price, properties(name), '
            'family_groups(name), profiles!created_by_id(name)')
        .order('start_date');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static List<List<String>> _filas(List<Map<String, dynamic>> rows) {
    final df = DateFormat('dd/MM/yyyy');
    String nombre(dynamic m) => m is Map ? (m['name'] as String? ?? '') : '';
    return rows.map((r) {
      final start = DateTime.parse(r['start_date'] as String);
      final end = DateTime.parse(r['end_date'] as String);
      final noches = end.difference(start).inDays;
      final maint = (r['is_maintenance'] as bool?) ?? false;
      return [
        nombre(r['properties']),
        nombre(r['family_groups']),
        nombre(r['profiles']),
        df.format(start),
        df.format(end),
        '$noches',
        '${r['guest_count'] ?? ''}',
        '${r['price_per_night'] ?? ''}',
        '${r['total_price'] ?? ''}',
        maint
            ? 'Mantenimiento'
            : ((r['is_fixed'] as bool?) ?? false ? 'Fija' : 'Normal'),
      ];
    }).toList();
  }

  static const _cabecera = [
    'Casa', 'Familia', 'Persona', 'Entrada', 'Salida', 'Noches',
    'Personas', 'Precio/noche', 'Total', 'Tipo',
  ];

  static Future<void> exportarCsv() async {
    final filas = _filas(await _reservas());
    String esc(String v) =>
        v.contains(RegExp('[;"\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
    final csv = [
      _cabecera.join(';'),
      ...filas.map((f) => f.map(esc).join(';')),
    ].join('\n');
    await _compartir('reservas.csv', utf8Bom + csv, texto: true);
  }

  static Future<void> exportarPdf() async {
    final filas = _filas(await _reservas());
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (_) => [
        pw.Text('Portal Familia — Reservas',
            style: const pw.TextStyle(fontSize: 18)),
        pw.SizedBox(height: 4),
        pw.Text('Generado el '
            '${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: _cabecera,
          data: filas,
          headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        ),
      ],
    ));
    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/reservas.pdf');
    await f.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path)],
      subject: 'Portal Familia — reservas',
    ));
  }

  static const utf8Bom = '﻿';

  static Future<void> _compartir(String nombre, String contenido,
      {required bool texto}) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$nombre');
    await f.writeAsString(contenido);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path)],
      subject: 'Portal Familia — reservas',
    ));
  }
}
