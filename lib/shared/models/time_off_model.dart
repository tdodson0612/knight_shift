// lib/shared/models/time_off_model.dart

class TimeOffRequest {
  final String id;
  final String companyId;
  final String userId;
  final DateTime startDate;
  final DateTime endDate;
  final String? reason;
  final String status;
  final DateTime? statusChangedAt;
  final String? statusChangedBy;
  final String? managerNote;
  final DateTime? createdAt;

  TimeOffRequest({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.startDate,
    required this.endDate,
    this.reason,
    this.status = 'pending',
    this.statusChangedAt,
    this.statusChangedBy,
    this.managerNote,
    this.createdAt,
  });

  factory TimeOffRequest.fromMap(Map<String, dynamic> map) {
    return TimeOffRequest(
      id: map['id']?.toString() ?? '',
      companyId: map['company_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      startDate: DateTime.parse(map['start_date']),
      endDate: DateTime.parse(map['end_date']),
      reason: map['reason']?.toString(),
      status: map['status']?.toString() ?? 'pending',
      statusChangedAt: map['status_changed_at'] != null
          ? DateTime.tryParse(map['status_changed_at'].toString())
          : null,
      statusChangedBy: map['status_changed_by']?.toString(),
      managerNote: map['manager_note']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';

  bool coversDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  bool overlapsRange(DateTime start, DateTime end) {
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day)
        .add(const Duration(days: 1));
    return start.isBefore(e) && end.isAfter(s);
  }
}