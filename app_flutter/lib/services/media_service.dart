// Subida y descarga de fotos/vídeos con URLs firmadas (media-sign).
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../main.dart';

class MediaService {
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
      'size': bytes.length,
    });
    final data = (res.data as Map);
    final url = data['url'] as String;
    final key = data['key'] as String;

    final signedHeaders = <String, String>{};
    (data['headers'] as Map?)?.forEach((k, v) =>
        signedHeaders[k.toString()] = v.toString());
    signedHeaders.putIfAbsent('Content-Type', () => contentType);

    final put = await http.put(
      Uri.parse(url),
      headers: signedHeaders,
      body: bytes,
    );
    if (put.statusCode >= 300) {
      throw Exception('Error subiendo media (${put.statusCode})');
    }
    return key;
  }

  static Future<String> signedUrl(String reservationId, String key) async {
    final res = await supabase.functions.invoke('media-sign', body: {
      'op': 'get',
      'reservationId': reservationId,
      'key': key,
    });
    return (res.data as Map)['url'] as String;
  }
}
