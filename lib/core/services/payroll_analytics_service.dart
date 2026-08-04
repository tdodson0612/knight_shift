// lib/core/services/payroll_analytics_service.dart

import 'supabase_service.dart';
import 'shift_analytics_service.dart';
import '../../shared/models/shift_model.dart';

/// Reconciles worked hours for payroll purposes.
///
/// Architecture (per product decision):
///   Shift      = planning layer   (scheduled, from `shifts`)
///   TimeEntry  = truth layer      (actual clock in/out, from `time_entries`)
///   Payroll    = reconciliation engine (this service)
///
/// Rule, per employee, for a given period:
///   IF completed time_entries exist in the period → use actual clocked hours
///   ELSE → fall back to scheduled shift hours
///
/// This does NOT replace ShiftAnalyticsService — it uses it as the
/// fallback calculation for employees with no clock data.
class PayrollAnalyticsService {
  static final _db = SupabaseService.client;

  /// Returns hours worked per user for [companyId] within
  /// [start]..[end], reconciling time_entries against scheduled
  /// [shifts] (already filtered to the same period by the caller).
  ///
  /// UNCHANGED from before — still delegates the scheduled-hours
  /// fallback to ShiftAnalyticsService. See
  /// [calculateDailyHoursByUser] below for the day-by-day breakdown
  /// used by overtime calculations, which is a separate, additive
  /// method rather than a refactor of this one, specifically so
  /// nothing already relying on this method's exact behavior
  /// (ManagerDashboard, PayrollScreen totals) is put at risk.
  static Future<Map<String, double>> calculateHoursByUser({
    required String companyId,
    required List<ShiftModel> shifts,
    required DateTime start,
    required DateTime end,
  }) async {
    final scheduledHours = ShiftAnalyticsService.calculateHoursByUser(
      shifts,
    );

    final rows = await _db
        .from('time_entries')
        .select('user_id, clock_in, clock_out')
        .eq('company_id', companyId)
        .not('clock_out', 'is', null)
        .gte('clock_in', start.toIso8601String())
        .lte('clock_in', end.toIso8601String());

    final data = List<Map<String, dynamic>>.from(rows);

    final Map<String, double> clockedHours = {};

    for (final row in data) {
      final userId = row['user_id']?.toString();
      final clockIn = DateTime.tryParse(row['clock_in']?.toString() ?? '');
      final clockOut = DateTime.tryParse(row['clock_out']?.toString() ?? '');

      if (userId == null || clockIn == null || clockOut == null) continue;

      final hours = clockOut.difference(clockIn).inMinutes / 60.0;
      clockedHours[userId] = (clockedHours[userId] ?? 0) + hours;
    }

    final Map<String, double> result = {};

    final allUserIds = {
      ...scheduledHours.keys,
      ...clockedHours.keys,
    };

    for (final userId in allUserIds) {
      final clocked = clockedHours[userId];
      result[userId] = clocked ?? scheduledHours[userId] ?? 0;
    }

    return result;
  }

  /// Same reconciliation rule as [calculateHoursByUser] (clocked
  /// hours win at the user level if any completed time_entries exist
  /// in the period; otherwise fall back to scheduled shift hours) —
  /// but broken out by calendar day, which the daily overtime
  /// threshold needs (see OvertimeService.splitHours). Returned
  /// inner-map keys are date-only DateTimes (no time component).
  ///
  /// NOTE: the scheduled-hours fallback here is computed directly
  /// from ShiftModel (skip shifts with no assigned user, sum
  /// endTime - startTime) rather than through ShiftAnalyticsService,
  /// since that service only exposes period totals, not a per-day
  /// breakdown. This is believed to match ShiftAnalyticsService's
  /// own null-handling but hasn't been verified against its source —
  /// worth a quick diff if shift_analytics_service.dart changes.
  static Future<Map<String, Map<DateTime, double>>>
      calculateDailyHoursByUser({
    required String companyId,
    required List<ShiftModel> shifts,
    required DateTime start,
    required DateTime end,
  }) async {
    // 1. Scheduled-hours fallback, by day.
    final Map<String, Map<DateTime, double>> scheduledDaily = {};
    for (final s in shifts) {
      final userId = s.userId;
      if (userId == null) continue;

      final day =
          DateTime(s.startTime.year, s.startTime.month, s.startTime.day);
      final hours = s.endTime.difference(s.startTime).inMinutes / 60.0;

      final userMap = scheduledDaily.putIfAbsent(userId, () => {});
      userMap[day] = (userMap[day] ?? 0) + hours;
    }

    // 2. Actual clocked hours, by day — bucketed by clock_in's date.
    //    An overnight shift's hours are attributed entirely to the
    //    day it started, not split across midnight.
    final rows = await _db
        .from('time_entries')
        .select('user_id, clock_in, clock_out')
        .eq('company_id', companyId)
        .not('clock_out', 'is', null)
        .gte('clock_in', start.toIso8601String())
        .lte('clock_in', end.toIso8601String());

    final data = List<Map<String, dynamic>>.from(rows);
    final Map<String, Map<DateTime, double>> clockedDaily = {};

    for (final row in data) {
      final userId = row['user_id']?.toString();
      final clockIn = DateTime.tryParse(row['clock_in']?.toString() ?? '');
      final clockOut = DateTime.tryParse(row['clock_out']?.toString() ?? '');

      if (userId == null || clockIn == null || clockOut == null) continue;

      final day = DateTime(clockIn.year, clockIn.month, clockIn.day);
      final hours = clockOut.difference(clockIn).inMinutes / 60.0;

      final userMap = clockedDaily.putIfAbsent(userId, () => {});
      userMap[day] = (userMap[day] ?? 0) + hours;
    }

    // 3. Reconcile at the user level: clocked data wins entirely if
    //    present for that user, else use the scheduled fallback.
    final Map<String, Map<DateTime, double>> result = {};
    final allUserIds = {...scheduledDaily.keys, ...clockedDaily.keys};

    for (final userId in allUserIds) {
      result[userId] = clockedDaily[userId] ?? scheduledDaily[userId] ?? {};
    }

    return result;
  }
}