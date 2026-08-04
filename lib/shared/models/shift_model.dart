// lib/shared/models/shift_model.dart

class ShiftModel {
  final String id;
  final String companyId;
  final String? userId;
  final DateTime startTime;
  final DateTime endTime;
  final String? createdBy;
  final DateTime? createdAt;

  final String status;
  final DateTime? statusChangedAt;
  final String? statusChangedBy;
  final String? managerNote;

  final String? swapTargetUserId;

  // Permanent record of how this shift was created:
  //   employee_request | manager_scheduled | open_posted
  // Set once at insert, never overwritten — this is what makes
  // reporting on request/fill rates reliable rather than guessed
  // from final status (which is ambiguous). Null for rows created
  // before this field existed.
  final String? origin;

  ShiftModel({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.startTime,
    required this.endTime,
    this.createdBy,
    this.createdAt,
    this.status = 'approved',
    this.statusChangedAt,
    this.statusChangedBy,
    this.managerNote,
    this.swapTargetUserId,
    this.origin,
  });

  factory ShiftModel.fromMap(Map<String, dynamic> map) {
    return ShiftModel(
      id: map['id']?.toString() ?? '',
      companyId: map['company_id']?.toString() ?? '',
      userId: map['user_id']?.toString(),
      startTime: DateTime.parse(map['start_time']),
      endTime: DateTime.parse(map['end_time']),
      createdBy: map['created_by']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      status: map['status']?.toString() ?? 'approved',
      statusChangedAt: map['status_changed_at'] != null
          ? DateTime.tryParse(map['status_changed_at'].toString())
          : null,
      statusChangedBy: map['status_changed_by']?.toString(),
      managerNote: map['manager_note']?.toString(),
      swapTargetUserId: map['swap_target_user_id']?.toString(),
      origin: map['origin']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'user_id': userId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'created_by': createdBy,
      'status': status,
      'status_changed_at': statusChangedAt?.toIso8601String(),
      'status_changed_by': statusChangedBy,
      'manager_note': managerNote,
      'swap_target_user_id': swapTargetUserId,
      'origin': origin,
    };
  }

  Duration get duration => endTime.difference(startTime);

  bool overlaps(DateTime start, DateTime end) {
    return start.isBefore(endTime) && end.isAfter(startTime);
  }

  bool get isOpen => status == 'open';
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';
  bool get isSwapRequested => status == 'swap_requested';
  bool get isSwapPending => status == 'swap_pending';

  bool get reservesTimeSlot =>
      isApproved || isPending || isSwapRequested || isSwapPending;

  String get computedTimingState {
    final now = DateTime.now();
    if (now.isBefore(startTime)) return "Scheduled";
    if (now.isAfter(endTime)) return "Completed";
    return "In Progress";
  }

  String get displayStatus {
    switch (status) {
      case 'open':
        return "Open Shift";
      case 'pending':
        return "Pending";
      case 'rejected':
        return "Rejected";
      case 'cancelled':
        return "Cancelled";
      case 'swap_requested':
        return "Swap Proposed";
      case 'swap_pending':
        return "Swap — Awaiting Approval";
      case 'approved':
        return computedTimingState;
      default:
        return status;
    }
  }
}