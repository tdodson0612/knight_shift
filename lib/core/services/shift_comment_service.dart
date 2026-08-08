// lib/core/services/shift_comment_service.dart
//
// Shift-scoped comment thread. Append-only — no update/delete
// policy exists, matching how a real conversation log should behave
// rather than an editable chat.

import 'supabase_service.dart';
import '../../shared/models/shift_comment_model.dart';

class ShiftCommentService {
  static final _db = SupabaseService.client;

  static Future<bool> isEnabled(String companyId) async {
    final res = await _db
        .from('companies')
        .select('shift_comments_enabled')
        .eq('id', companyId)
        .single();
    return res['shift_comments_enabled'] as bool? ?? false;
  }

  /// Manager-only in practice via companies_update RLS.
  static Future<void> setEnabled(String companyId, bool enabled) async {
    await _db
        .from('companies')
        .update({'shift_comments_enabled': enabled})
        .eq('id', companyId);
  }

  static Future<List<ShiftComment>> getComments(String shiftId) async {
    final res = await _db
        .from('shift_comments')
        .select()
        .eq('shift_id', shiftId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(res)
        .map(ShiftComment.fromMap)
        .toList();
  }

  static Future<void> postComment({
    required String shiftId,
    required String companyId,
    required String userId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;

    await _db.from('shift_comments').insert({
      'shift_id': shiftId,
      'company_id': companyId,
      'user_id': userId,
      'body': trimmed,
    });
  }
}