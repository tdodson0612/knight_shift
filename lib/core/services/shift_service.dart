// lib/core/services/shift_service.dart

import 'supabase_service.dart';
import '../../shared/models/shift_model.dart';
import 'validation_service.dart';
import 'availability_service.dart';
import 'time_off_service.dart';
import 'notification_service.dart';
import 'subscription_service.dart';

class ShiftService {
  static final _db = SupabaseService.client;

  // ----------------------------
  // GET SHIFTS — never gated, always readable
  // ----------------------------
  static Future<List<ShiftModel>> getCompanyShifts(
    String companyId,
  ) async {
    final error = ValidationService.validateCompanyId(companyId);
    if (error != null) throw Exception(error);

    final res = await _db
        .from('shifts')
        .select()
        .eq('company_id', companyId);

    final data = List<Map<String, dynamic>>.from(res);

    return data.map((e) => ShiftModel.fromMap(e)).toList();
  }

  // ----------------------------
  // CONFLICT CHECK (CLIENT)
  // ----------------------------
  static Future<bool> hasConflict({
    required String companyId,
    required String userId,
    required DateTime start,
    required DateTime end,
    String? ignoreShiftId,
  }) async {
    final res = await _db
        .from('shifts')
        .select()
        .eq('company_id', companyId)
        .eq('user_id', userId);

    final shifts = List<Map<String, dynamic>>.from(res)
        .map((e) => ShiftModel.fromMap(e))
        .toList();

    return shifts.any((shift) {
      if (ignoreShiftId != null && shift.id == ignoreShiftId) return false;
      if (!shift.reservesTimeSlot) return false;
      return shift.overlaps(start, end);
    });
  }

