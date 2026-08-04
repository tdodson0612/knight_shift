// lib/core/services/availability_service.dart

import 'supabase_service.dart';
import '../../shared/models/availability_model.dart';

class AvailabilityService {
  static final _db = SupabaseService.client;

  static Future<List<AvailabilityWindow>> getAvailability(
    String companyId,
    String userId,
  ) async {
    final res = await _db
        .from('employee_availability')
        .select()
        .eq('company_id', companyId)
        .eq('user_id', userId);

    return List<Map<String, dynamic>>.from(res)
        .map(AvailabilityWindow.fromMap)
        .toList();
  }

  /// Replaces the employee's entire weekly availability with
  /// [windows]. Simpler and safer than diffing individual days —
  /// the UI always saves the full week at once.
  static Future<void> setAvailability({
    required String companyId,
    required String userId,
    required List<AvailabilityWindow> windows,
  }) async {
    await _db
        .from('employee_availability')
        .delete()
        .eq('company_id', companyId)
        .eq('user_id', userId);

    if (windows.isEmpty) return;

    final payload = windows
        .map((w) => w.toInsertMap(companyId: companyId, userId: userId))
        .toList();

    await _db.from('employee_availability').insert(payload);
  }

  /// True if [dateTime] falls within a stated availability window for
  /// that day. If the employee has no availability data at all yet
  /// (never set anything), this returns true — absence of data
  /// should never block scheduling; only an explicit "not available"
  /// (no window for that day) should trigger the soft warning.
  static Future<bool> isWithinAvailability({
    required String companyId,
    required String userId,
    required DateTime dateTime,
  }) async {
    final windows = await getAvailability(companyId, userId);
    if (windows.isEmpty) return true;

    return windows.any((w) => w.contains(dateTime));
  }
}