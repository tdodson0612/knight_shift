// lib/core/services/labor_budget_service.dart
//
// Owns per-company labor budget settings (stored on `companies`,
// same pattern as OvertimeService / GeofenceService) and the pure
// live projection math used by ManagerSchedulingScreen to surface
// overtime-risk and budget warnings while building the schedule.
//
// Advisory only — never blocks shift creation. Same fail-open
// philosophy as the existing availability/time-off advisory check
// in ShiftService._checkAdvisories.

import 'supabase_service.dart';
import '../../shared/models/labor_budget_settings_model.dart';
import '../../shared/models/shift_model.dart';
import '../../shared/models/overtime_settings_model.dart';
import 'employee_service.dart';

class LaborBudgetService {
  static final _db = SupabaseService.client;

  // ----------------------------
  // SETTINGS (per company)
  // ----------------------------
  static Future<LaborBudgetSettings> getSettings(String companyId) async {
    final res = await _db
        .from('companies')
        .select('labor_budget_enabled, labor_budget_amount')
        .eq('id', companyId)
        .single();

    return LaborBudgetSettings.fromMap(res);
  }

  /// Manager-only in practice, enforced by the existing
  /// `companies_update` RLS policy (is_company_manager).
  static Future<void> updateSettings({
    required String companyId,
    required LaborBudgetSettings settings,
  }) async {
    await _db
        .from('companies')
        .update(settings.toMap())
        .eq('id', companyId);
  }

  // ----------------------------
  // LIVE PROJECTION (scheduling-time)
  // ----------------------------

  /// Computes the projected weekly labor cost for [companyId] if a
  /// new shift [newStart]..[newEnd] for [userId] were added, using
  /// each employee's hourly rate from `company_members`. Returns the
  /// projected total for the week that contains [newStart].
  ///
  /// This is a SCHEDULED-hours projection (what the manager is
  /// building), NOT an actual-clock reconciliation — it deliberately
  /// does not touch `time_entries`. That matches the scheduling
  /// screen's purpose: "if I add this shift, what does the week cost?"
  static Future<double> projectedWeeklyLaborCost({
    required String companyId,
    required List<ShiftModel> shifts,
    required DateTime newStart,
    required DateTime newEnd,
    String? userId,
  }) async {
    final weekStart = _mondayOf(newStart);
    final weekEnd = weekStart.add(const Duration(days: 7));

    // Rates: build a userId -> hourlyRate map once.
    final employees = await EmployeeService.getCompanyEmployees(companyId);
    final rateByUser = {for (final e in employees) e.userId: e.hourlyRate};

    double total = 0;

    for (final s in shifts) {
      if (s.userId == null) continue;
      if (s.startTime.isBefore(weekStart) ||
          s.startTime.isAtSameMomentAs(weekEnd) ||
          s.startTime.isAfter(weekEnd)) {
        continue;
      }

      final rate = rateByUser[s.userId] ?? 20;
      final hours = s.endTime.difference(s.startTime).inMinutes / 60.0;
      total += hours * rate;
    }

    // Add the prospective shift itself (if it has an employee).
    if (userId != null) {
      final rate = rateByUser[userId] ?? 20;
      final hours = newEnd.difference(newStart).inMinutes / 60.0;
      total += hours * rate;
    }

    return total;
  }

  /// True if the projected weekly labor cost exceeds [budget].
  static bool exceedsBudget({
    required double projectedCost,
    required LaborBudgetSettings budget,
  }) {
    if (!budget.enabled || budget.amount <= 0) return false;
    return projectedCost > budget.amount;
  }

  /// Estimates an employee's projected weekly hours if [newStart]..
  /// [newEnd] were added, by summing all their scheduled shifts in
  /// the same Monday-start week as [newStart] (including the new one).
  /// Used by the overtime-risk warning in the scheduling screen.
  static double projectedWeeklyHours({
    required List<ShiftModel> shifts,
    required DateTime newStart,
    required DateTime newEnd,
    required String userId,
  }) {
    final weekStart = _mondayOf(newStart);
    final weekEnd = weekStart.add(const Duration(days: 7));

    double hours = 0;

    for (final s in shifts) {
      if (s.userId != userId) continue;
      if (s.startTime.isBefore(weekStart) ||
          s.startTime.isAtSameMomentAs(weekEnd) ||
          s.startTime.isAfter(weekEnd)) {
        continue;
      }
      hours += s.endTime.difference(s.startTime).inMinutes / 60.0;
    }

    hours += newEnd.difference(newStart).inMinutes / 60.0;
    return hours;
  }

  /// True if the projected weekly hours cross the configured weekly
  /// overtime threshold.
  static bool crossesOvertimeThreshold({
    required double projectedHours,
    required OvertimeSettings overtime,
  }) {
    if (!overtime.weeklyEnabled) return false;
    return projectedHours > overtime.weeklyThresholdHours;
  }

  static DateTime _mondayOf(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return date.subtract(Duration(days: date.weekday - DateTime.monday));
  }
}