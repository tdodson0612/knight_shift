// lib/core/services/time_entry_service.dart
//
// Owns time_entries: clock in/out for employees (through the
// `clock_in` / `clock_out` database functions, which stamp the server's
// time), and reads/edits for managers. Every insert, update and delete
// is recorded automatically by the trg_time_entry_audit trigger.

import 'supabase_service.dart';
import '../../shared/models/time_entry_model.dart';

class TimeEntryService {
  static final _db = SupabaseService.client;

  // ----------------------------
  // CLOCK IN / OUT — server steps. The database stamps the time in the
  // company's time zone, so a phone's wrong clock can't change hours.
  // ----------------------------

  /// The signed-in user's open punch at [companyId], or null.
  static Future<TimeEntry?> getOpenEntry({
    required String companyId,
    required String userId,
  }) async {
    final res = await _db
        .from('time_entries')
        .select()
        .eq('company_id', companyId)
        .eq('user_id', userId)
        .isFilter('clock_out', null)
        .order('clock_in', ascending: false)
        .limit(1);

    final rows = List<Map<String, dynamic>>.from(res);
    return rows.isEmpty ? null : TimeEntry.fromMap(rows.first);
  }

  static Future<TimeEntry> clockIn({
    required String companyId,
    String? photoPath,
  }) async {
    final res = await _db.rpc(
      'clock_in',
      params: {'p_company_id': companyId, 'p_photo_path': photoPath},
    );
    return TimeEntry.fromMap(Map<String, dynamic>.from(res as Map));
  }

  static Future<TimeEntry> clockOut({required String companyId}) async {
    final res = await _db.rpc(
      'clock_out',
      params: {'p_company_id': companyId},
    );
    return TimeEntry.fromMap(Map<String, dynamic>.from(res as Map));
  }

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
