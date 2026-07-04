class SystemConfig {
  final String? smtpHost;
  final int? smtpPort;
  final String? smtpUser;
  final String? smtpPass;
  final bool smtpSecure;
  final int maxReservationDays;
  final int maxReservationDaysCap;

  SystemConfig({
    this.smtpHost,
    this.smtpPort,
    this.smtpUser,
    this.smtpPass,
    this.smtpSecure = false,
    this.maxReservationDays = 30,
    this.maxReservationDaysCap = 31,
  });

  factory SystemConfig.fromMap(Map<String, dynamic> m) => SystemConfig(
        smtpHost: m['smtp_host'] as String?,
        smtpPort: m['smtp_port'] as int?,
        smtpUser: m['smtp_user'] as String?,
        smtpPass: m['smtp_pass'] as String?,
        smtpSecure: (m['smtp_secure'] as bool?) ?? false,
        maxReservationDays: (m['max_reservation_days'] as int?) ?? 30,
        maxReservationDaysCap: (m['max_reservation_days_cap'] as int?) ?? 31,
      );
}
