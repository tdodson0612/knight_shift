// lib/shared/models/payroll_model.dart

/// Run-level metadata for a payroll_runs row.
class PayrollRun {
  final String id;
  final String companyId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String status;
  final String? createdBy;

  PayrollRun({
    required this.id,
    required this.companyId,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    this.createdBy,
  });

  factory PayrollRun.fromMap(Map<String, dynamic> map) {
    return PayrollRun(
      id: map['id']?.toString() ?? '',
      companyId: map['company_id']?.toString() ?? '',
      // Real columns are start_date / end_date, not
      // period_start / period_end — confirmed against live schema.
      periodStart: DateTime.parse(map['start_date']),
      periodEnd: DateTime.parse(map['end_date']),
      status: map['status']?.toString() ?? 'draft',
      createdBy: map['created_by']?.toString(),
    );
  }
}

/// Per-employee entry within a payroll run (a payroll_entries row).
///
/// regularHours/overtimeHours/overtimePay are null for any entry
/// created before the overtime feature existed, or for a company
/// that never had overtime thresholds enabled — treat null as "no
/// breakdown available," not as zero.
class PayrollSummary {
  final String userId;
  final double hours;
  final double hourlyRate;
  final double totalPay;
  final double? regularHours;
  final double? overtimeHours;
  final double? overtimePay;

  PayrollSummary({
    required this.userId,
    required this.hours,
    required this.hourlyRate,
    required this.totalPay,
    this.regularHours,
    this.overtimeHours,
    this.overtimePay,
  });

  bool get hasOvertimeBreakdown => overtimeHours != null;

  factory PayrollSummary.fromMap(Map<String, dynamic> map) {
    return PayrollSummary(
      userId: map['user_id']?.toString() ?? '',
      hours: (map['total_hours'] ?? 0).toDouble(),
      hourlyRate: (map['hourly_rate'] ?? 0).toDouble(),
      totalPay: (map['total_pay'] ?? 0).toDouble(),
      regularHours: map['regular_hours'] == null
          ? null
          : (map['regular_hours'] as num).toDouble(),
      overtimeHours: map['overtime_hours'] == null
          ? null
          : (map['overtime_hours'] as num).toDouble(),
      overtimePay: map['overtime_pay'] == null
          ? null
          : (map['overtime_pay'] as num).toDouble(),
    );
  }
}