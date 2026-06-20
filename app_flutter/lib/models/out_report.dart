class OutReport {
  final String id;
  final String? reservationId;
  final String? propertyName;
  final String generalStatus;
  final String? notes;
  final List<Map<String, dynamic>> mediaUrls; // [{type, key}]
  final int? rating;
  final DateTime? checkOut;
  final DateTime createdAt;

  OutReport({
    required this.id,
    required this.generalStatus,
    required this.createdAt,
    this.reservationId,
    this.propertyName,
    this.notes,
    this.mediaUrls = const [],
    this.rating,
    this.checkOut,
  });

  factory OutReport.fromMap(Map<String, dynamic> m) => OutReport(
        id: m['id'] as String,
        reservationId: m['reservation_id'] as String?,
        propertyName: m['properties'] is Map ? m['properties']['name'] as String? : null,
        generalStatus: (m['general_status'] as String?) ?? '',
        notes: m['notes'] as String?,
        mediaUrls: ((m['media_urls'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        rating: m['rating'] as int?,
        checkOut: m['check_out'] != null ? DateTime.parse(m['check_out'] as String) : null,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
