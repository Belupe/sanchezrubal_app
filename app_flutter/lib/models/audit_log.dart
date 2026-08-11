class AuditLog {
  final String action;
  final String entityType;
  final String? entityId;
  final Map<String, dynamic>? details;
  final String? userName;
  final DateTime createdAt;

  AuditLog({
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.entityId,
    this.details,
    this.userName,
  });

  factory AuditLog.fromMap(Map<String, dynamic> m) {
    final prof = m['profiles'];
    final d = m['details'];
    return AuditLog(
      action: (m['action'] as String?) ?? '',
      entityType: (m['entity_type'] as String?) ?? '',
      entityId: m['entity_id'] as String?,
      details: d is Map ? Map<String, dynamic>.from(d) : null,
      userName: prof is Map ? prof['name'] as String? : null,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }

  String get actionLabel {
    switch (action) {
      case 'CREATE':
        return 'Creó';
      case 'UPDATE':
        return 'Modificó';
      case 'DELETE':
        return 'Eliminó';
      default:
        return action;
    }
  }

  String get entityLabel {
    switch (entityType) {
      case 'reservation':
        return 'una reserva';
      default:
        return entityType;
    }
  }

  Map<String, dynamic>? get snapshot {
    final n = details?['new'];
    final o = details?['old'];
    if (n is Map) return Map<String, dynamic>.from(n);
    if (o is Map) return Map<String, dynamic>.from(o);
    return null;
  }
}
