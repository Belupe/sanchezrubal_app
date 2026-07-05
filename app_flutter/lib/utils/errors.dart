import 'package:flutter/foundation.dart';

/// [2L-06] Devuelve un mensaje GENÉRICO para el usuario y loguea el detalle
/// real (que puede traer nombres de columnas/constraints/RLS de Postgres).
String friendlyError(Object error,
    {String fallback = 'No se pudo completar la operación. Inténtalo de nuevo.'}) {
  debugPrint('Error backend: $error');
  return fallback;
}
