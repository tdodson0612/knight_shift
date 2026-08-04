// lib/core/services/team_insights_service.dart

import '../../shared/models/shift_model.dart';
import '../../shared/models/time_off_model.dart';

class RequestStats {
  final int approved;
  final int rejected;
  final int pending;

  RequestStats({
    required this.approved,
    required this.rejected,
    required this.pending,
  });

  int get resolved => approved + rejected;

  double? get approvalRate {
    if (resolved == 0) return null;
    return approved / resolved;
  }
}

class TeamInsightsService {
  // ============================================================
  // SHIFT REQUESTS — relies on ShiftModel.origin == 'employee_request'
  // ============================================================

  static RequestStats shiftRequestStats(List<ShiftModel> shifts) {
    final requests = shifts.where((s) => s.origin == 'employee_request');

    int approved = 0, rejected = 0, pending = 0;
    for (final s in requests) {
      if (s.isApproved) approved++;
      if (s.isRejected) rejected++;
      if (s.isPending) pending++;
    }

    return RequestStats(approved: approved, rejected: rejected, pending: pending);
  }

  static Map<String, RequestStats> shiftRequestStatsByUser(
    List<ShiftModel> shifts,
  ) {
    final requests = shifts.where((s) => s.origin == 'employee_request');
    final byUser = <String, List<ShiftModel>>{};

    for (final s in requests) {
      if (s.userId == null) continue;
      byUser.putIfAbsent(s.userId!, () => []).add(s);
    }

    final Map<String, RequestStats> result = {};
    byUser.forEach((userId, userShifts) {
      int approved = 0, rejected = 0, pending = 0;
      for (final s in userShifts) {
        if (s.isApproved) approved++;
        if (s.isRejected) rejected++;
        if (s.isPending) pending++;
      }
      result[userId] =
          RequestStats(approved: approved, rejected: rejected, pending: pending);
    });

    return result;
  }

  // ============================================================
  // OPEN SHIFT FILL RATE — relies on origin == 'open_posted'.
  // "Filled" = claimed at some point, regardless of later
  // approve/reject outcome.
  // ============================================================

  static ({int filled, int unfilled}) openShiftFillStats(
    List<ShiftModel> shifts,
  ) {
    final openOrigin = shifts.where((s) => s.origin == 'open_posted');

    int filled = 0, unfilled = 0;
    for (final s in openOrigin) {
      if (s.isOpen) {
        unfilled++;
      } else {
        filled++;
      }
    }

    return (filled: filled, unfilled: unfilled);
  }

  static double? openShiftFillRate(List<ShiftModel> shifts) {
    final stats = openShiftFillStats(shifts);
    final total = stats.filled + stats.unfilled;
    if (total == 0) return null;
    return stats.filled / total;
  }

  // ============================================================
  // ACTIVE SWAPS — live snapshot only. History is lost once
  // resolved, so this can never be a trend.
  // ============================================================

  static ({int awaitingResponse, int awaitingApproval}) activeSwaps(
    List<ShiftModel> shifts,
  ) {
    final awaitingResponse = shifts.where((s) => s.isSwapRequested).length;
    final awaitingApproval = shifts.where((s) => s.isSwapPending).length;
    return (awaitingResponse: awaitingResponse, awaitingApproval: awaitingApproval);
  }

  // ============================================================
  // TIME OFF REQUESTS — always employee-initiated, no ambiguity.
  // ============================================================

  static RequestStats timeOffStats(List<TimeOffRequest> requests) {
    int approved = 0, rejected = 0, pending = 0;
    for (final r in requests) {
      if (r.isApproved) approved++;
      if (r.isRejected) rejected++;
      if (r.isPending) pending++;
    }
    return RequestStats(approved: approved, rejected: rejected, pending: pending);
  }

  static Map<String, RequestStats> timeOffStatsByUser(
    List<TimeOffRequest> requests,
  ) {
    final byUser = <String, List<TimeOffRequest>>{};
    for (final r in requests) {
      byUser.putIfAbsent(r.userId, () => []).add(r);
    }

    final Map<String, RequestStats> result = {};
    byUser.forEach((userId, userRequests) {
      int approved = 0, rejected = 0, pending = 0;
      for (final r in userRequests) {
        if (r.isApproved) approved++;
        if (r.isRejected) rejected++;
        if (r.isPending) pending++;
      }
      result[userId] =
          RequestStats(approved: approved, rejected: rejected, pending: pending);
    });

    return result;
  }

  // ============================================================
  // REQUEST VOLUME BY WEEK — based on createdAt (submission time).
  // Rows with no createdAt (pre-migration data) are excluded.
  // ============================================================

  static Map<String, int> shiftRequestVolumeByWeek(List<ShiftModel> shifts) {
    final requests = shifts.where(
      (s) => s.origin == 'employee_request' && s.createdAt != null,
    );

    final Map<String, int> result = {};
    for (final s in requests) {
      final key = _weekKey(s.createdAt!);
      result[key] = (result[key] ?? 0) + 1;
    }
    return result;
  }

  static Map<String, int> timeOffVolumeByWeek(List<TimeOffRequest> requests) {
    final withDates = requests.where((r) => r.createdAt != null);

    final Map<String, int> result = {};
    for (final r in withDates) {
      final key = _weekKey(r.createdAt!);
      result[key] = (result[key] ?? 0) + 1;
    }
    return result;
  }

  static String _weekKey(DateTime date) {
    final daysFromMonday = date.weekday - DateTime.monday;
    final monday = date.subtract(Duration(days: daysFromMonday));
    return "${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}";
  }
}