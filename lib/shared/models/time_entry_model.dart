// lib/shared/models/time_entry_model.dart

class TimeEntry {
  final String id;
  final String companyId;
  final String userId;
  final DateTime clockIn;
  final DateTime? clockOut;

  const TimeEntry({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.clockIn,
    this.clockOut,
  });

  bool get isOpen => clockOut == null;

  Duration? get duration => clockOut?.difference(clockIn);

  factory TimeEntry.fromMap(Map<String, dynamic> map) {
    return TimeEntry(
      id: map['id']?.toString() ?? '',
      companyId: map['company_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      clockIn: DateTime.parse(map['clock_in']),
      clockOut: map['clock_out'] == null
          ? null
          : DateTime.tryParse(map['clock_out'].toString()),
    );
  }
}

class TimeEntryAuditEntry {
  final String id;
  final String timeEntryId;
  final String? changedBy;
  final DateTime changedAt;
  final DateTime? oldClockIn;
  final DateTime? newClockIn;
  final DateTime? oldClockOut;
  final DateTime? newClockOut;
  final String changeType; // created | updated | deleted

  const TimeEntryAuditEntry({
    required this.id,
    required this.timeEntryId,
    this.changedBy,
    required this.changedAt,
    this.oldClockIn,
    this.newClockIn,
    this.oldClockOut,
    this.newClockOut,
    required this.changeType,
  });

  factory TimeEntryAuditEntry.fromMap(Map<String, dynamic> map) {
    DateTime? parse(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

    return TimeEntryAuditEntry(
      id: map['id']?.toString() ?? '',
      timeEntryId: map['time_entry_id']?.toString() ?? '',
      changedBy: map['changed_by']?.toString(),
      changedAt: DateTime.tryParse(map['changed_at']?.toString() ?? '') ??
          DateTime.now(),
      oldClockIn: parse(map['old_clock_in']),
      newClockIn: parse(map['new_clock_in']),
      oldClockOut: parse(map['old_clock_out']),
      newClockOut: parse(map['new_clock_out']),
      changeType: map['change_type']?.toString() ?? 'updated',
    );
  }
}