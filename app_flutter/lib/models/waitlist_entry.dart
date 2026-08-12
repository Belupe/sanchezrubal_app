class WaitlistEntry {
  final String id;
  final String propertyId;
  final String requestedById;
  final String? familyGroupId;
  final DateTime startDate;
  final DateTime endDate;
  final int guestCount;
  final String? notes;
  final String status;
  final DateTime createdAt;
  final DateTime? offeredUntil;
  final String? requesterName;
  final String? propertyName;

  WaitlistEntry({
    required this.id,
    required this.propertyId,
    required this.requestedById,
    required this.startDate,
    required this.endDate,
    required this.guestCount,
    required this.status,
    required this.createdAt,
    this.familyGroupId,
    this.notes,
    this.offeredUntil,
    this.requesterName,
    this.propertyName,
  });

  factory WaitlistEntry.fromMap(Map<String, dynamic> m) => WaitlistEntry(
        id: m['id'] as String,
        propertyId: m['property_id'] as String,
        requestedById: m['requested_by_id'] as String,
        familyGroupId: m['family_group_id'] as String?,
        startDate: DateTime.parse(m['start_date'] as String),
        endDate: DateTime.parse(m['end_date'] as String),
        guestCount: (m['guest_count'] as int?) ?? 1,
        notes: m['notes'] as String?,
        status: (m['status'] as String?) ?? 'waiting',
        createdAt: DateTime.parse(m['created_at'] as String),
        offeredUntil: m['offered_until'] == null
            ? null
            : DateTime.parse(m['offered_until'] as String),
        requesterName: m['profiles'] is Map ? m['profiles']['name'] as String? : null,
        propertyName: m['properties'] is Map ? m['properties']['name'] as String? : null,
      );
}
