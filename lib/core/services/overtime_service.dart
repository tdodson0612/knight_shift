// lib/core/services/overtime_service.dart
//
// Owns everything overtime-related: reading/writing each company's
// manager-configured thresholds, and the pure hour-splitting math
// used by payroll generation. One domain, one service.
//
// Overlap rule (explicit product decision, confirmed with the human
// — not invented here): when both daily and weekly thresholds are
// enabled, hours already counted as daily overtime are ALSO counted
// toward the weekly total's raw hours. This is the simpler of two
// valid approaches and can result in some hours being paid at the
// overtime rate under both rules — that tradeoff was chosen
// deliberately over the more complex "exclude daily OT from weekly
// total" approach.

import 'supabase_service.dart';
import '../../shared/models/overtime_settings_model.dart';

class OvertimeService {
  static final _db = SupabaseService.client;

  // ----------------------------
  // SETTINGS (per company)
  // ----------------------------
  static Future<OvertimeSettings> getSettings(String companyId) async {
    final res = await _db
        .from('companies')
        .select(
          'overtime_daily_enabled, overtime_daily_threshold_hours, '
          'overtime_weekly_enabled, overtime_weekly_threshold_hours, '
          'overtime_pay_mode, overtime_multiplier',
        )
        .eq('id', companyId)
        .single();

    return OvertimeSettings.fromMap(res);
  }

  /// Manager-only in practice, enforced by the existing
  /// `companies_update` RLS policy (is_company_manager) — not
  /// re-checked client-side here.
  static Future<void> updateSettings({
    required String companyId,
    required OvertimeSettings settings,
  }) async {
    await _db.from('companies').update(settings.toMap()).eq('id', companyId);
  }

  // ----------------------------
  // PURE COMPUTATION
  // ----------------------------

  /// Splits one user's day-by-day hours into regular vs overtime for
  /// a payroll period, per [settings]. [dailyHours] keys must be
  /// date-only DateTimes (no time component) -> hours worked that
  /// day. Weeks are Monday-start, matching the "This Week" convention
  /// already used in ManagerDashboard.
  static OvertimeBreakdown splitHours({
    required Map<DateTime, double> dailyHours,
    required double hourlyRate,
    required OvertimeSettings settings,
  }) {
    final totalHours = dailyHours.values.fold(0.0, (a, b) => a + b);

    if (!settings.anyThresholdEnabled || dailyHours.isEmpty) {
      return OvertimeBreakdown(
        totalHours: totalHours,
        regularHours: totalHours,
        overtimeHours: 0,
        regularPay: totalHours * hourlyRate,
        overtimePay: 0,
      );
    }

    // 1. Daily overtime: sum of hours over the daily threshold, per
    //    day worked.
    double dailyOT = 0;
    if (settings.dailyEnabled) {
      for (final hours in dailyHours.values) {
        if (hours > settings.dailyThresholdHours) {
          dailyOT += hours - settings.dailyThresholdHours;
        }
      }
    }

    // 2. Weekly overtime: group days into Monday-start weeks, sum of
    //    each week's hours over the weekly threshold. Uses the FULL
    //    day totals (not reduced by daily OT already found above) —
    //    see file-level note on the overlap rule.
    double weeklyOT = 0;
    if (settings.weeklyEnabled) {
      final Map<DateTime, double> weekTotals = {};
      for (final entry in dailyHours.entries) {
        final weekStart = _mondayOf(entry.key);
        weekTotals[weekStart] = (weekTotals[weekStart] ?? 0) + entry.value;
      }
      for (final weekHours in weekTotals.values) {
        if (weekHours > settings.weeklyThresholdHours) {
          weeklyOT += weekHours - settings.weeklyThresholdHours;
        }
      }
    }

    final overtimeHours = dailyOT + weeklyOT;
    // Clamp — guards the edge case where combined daily + weekly
    // overtime exceeds total hours worked, which would otherwise
    // push regular hours negative.
    final regularHours =
        (totalHours - overtimeHours) < 0 ? 0.0 : totalHours - overtimeHours;

    if (!settings.calculatesPay) {
      // hours_only mode: report the split for visibility, but pay
      // everything at straight rate — no multiplier applied.
      return OvertimeBreakdown(
        totalHours: totalHours,
        regularHours: regularHours,
        overtimeHours: overtimeHours,
        regularPay: totalHours * hourlyRate,
        overtimePay: 0,
      );
    }

    return OvertimeBreakdown(
      totalHours: totalHours,
      regularHours: regularHours,
      overtimeHours: overtimeHours,
      regularPay: regularHours * hourlyRate,
      overtimePay: overtimeHours * hourlyRate * settings.multiplier,
    );
  }

  static DateTime _mondayOf(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return date.subtract(Duration(days: date.weekday - DateTime.monday));
  }
}