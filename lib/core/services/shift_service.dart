// lib/core/services/shift_service.dart

import 'supabase_service.dart';
import '../../shared/models/shift_model.dart';
import 'validation_service.dart';
import 'availability_service.dart';
import 'time_off_service.dart';
import 'notification_service.dart';
import 'subscription_service.dart';
import 'employee_service.dart';

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
    String? requiredSkillId,
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
      if (requiredSkillId != null) 'required_skill_id': requiredSkillId,
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

    // Seniority-first claiming (Feature 6): when the company has
    // `open_shift_priority` = 'seniority_first', only the most senior
    // eligible employee (earliest hire_date) may claim. Employees with
    // no hire_date set rank BELOW everyone who has one — that's the
    // correct fail-safe: a missing hire date is "unverified seniority",
    // not "hired at the beginning of time". Ties (same hire date, or
    // multiple unset) fall back to first-come.
    final priority = await _getOpenShiftPriority(shift.companyId);
    if (priority == 'seniority_first') {
      final employees =
          await EmployeeService.getCompanyEmployees(shift.companyId);

      // Candidate = anyone with a hire_date, sorted ascending.
      final withHireDates = employees
          .where((e) => e.hireDate != null)
          .toList()
        ..sort((a, b) => a.hireDate!.compareTo(b.hireDate!));

      final mostSenior = withHireDates.isNotEmpty ? withHireDates.first : null;

      if (mostSenior != null && mostSenior.userId != claimingUserId) {
        // Does the caller have a hire date too? Only ask this if
        // they're the earliest — otherwise they're not the most senior.
        final caller = employees.where((e) => e.userId == claimingUserId);
        if (caller.isEmpty ||
            caller.first.hireDate == null ||
            caller.first.hireDate!.isAfter(mostSenior.hireDate!)) {
          throw Exception(
            "This shift is seniority-protected — only the most senior "
            "employee can claim it",
          );
        }
      }
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

  // ----------------------------
  // RECURRING SHIFT PATTERNS (Feature 4)
  // ----------------------------

  /// Generates individual `shifts` rows for a recurring pattern —
  /// "this employee works every Mon/Wed/Fri 9-5 for N weeks" — by
  /// looping [createShift] per occurrence instead of creating a
  /// parallel "recurring shift definition" table. Shifts stay the
  /// single source of truth; the rest of the app doesn't need to
  /// know a shift was generated from a pattern.
  ///
  /// Each occurrence goes through [createShift], so subscription
  /// gating, time validation, and per-occurrence conflict checking
  /// all apply exactly as they do for a shift created one at a time —
  /// a conflict on one day skips just that day, never the whole run.
  ///
  /// [daysOfWeek] uses Dart's DateTime.weekday convention (1=Mon ..
  /// 7=Sun). Only weekdays present in the list are generated within
  /// [startDate]..[endDate] (inclusive).
  ///
  /// All generated shifts are `manager_scheduled` / `approved` — a
  /// recurring pattern is a manager decision, not a batch of
  /// employee requests.
  ///
  /// Returns {created, skipped} — how many shifts were successfully
  /// created vs skipped (conflict or validation failure).
  static Future<({int created, int skipped})> createRecurringShifts({
    required String companyId,
    required String? userId,
    required String createdBy,
    required Set<int> daysOfWeek,
    required TimeOfDaySpec startTime,
    required TimeOfDaySpec endTime,
    required DateTime startDate,
    required DateTime endDate,
    String? requiredSkillId,
  }) async {
    if (await SubscriptionService.isLocked(companyId)) {
      throw Exception(
        "Schedule editing is disabled — your trial has ended. Upgrade to continue.",
      );
    }

    if (daysOfWeek.isEmpty) {
      throw Exception("Pick at least one day of the week");
    }
    if (endDate.isBefore(startDate)) {
      throw Exception("End date must be after start date");
    }

    int created = 0;
    int skipped = 0;

    for (final day in datesForRecurrence(startDate, endDate, daysOfWeek)) {
      try {
        await createShift(
          companyId: companyId,
          userId: userId,
          start: DateTime(day.year, day.month, day.day, startTime.hour, startTime.minute),
          end: DateTime(day.year, day.month, day.day, endTime.hour, endTime.minute),
          createdBy: createdBy,
          status: 'approved',
          origin: 'manager_scheduled',
          requiredSkillId: requiredSkillId,
        );
        created++;
      } catch (_) {
        skipped++;
      }
    }

    return (created: created, skipped: skipped);
  }

  static List<DateTime> datesForRecurrence(
    DateTime startDate,
    DateTime endDate,
    Set<int> daysOfWeek,
  ) {
    final result = <DateTime>[];
    for (var day = DateTime(startDate.year, startDate.month, startDate.day);
        !day.isAfter(endDate);
        day = day.add(const Duration(days: 1))) {
      if (daysOfWeek.contains(day.weekday)) {
        result.add(DateTime(day.year, day.month, day.day));
      }
    }
    return result;
  }

  // ----------------------------
  // OPEN-SHIFT PRIORITY (Feature 6)
  // ----------------------------

  /// Reads the company's `open_shift_priority` column.
  /// 'first_come' (default) = first-come-first-served.
  /// 'seniority_first' = earliest hire_date wins.
  static Future<String> _getOpenShiftPriority(String companyId) async {
    try {
      final res = await _db
          .from('companies')
          .select('open_shift_priority')
          .eq('id', companyId)
          .single();
      return res['open_shift_priority']?.toString() ?? 'first_come';
    } catch (_) {
      // Fail open: if we can't read the setting, don't lock anyone
      // out of claiming.
      return 'first_come';
    }
  }

  // ----------------------------
  // COPY SHIFTS (schedule templates / "copy last week")
  // ----------------------------

  /// Copies all approved/pending/open shifts in [sourceStart]..[sourceEnd]
  /// to a new date range [targetStart]..[targetEnd], preserving each
  /// shift's time-of-day and duration but shifting them forward (or
  /// backward) by the same amount. The [targetStart]..[targetEnd]
  /// range must be the same length as the source range.
  ///
  /// Each copy goes through [createShift] — NOT a raw insert — so
  /// subscription gating, time validation, and conflict checking all
  /// apply exactly as they do for a shift created one at a time.
  ///
  /// Copies are ALWAYS `manager_scheduled` / `approved` regardless of
  /// the source shift's status or origin. A template copy is a fresh
  /// manager decision — not a re-approval of an old employee request,
  /// and not a re-creation of someone's pending swap. Open shifts in
  /// the source are copied as assigned-to-manager-approved shifts if
  /// they had a claim, or as open shifts if they were still unclaimed;
  /// either way they become manager decisions on the copy.
  ///
  /// Returns the number of shifts successfully copied (conflicts on
  /// individual shifts are skipped, not fatal).
  static Future<int> copyShifts({
    required String companyId,
    required String createdBy,
    required DateTime sourceStart,
    required DateTime sourceEnd,
    required DateTime targetStart,
    required DateTime targetEnd,
  }) async {
    if (await SubscriptionService.isLocked(companyId)) {
      throw Exception(
        "Schedule editing is disabled — your trial has ended. Upgrade to continue.",
      );
    }

    final sourceSpan = sourceEnd.difference(sourceStart);
    final targetSpan = targetEnd.difference(targetStart);
    if (sourceSpan != targetSpan) {
      throw Exception("Source and target ranges must be the same length");
    }

    final shiftOffset = targetStart.difference(sourceStart);

    final allShifts = await getCompanyShifts(companyId);
    final sourceShifts = allShifts.where((s) {
      return (s.startTime.isAfter(sourceStart) ||
              s.startTime.isAtSameMomentAs(sourceStart)) &&
          (s.startTime.isBefore(sourceEnd) ||
              s.startTime.isAtSameMomentAs(sourceEnd));
    }).toList();

    if (sourceShifts.isEmpty) return 0;

    int copied = 0;

    for (final source in sourceShifts) {
      final newStart = source.startTime.add(shiftOffset);
      final newEnd = source.endTime.add(shiftOffset);

      try {
        // Copies are always manager_scheduled / approved — a template
        // copy is a fresh manager decision (see method doc comment).
        await createShift(
          companyId: companyId,
          userId: source.userId,
          start: newStart,
          end: newEnd,
          createdBy: createdBy,
          status: 'approved',
          origin: 'manager_scheduled',
        );
        copied++;
      } catch (_) {
        // Skip individual shifts that conflict — don't fail the whole
        // copy operation because one slot is already taken.
      }
    }

    return copied;
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

/// A time-of-day (hour + minute) used by recurring shift generation.
/// Kept as a value type so the screen can pass picked times without
/// coupling the service to Flutter's TimeOfDay.
class TimeOfDaySpec {
  final int hour;
  final int minute;

  const TimeOfDaySpec({required this.hour, required this.minute});
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