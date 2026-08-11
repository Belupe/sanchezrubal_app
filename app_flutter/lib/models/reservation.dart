class Reservation {
  final String id;
  final String propertyId;
  final String? familyGroupId;
  final String createdById;
  final DateTime startDate;
  final DateTime endDate;
  final int guestCount;
  final String? notes;
  final bool isMaintenance;
  final String? propertyName;
  final String? familyGroupName;
  final String? familyColor;
  final double? pricePerNight;
  final double? totalPrice;
  final bool isFixed;

  Reservation({
    required this.id,
    required this.propertyId,
    required this.createdById,
    required this.startDate,
    required this.endDate,
    required this.guestCount,
    this.familyGroupId,
    this.notes,
    this.isMaintenance = false,
    this.propertyName,
    this.familyGroupName,
    this.familyColor,
    this.pricePerNight,
    this.totalPrice,
    this.isFixed = false,
  });

  int get nights => endDate.difference(startDate).inDays;

  factory Reservation.fromMap(Map<String, dynamic> m) => Reservation(
        id: m['id'] as String,
        propertyId: m['property_id'] as String,
        familyGroupId: m['family_group_id'] as String?,
        createdById: m['created_by_id'] as String,
        startDate: DateTime.parse(m['start_date'] as String),
        endDate: DateTime.parse(m['end_date'] as String),
        guestCount: (m['guest_count'] as int?) ?? 1,
        notes: m['notes'] as String?,
        isMaintenance: (m['is_maintenance'] as bool?) ?? false,
        propertyName: m['properties'] is Map ? m['properties']['name'] as String? : null,
        familyGroupName: m['family_groups'] is Map ? m['family_groups']['name'] as String? : null,
        familyColor: m['family_groups'] is Map ? m['family_groups']['color'] as String? : null,
        pricePerNight: (m['price_per_night'] as num?)?.toDouble(),
        totalPrice: (m['total_price'] as num?)?.toDouble(),
        isFixed: (m['is_fixed'] as bool?) ?? false,
      );
}
