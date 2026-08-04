// lib/core/services/time_entry_service.dart
//
// Owns time_entries reads/edits for managers, and the audit trail
// that comes with them. This is a NEW service — previously
// home_screen.dart called Supabase directly for clock in/out with no
// dedicated service, and there was no manager-facing edit path at
// all. Clock in/out in home_screen.dart is left as-is (still works
// exactly as before); this service adds the missing manager
// correction + audit capability on top, per the existing
// trg_time_entry_audit trigger which logs every insert/update/delete
// automatically regardless of which code path caused it.

import 'supabase_service.dart';
import '../../shared/models/time_entry_model.dart';

class TimeEntryService {
  static final _db = SupabaseService.client;

  static Future<List<TimeEntry>> getCompanyTimeEntries({
    required String companyId,
    required DateTime start,
    required DateTime end,
  }) async {
    final res = await _db
        .from('time_entries')
        .select()
        .eq('company_id', companyId)
        .gte('clock_in', start.toIso8601String())
        .lte('clock_in', end.toIso8601String())
        .order('clock_in', ascending: false);

    return List<Map<String, dynamic>>.from(res)
        .map(TimeEntry.fromMap)
        .toList();
  }

  /// Manager correction of a punch. RLS (time_entries_manager_update)
  /// enforces this is manager-only — a non-manager calling it just
  /// gets an RLS failure, not a client-side check here.
  static Future<void> updateTimeEntry({
    required String timeEntryId,
    required DateTime clockIn,
    DateTime? clockOut,
  }) async {
    await _db.from('time_entries').update({
      'clock_in': clockIn.toIso8601String(),
      'clock_out': clockOut?.toIso8601String(),
    }).eq('id', timeEntryId);
  }

  /// Full edit history for one punch, most recent first. RLS
  /// (time_entry_audit_log_select) restricts this to managers.
  static Future<List<TimeEntryAuditEntry>> getAuditLog(
    String timeEntryId,
  ) async {
    final res = await _db
        .from('time_entry_audit_log')
        .select()
        .eq('time_entry_id', timeEntryId)
        .order('changed_at', ascending: false);

    return List<Map<String, dynamic>>.from(res)
        .map(TimeEntryAuditEntry.fromMap)
        .toList();
  }
}
