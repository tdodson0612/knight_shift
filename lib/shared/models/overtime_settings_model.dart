// lib/shared/models/overtime_settings_model.dart

/// Per-company overtime configuration, set by that company's own
/// manager/admin in Settings — never a hardcoded business rule.
/// Read from / written to columns on `companies`.
class OvertimeSettings {
  final bool dailyEnabled;
  final double dailyThresholdHours;
  final bool weeklyEnabled;
  final double weeklyThresholdHours;

  /// 'hours_only'    -> track/report the overtime split, but pay
  ///                    everyone at straight rate (no multiplier).
  /// 'calculate_pay'  -> apply [multiplier] to overtime hours when
  ///                    generating payroll entries.
  final String payMode;
  final double multiplier;

  const OvertimeSettings({
    required this.dailyEnabled,
    required this.dailyThresholdHours,
    required this.weeklyEnabled,
    required this.weeklyThresholdHours,
    required this.payMode,
    required this.multiplier,
  });

  static const defaults = OvertimeSettings(
    dailyEnabled: false,
    dailyThresholdHours: 8,
    weeklyEnabled: false,
    weeklyThresholdHours: 40,
    payMode: 'hours_only',
    multiplier: 1.5,
  );

  bool get calculatesPay => payMode == 'calculate_pay';
  bool get anyThresholdEnabled => dailyEnabled || weeklyEnabled;

  factory OvertimeSettings.fromMap(Map<String, dynamic> map) {
    return OvertimeSettings(
      dailyEnabled: map['overtime_daily_enabled'] as bool? ?? false,
      dailyThresholdHours:
          (map['overtime_daily_threshold_hours'] ?? 8).toDouble(),
      weeklyEnabled: map['overtime_weekly_enabled'] as bool? ?? false,
      weeklyThresholdHours:
          (map['overtime_weekly_threshold_hours'] ?? 40).toDouble(),
      payMode: map['overtime_pay_mode']?.toString() ?? 'hours_only',
      multiplier: (map['overtime_multiplier'] ?? 1.5).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'overtime_daily_enabled': dailyEnabled,
      'overtime_daily_threshold_hours': dailyThresholdHours,
      'overtime_weekly_enabled': weeklyEnabled,
      'overtime_weekly_threshold_hours': weeklyThresholdHours,
      'overtime_pay_mode': payMode,
      'overtime_multiplier': multiplier,
    };
  }

  OvertimeSettings copyWith({
    bool? dailyEnabled,
    double? dailyThresholdHours,
    bool? weeklyEnabled,
    double? weeklyThresholdHours,
    String? payMode,
    double? multiplier,
  }) {
    return OvertimeSettings(
      dailyEnabled: dailyEnabled ?? this.dailyEnabled,
      dailyThresholdHours: dailyThresholdHours ?? this.dailyThresholdHours,
      weeklyEnabled: weeklyEnabled ?? this.weeklyEnabled,
      weeklyThresholdHours:
          weeklyThresholdHours ?? this.weeklyThresholdHours,
      payMode: payMode ?? this.payMode,
      multiplier: multiplier ?? this.multiplier,
    );
  }
}

/// Result of splitting one user's hours into regular vs overtime for
/// a payroll period.
class OvertimeBreakdown {
  final double totalHours;
  final double regularHours;
  final double overtimeHours;
  final double regularPay;
  final double overtimePay;

  const OvertimeBreakdown({
    required this.totalHours,
    required this.regularHours,
    required this.overtimeHours,
    required this.regularPay,
    required this.overtimePay,
  });

  double get totalPay => regularPay + overtimePay;
}