class ReservationSwap {
  final String id;
  final String proposerId;
  final String targetId;
  final String? proposerName;
  final String? targetName;
  final String offerPropertyId;
  final DateTime offerStart;
  final DateTime offerEnd;
  final String? offerPropertyName;
  final String wantPropertyId;
  final DateTime wantStart;
  final DateTime wantEnd;
  final String? wantPropertyName;
  final String status;
  final DateTime createdAt;

  ReservationSwap({
    required this.id,
    required this.proposerId,
    required this.targetId,
    required this.offerPropertyId,
    required this.offerStart,
    required this.offerEnd,
    required this.wantPropertyId,
    required this.wantStart,
    required this.wantEnd,
    required this.status,
    required this.createdAt,
    this.proposerName,
    this.targetName,
    this.offerPropertyName,
    this.wantPropertyName,
  });

  static String? _name(dynamic v) =>
      v is Map ? v['name'] as String? : null;

  factory ReservationSwap.fromMap(Map<String, dynamic> m) => ReservationSwap(
        id: m['id'] as String,
        proposerId: m['proposer_id'] as String,
        targetId: m['target_id'] as String,
        proposerName: _name(m['proposer']),
        targetName: _name(m['target']),
        offerPropertyId: m['offer_property_id'] as String,
        offerStart: DateTime.parse(m['offer_start'] as String),
        offerEnd: DateTime.parse(m['offer_end'] as String),
        offerPropertyName: _name(m['offer_property']),
        wantPropertyId: m['want_property_id'] as String,
        wantStart: DateTime.parse(m['want_start'] as String),
        wantEnd: DateTime.parse(m['want_end'] as String),
        wantPropertyName: _name(m['want_property']),
        status: m['status'] as String? ?? 'pending',
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
