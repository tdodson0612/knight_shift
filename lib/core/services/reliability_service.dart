// lib/core/services/reliability_service.dart
//
// Owns reliability tracking: manager-configured settings (stored on
// `companies`, same pattern as OvertimeService) and the matching +
// scoring logic.
//
// SCHEMA CAVEAT (confirmed against live schema, not assumed): there
// is no shift_id column on time_entries, and no FK linking the two
// tables at all. So a clock event can't be looked up by shift
// directly — it's MATCHED to the nearest shift for that same user by
// time proximity (closest clock_in to a shift's scheduled start,
// within _matchWindowHours). This is an approximation, not a
// guaranteed-correct link, and can misfire in edge cases like
// back-to-back same-day shifts for one person.
//
// SIMPLIFICATION: "no-show" and "missed/unfilled shift assigned to
// them" are the SAME detected category here — an assigned shift
// whose scheduled time has fully passed with no matching clock-in
// found. Live data shows shifts.status is only ever 'approved' in
// practice (no check constraint enforces an enum), so there's no
// existing signal that would distinguish the two. If a real
// distinction is wanted (e.g. a manager manually marking a shift
// "missed" vs. the system auto-detecting a no-show), that needs its
// own field added to shifts first — not invented here.

import 'supabase_service.dart';
import '../../shared/models/reliability_settings_model.dart';
import '../../shared/models/shift_model.dart';

class ReliabilityService {
  static final _db = SupabaseService.client;

  // How far from a shift's scheduled start a clock-in is still
  // considered a candidate match for that shift. NOT the same as
  // the grace period (which governs what counts as LATE) — this is
  // just candidate matching, generously wide on purpose.
  static const _matchWindowHours = 4;

  // ----------------------------
  // SETTINGS (per company)
  // ----------------------------
  static Future<ReliabilitySettings> getSettings(String companyId) async {
    final res = await _db
        .from('companies')
        .select(
          'reliability_enabled, reliability_grace_minutes, '
          'reliability_track_late, reliability_track_early_leave, '
          'reliability_track_no_show, reliability_weight_mode, '
          'reliability_flat_points, reliability_weight_late, '
          'reliability_weight_early_leave, reliability_weight_no_show',
        )
        .eq('id', companyId)
        .single();

    return ReliabilitySettings.fromMap(res);
  }

  /// Manager-only in practice, enforced by the existing
  /// `companies_update` RLS policy (is_company_manager).
  static Future<void> updateSettings({
    required String companyId,
    required ReliabilitySettings settings,
  }) async {
    await _db.from('companies').update(settings.toMap()).eq('id', companyId);
  }

  // ----------------------------
  // STATS (per company, per period)
  // ----------------------------

  /// Computes reliability stats for every user with at least one
  /// PAST assigned shift in [start]..[end]. Only shifts whose
  /// end_time has already passed are evaluated — a future shift
  /// can't yet be late, early, or a no-show. [shifts] should already
  /// be filtered to the company by the caller (same convention as
  /// PayrollAnalyticsService).
  static Future<Map<String, ReliabilityStats>> calculateStatsByUser({
    required String companyId,
    required List<ShiftModel> shifts,
    required DateTime start,
    required DateTime end,
    required ReliabilitySettings settings,
  }) async {
    final now = DateTime.now();

    final evaluable = shifts.where((s) =>
        s.userId != null &&
        s.endTime.isBefore(now) &&
        (s.startTime.isAfter(start) || s.startTime.isAtSameMomentAs(start)) &&
        (s.startTime.isBefore(end) || s.startTime.isAtSameMomentAs(end)));

    final Map<String, List<ShiftModel>> shiftsByUser = {};
    for (final s in evaluable) {
      shiftsByUser.putIfAbsent(s.userId!, () => []).add(s);
    }

    if (shiftsByUser.isEmpty) return {};

    // Deliberately NOT filtering out incomplete entries (clock_out
    // null) the way PayrollAnalyticsService does — someone who
    // clocked in but hasn't clocked out yet still needs to be
    // matched for lateness purposes, just not for early-leave.
    final rows = await _db
        .from('time_entries')
        .select('user_id, clock_in, clock_out')
        .eq('company_id', companyId)
        .gte(
          'clock_in',
          start.subtract(const Duration(hours: _matchWindowHours)).toIso8601String(),
        )
        .lte(
          'clock_in',
          end.add(const Duration(hours: _matchWindowHours)).toIso8601String(),
        );

    final entries = List<Map<String, dynamic>>.from(rows);
    final Map<String, List<Map<String, dynamic>>> entriesByUser = {};
    for (final row in entries) {
      final userId = row['user_id']?.toString();
      if (userId == null) continue;
      entriesByUser.putIfAbsent(userId, () => []).add(row);
    }

    final Map<String, ReliabilityStats> result = {};

    for (final userId in shiftsByUser.keys) {
      final userShifts = shiftsByUser[userId]!
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      final candidateEntries =
          List<Map<String, dynamic>>.from(entriesByUser[userId] ?? []);

      int lateCount = 0;
      int earlyLeaveCount = 0;
      int noShowCount = 0;

      for (final shift in userShifts) {
        Map<String, dynamic>? best;
        Duration? bestDiff;

        for (final entry in candidateEntries) {
          final clockIn =
              DateTime.tryParse(entry['clock_in']?.toString() ?? '');
          if (clockIn == null) continue;

          final diff = clockIn.difference(shift.startTime).abs();
          if (diff.inHours > _matchWindowHours) continue;

          if (bestDiff == null || diff < bestDiff) {
            best = entry;
            bestDiff = diff;
          }
        }

        if (best == null) {
          if (settings.trackNoShow) noShowCount++;
          continue;
        }

        // Consumed — don't let a second shift match the same clock
        // event.
        candidateEntries.remove(best);

        final clockIn =
            DateTime.tryParse(best['clock_in']?.toString() ?? '');
        final clockOut =
            DateTime.tryParse(best['clock_out']?.toString() ?? '');

        if (settings.trackLate && clockIn != null) {
          final lateBy = clockIn.difference(shift.startTime);
          if (lateBy.inMinutes > settings.graceMinutes) lateCount++;
        }

        if (settings.trackEarlyLeave && clockOut != null) {
          final earlyBy = shift.endTime.difference(clockOut);
          if (earlyBy.inMinutes > settings.graceMinutes) earlyLeaveCount++;
        }
      }

      double deduction;
      if (settings.isWeighted) {
        deduction = lateCount * settings.weightLate +
            earlyLeaveCount * settings.weightEarlyLeave +
            noShowCount * settings.weightNoShow;
      } else {
        final infractions = lateCount + earlyLeaveCount + noShowCount;
        deduction = infractions * settings.flatPoints;
      }

      final score = (100 - deduction).clamp(0, 100).toDouble();

      result[userId] = ReliabilityStats(
        lateCount: lateCount,
        earlyLeaveCount: earlyLeaveCount,
        noShowCount: noShowCount,
        shiftsEvaluated: userShifts.length,
        score: score,
      );
    }

    return result;
  }
}