  // ----------------------------
  // SOFT ADVISORY CHECK
  // ----------------------------
  static Future<String?> _checkAdvisories({
    required String companyId,
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final warnings = <String>[];

    final withinAvailability = await AvailabilityService.isWithinAvailability(
      companyId: companyId,
      userId: userId,
      dateTime: start,
    );
    if (!withinAvailability) {
      warnings.add("Outside employee's stated availability");
    }

    final timeOff = await TimeOffService.getUserTimeOff(companyId, userId);
    final approvedOverlap = timeOff.any(
      (t) => t.isApproved && t.overlapsRange(start, end),
    );
    if (approvedOverlap) {
      warnings.add("Employee has approved time off during this period");
    }

    if (warnings.isEmpty) return null;
    return warnings.join(" • ");
  }

  // ----------------------------
  // VALIDATE SHIFT
  // ----------------------------
  static Future<ShiftAnalysis> analyzeShift({
    required String companyId,
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final timeError =
        ValidationService.validateShiftTime(start, end);

    if (timeError != null) {
      return ShiftAnalysis(false, timeError, null);
    }

    final conflict = await hasConflict(
      companyId: companyId,
      userId: userId,
      start: start,
      end: end,
    );

    if (conflict) {
      return ShiftAnalysis(false, "Shift conflict detected", null);
    }

    final warning = await _checkAdvisories(
      companyId: companyId,
      userId: userId,
      start: start,
      end: end,
    );

    return ShiftAnalysis(true, null, warning);
  }

  // ----------------------------
  // CREATE SHIFT — gated. [origin] is a permanent record of how
  // this shift was created (employee_request | manager_scheduled |
  // open_posted) — set once, never overwritten.
  // ----------------------------
  static Future<void> createShift({
    required String companyId,
    required String? userId,
    required DateTime start,
    required DateTime end,
    required String createdBy,
    required String status,
    required String origin,
  }) async {
    if (await SubscriptionService.isLocked(companyId)) {
      throw Exception(
        "Schedule editing is disabled — your trial has ended. Upgrade to continue.",
      );
    }

    final error =
        ValidationService.validateShiftTime(start, end);
    if (error != null) throw Exception(error);

    if (userId != null) {
      final conflict = await hasConflict(
        companyId: companyId,
        userId: userId,
        start: start,
        end: end,
      );

      if (conflict) {
        throw Exception("Shift conflict detected");
      }
    }

    final now = DateTime.now().toIso8601String();

    final inserted = await _db.from('shifts').insert({
      'company_id': companyId,
      'user_id': userId,
      'start_time': start.toIso8601String(),
      'end_time': end.toIso8601String(),
      'created_by': createdBy,
      'status': status,
      'status_changed_at': now,
      'status_changed_by': createdBy,
      'origin': origin,
    }).select().single();

    final newShiftId = inserted['id']?.toString();

    if (status == 'pending' && userId != null) {
      await NotificationService.notifyManagers(
        companyId: companyId,
        type: 'shift_request',
        title: 'New shift request',
        body: 'A shift request was submitted for ${_formatDateTime(start)}.',
        excludeUserId: createdBy,
        relatedId: newShiftId,
        relatedType: 'shift',
      );
    }
  }

  // ----------------------------
  // OPEN SHIFTS
  // ----------------------------

  static Future<void> postOpenShift({
    required String companyId,
    required DateTime start,
    required DateTime end,
    required String createdBy,
  }) async {
    await createShift(
      companyId: companyId,
      userId: null,
      start: start,
      end: end,
      createdBy: createdBy,
      status: 'open',
      origin: 'open_posted',
    );
  }

  static Future<void> claimOpenShift({
    required String shiftId,
    required String claimingUserId,
  }) async {
    final shift = await _fetchShift(shiftId);
    if (shift == null) throw Exception("Shift not found");

    if (!shift.isOpen || shift.userId != null) {
      throw Exception("This shift is no longer open");
    }

    if (await SubscriptionService.isLocked(shift.companyId)) {
      throw Exception(
        "Schedule editing is disabled — your trial has ended. Upgrade to continue.",
      );
    }

    final conflict = await hasConflict(
      companyId: shift.companyId,
      userId: claimingUserId,
      start: shift.startTime,
      end: shift.endTime,
    );

    if (conflict) {
      throw Exception("This conflicts with one of your existing shifts");
    }

    await _db.from('shifts').update({
      'user_id': claimingUserId,
      'status': 'pending',
      'status_changed_at': DateTime.now().toIso8601String(),
      'status_changed_by': claimingUserId,
    }).eq('id', shiftId);

    await NotificationService.notifyManagers(
      companyId: shift.companyId,
      type: 'shift_claimed',
      title: 'Open shift claimed',
      body: 'An open shift on ${_formatDateTime(shift.startTime)} was '
          'claimed and needs approval.',
      excludeUserId: claimingUserId,
      relatedId: shiftId,
      relatedType: 'shift',
    );
  }

  // ----------------------------
  // APPROVE / REJECT
  // ----------------------------
  static Future<void> approveShift({
    required String shiftId,
    required String managerId,
    String? note,
  }) async {
    final shift = await _fetchShift(shiftId);
    if (shift == null || shift.userId == null) return;

    if (await SubscriptionService.isLocked(shift.companyId)) {
      throw Exception(
        "Schedule editing is disabled — your trial has ended. Upgrade to continue.",
      );
    }

    await _db.from('shifts').update({
      'status': 'approved',
      'status_changed_at': DateTime.now().toIso8601String(),
      'status_changed_by': managerId,
      'manager_note': note,
    }).eq('id', shiftId);

    await NotificationService.notifyUser(
      companyId: shift.companyId,
      userId: shift.userId!,
      type: 'shift_approved',
      title: 'Shift request approved',
      body:
          'Your shift request for ${_formatDateTime(shift.startTime)} was approved.'
          '${note != null && note.isNotEmpty ? ' Note: $note' : ''}',
      relatedId: shiftId,
      relatedType: 'shift',
    );
  }

  static Future<void> rejectShift({
    required String shiftId,
    required String managerId,
    String? note,
  }) async {
    final shift = await _fetchShift(shiftId);
    if (shift == null || shift.userId == null) return;

    if (await SubscriptionService.isLocked(shift.companyId)) {
      throw Exception(
        "Schedule editing is disabled — your trial has ended. Upgrade to continue.",
      );
    }

    await _db.from('shifts').update({
      'status': 'rejected',
      'status_changed_at': DateTime.now().toIso8601String(),
      'status_changed_by': managerId,
      'manager_note': note,
    }).eq('id', shiftId);

    await NotificationService.notifyUser(
      companyId: shift.companyId,
      userId: shift.userId!,
      type: 'shift_rejected',
      title: 'Shift request rejected',
      body:
          'Your shift request for ${_formatDateTime(shift.startTime)} was rejected.'
          '${note != null && note.isNotEmpty ? ' Note: $note' : ''}',
      relatedId: shiftId,
      relatedType: 'shift',
    );
  }

  // ----------------------------
  // SHIFT SWAP REQUESTS
  // ----------------------------

  static Future<void> requestSwap({
    required String shiftId,
    required String requestingUserId,
    required String targetUserId,
  }) async {
    final shift = await _fetchShift(shiftId);
    if (shift == null) throw Exception("Shift not found");

    if (await SubscriptionService.isLocked(shift.companyId)) {
      throw Exception(
        "Schedule editing is disabled — your trial has ended. Upgrade to continue.",
      );
    }

    if (shift.userId != requestingUserId) {
      throw Exception("You can only propose a swap for your own shift");
    }
    if (!shift.isApproved) {
      throw Exception("Only approved shifts can be swapped");
    }
    if (shift.startTime.isBefore(DateTime.now())) {
      throw Exception("Cannot swap a shift that has already started");
    }
    if (targetUserId == requestingUserId) {
      throw Exception("Choose a different coworker to swap with");
    }

    await _db.from('shifts').update({
      'status': 'swap_requested',
      'swap_target_user_id': targetUserId,
      'status_changed_at': DateTime.now().toIso8601String(),
      'status_changed_by': requestingUserId,
    }).eq('id', shiftId);

    await NotificationService.notifyUser(
      companyId: shift.companyId,
      userId: targetUserId,
      type: 'swap_requested',
      title: 'Shift swap proposed',
      body: 'A coworker proposed swapping their shift on '
          '${_formatDateTime(shift.startTime)} with you.',
      relatedId: shiftId,
      relatedType: 'shift',
    );
  }

  static Future<void> respondToSwap({
    required String shiftId,
    required String targetUserId,
    required bool accept,
  }) async {
    final shift = await _fetchShift(shiftId);
    if (shift == null) throw Exception("Shift not found");

    if (shift.swapTargetUserId != targetUserId || !shift.isSwapRequested) {
      throw Exception("This swap request is no longer available");
    }

    if (await SubscriptionService.isLocked(shift.companyId)) {
      throw Exception(
        "Schedule editing is disabled — your trial has ended. Upgrade to continue.",
      );
    }

    final newStatus = accept ? 'swap_pending' : 'approved';

    await _db.from('shifts').update({
      'status': newStatus,
      'swap_target_user_id': accept ? targetUserId : null,
      'status_changed_at': DateTime.now().toIso8601String(),
      'status_changed_by': targetUserId,
    }).eq('id', shiftId);

    if (accept) {
      await NotificationService.notifyManagers(
        companyId: shift.companyId,
        type: 'swap_pending',
        title: 'Shift swap needs approval',
        body: 'A shift swap for ${_formatDateTime(shift.startTime)} was '
            'accepted by both employees and needs final approval.',
        relatedId: shiftId,
        relatedType: 'shift',
      );
    } else {
      await NotificationService.notifyUser(
        companyId: shift.companyId,
        userId: shift.userId!,
        type: 'swap_declined',
        title: 'Shift swap declined',
        body: 'Your swap proposal for ${_formatDateTime(shift.startTime)} '
            'was declined.',
        relatedId: shiftId,
        relatedType: 'shift',
      );
    }
  }

  static Future<void> approveSwap({
    required String shiftId,
    required String managerId,
  }) async {
    final shift = await _fetchShift(shiftId);
    if (shift == null) throw Exception("Shift not found");

    if (!shift.isSwapPending || shift.swapTargetUserId == null) {
      throw Exception("This shift is not awaiting swap approval");
    }

    if (await SubscriptionService.isLocked(shift.companyId)) {
      throw Exception(
        "Schedule editing is disabled — your trial has ended. Upgrade to continue.",
      );
    }

    final newUserId = shift.swapTargetUserId!;
    final originalUserId = shift.userId!;

    await _db.from('shifts').update({
      'user_id': newUserId,
      'status': 'approved',
      'swap_target_user_id': null,
      'status_changed_at': DateTime.now().toIso8601String(),
      'status_changed_by': managerId,
    }).eq('id', shiftId);

    await NotificationService.notifyUser(
      companyId: shift.companyId,
      userId: originalUserId,
      type: 'swap_approved',
      title: 'Shift swap approved',
      body: 'Your swap for ${_formatDateTime(shift.startTime)} was approved.',
      relatedId: shiftId,
      relatedType: 'shift',
    );
    await NotificationService.notifyUser(
      companyId: shift.companyId,
      userId: newUserId,
      type: 'swap_approved',
      title: 'Shift swap approved',
      body: 'You are now scheduled for ${_formatDateTime(shift.startTime)}.',
      relatedId: shiftId,
      relatedType: 'shift',
    );
  }

  static Future<void> rejectSwap({
    required String shiftId,
    required String managerId,
  }) async {
    final shift = await _fetchShift(shiftId);
    if (shift == null) throw Exception("Shift not found");

    if (!shift.isSwapPending) {
      throw Exception("This shift is not awaiting swap approval");
    }

    if (await SubscriptionService.isLocked(shift.companyId)) {
      throw Exception(
        "Schedule editing is disabled — your trial has ended. Upgrade to continue.",
      );
    }

    final targetUserId = shift.swapTargetUserId;

    await _db.from('shifts').update({
      'status': 'approved',
      'swap_target_user_id': null,
      'status_changed_at': DateTime.now().toIso8601String(),
      'status_changed_by': managerId,
    }).eq('id', shiftId);

    await NotificationService.notifyUser(
      companyId: shift.companyId,
      userId: shift.userId!,
      type: 'swap_rejected',
      title: 'Shift swap rejected',
      body:
          'Your swap request for ${_formatDateTime(shift.startTime)} was rejected. You remain scheduled.',
      relatedId: shiftId,
      relatedType: 'shift',
    );

    if (targetUserId != null) {
      await NotificationService.notifyUser(
        companyId: shift.companyId,
        userId: targetUserId,
        type: 'swap_rejected',
        title: 'Shift swap rejected',
        body:
            'The shift swap for ${_formatDateTime(shift.startTime)} was rejected by a manager.',
        relatedId: shiftId,
        relatedType: 'shift',
      );
    }
  }

  static Future<ShiftModel?> _fetchShift(String shiftId) async {
    final res = await _db
        .from('shifts')
        .select()
        .eq('id', shiftId)
        .maybeSingle();

    if (res == null) return null;
    return ShiftModel.fromMap(res);
  }

  static String _formatDateTime(DateTime dt) {
    return "${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }
}

// ----------------------------
// PUBLIC ANALYSIS MODEL
// ----------------------------
class ShiftAnalysis {
  final bool canCreate;
  final String? reason;
  final String? warning;

  ShiftAnalysis(this.canCreate, this.reason, this.warning);
}