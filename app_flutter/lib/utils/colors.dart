import 'package:flutter/material.dart';

/// Convierte un hex ('#RRGGBB' o 'RRGGBB') a Color.
Color colorFromHex(String hex) {
  var v = hex.replaceAll('#', '').trim();
  if (v.length == 6) v = 'FF$v';
  final parsed = int.tryParse(v, radix: 16);
  return parsed == null ? Colors.blueGrey : Color(parsed);
}

/// Color distinto y bien separado para cada familia, por índice, usando el
/// ángulo áureo (137.5°). Para N familias razonables no se repiten ni quedan
/// visualmente cercanos.
String familyColorForIndex(int index) {
  final hue = (index * 137.508) % 360.0;
  return _hslToHex(hue, 0.62, 0.50);
}

String _hslToHex(double h, double s, double l) {
  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - (((h / 60) % 2) - 1).abs());
  final m = l - c / 2;
  double r = 0, g = 0, b = 0;
  if (h < 60) {
    r = c;
    g = x;
  } else if (h < 120) {
    r = x;
    g = c;
  } else if (h < 180) {
    g = c;
    b = x;
  } else if (h < 240) {
    g = x;
    b = c;
  } else if (h < 300) {
    r = x;
    b = c;
  } else {
    r = c;
    b = x;
  }
  String hx(double v) =>
      ((v + m) * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${hx(r)}${hx(g)}${hx(b)}';
}
