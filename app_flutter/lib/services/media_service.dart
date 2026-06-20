import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../main.dart';

/// Subida/descarga de media de inspecciones contra MinIO mediante URLs
/// prefirmadas que emite la Edge Function `media-sign` (tras verificar
/// permisos con el RLS). Los archivos NO pasan por Supabase.
class MediaService {
  /// Sube bytes y devuelve la CLAVE del objeto (para guardar en
  /// out_reports.media_urls).
  ///
  /// NOTA: para vídeos grandes (> 100 MB) habría que usar subida
  /// multiparte por el límite del plan free de Cloudflare. Aquí va un
  /// PUT simple, suficiente para fotos y vídeos cortos.
  static Future<String> upload({
    required String reservationId,
    required String filename,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final res = await supabase.functions.invoke('media-sign', body: {
      'op': 'put',
      'reservationId': reservationId,
      'filename': filename,
    });
    final data = (res.data as Map);
    final url = data['url'] as String;
    final key = data['key'] as String;

    final put = await http.put(
      Uri.parse(url),
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (put.statusCode >= 300) {
      throw Exception('Error subiendo media (${put.statusCode})');
    }
    return key;
  }

  /// URL temporal para ver un objeto.
  static Future<String> signedUrl(String reservationId, String key) async {
    final res = await supabase.functions.invoke('media-sign', body: {
      'op': 'get',
      'reservationId': reservationId,
      'key': key,
    });
    return (res.data as Map)['url'] as String;
  }
}
