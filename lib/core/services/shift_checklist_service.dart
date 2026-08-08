// lib/core/services/shift_checklist_service.dart
//
// Company-wide checklist item templates (manager-managed) and
// per-shift completion tracking. Any company member can check/
// uncheck an item on a shift they can see — casual, not a
// manager-only approval step.

import 'supabase_service.dart';
import '../../shared/models/shift_checklist_model.dart';

class ShiftChecklistService {
  static final _db = SupabaseService.client;

  static Future<bool> isEnabled(String companyId) async {
    final res = await _db
        .from('companies')
        .select('shift_checklists_enabled')
        .eq('id', companyId)
        .single();
    return res['shift_checklists_enabled'] as bool? ?? false;
  }

  /// Manager-only in practice via companies_update RLS.
  static Future<void> setEnabled(String companyId, bool enabled) async {
    await _db
        .from('companies')
        .update({'shift_checklists_enabled': enabled})
        .eq('id', companyId);
  }

  static Future<List<ShiftChecklistItem>> getItems(String companyId) async {
    final res = await _db
        .from('shift_checklist_items')
        .select()
        .eq('company_id', companyId)
        .order('sort_order', ascending: true);

    return List<Map<String, dynamic>>.from(res)
        .map(ShiftChecklistItem.fromMap)
        .toList();
  }

  /// Manager-only in practice via shift_checklist_items_insert RLS.
  static Future<void> addItem({
    required String companyId,
    required String label,
    int sortOrder = 0,
  }) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;

    await _db.from('shift_checklist_items').insert({
      'company_id': companyId,
      'label': trimmed,
      'sort_order': sortOrder,
    });
  }

  /// Manager-only in practice via shift_checklist_items_delete RLS.
  static Future<void> deleteItem(String itemId) async {
    await _db.from('shift_checklist_items').delete().eq('id', itemId);
  }

  static Future<List<ShiftChecklistCompletion>> getCompletions(
    String shiftId,
  ) async {
    final res = await _db
        .from('shift_checklist_completions')
        .select()
        .eq('shift_id', shiftId);

    return List<Map<String, dynamic>>.from(res)
        .map(ShiftChecklistCompletion.fromMap)
        .toList();
  }

  static Future<void> checkItem({
    required String shiftId,
    required String itemId,
    required String userId,
  }) async {
    await _db.from('shift_checklist_completions').insert({
      'shift_id': shiftId,
      'item_id': itemId,
      'completed_by': userId,
    });
  }

  static Future<void> uncheckItem({
    required String shiftId,
    required String itemId,
  }) async {
    await _db
        .from('shift_checklist_completions')
        .delete()
        .eq('shift_id', shiftId)
        .eq('item_id', itemId);
  }
}