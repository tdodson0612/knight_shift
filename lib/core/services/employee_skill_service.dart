// lib/core/services/employee_skill_service.dart
//
// Owns company-wide skill tags (e.g. "bartender", "certified
// forklift") and per-employee skill assignments. Manager-managed;
// advisory-only in the scheduling flow (a manager assigning someone
// without the required tag gets a warning, never a block).

import 'supabase_service.dart';
import '../../shared/models/employee_skill_model.dart';

class EmployeeSkillService {
  static final _db = SupabaseService.client;

  // ----------------------------
  // SKILL TAGS (company-wide)
  // ----------------------------

  /// All skill tags for the company. RLS restricts to company members.
  static Future<List<EmployeeSkill>> getSkills(String companyId) async {
    final res = await _db
        .from('employee_skills')
        .select()
        .eq('company_id', companyId)
        .order('label', ascending: true);

    return List<Map<String, dynamic>>.from(res)
        .map(EmployeeSkill.fromMap)
        .toList();
  }

  /// Manager-only in practice via employee_skills_insert RLS.
  static Future<void> addSkill({
    required String companyId,
    required String label,
  }) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;

    await _db.from('employee_skills').insert({
      'company_id': companyId,
      'label': trimmed,
    });
  }

  /// Manager-only in practice via employee_skills_delete RLS.
  static Future<void> deleteSkill(String skillId) async {
    await _db.from('employee_skills').delete().eq('id', skillId);
  }

  // ----------------------------
  // ASSIGNMENTS (employee -> skill)
  // ----------------------------

  static Future<List<EmployeeSkillAssignment>> getAssignments(
    String companyId,
  ) async {
    final res = await _db
        .from('employee_skill_assignments')
        .select()
        .eq('company_id', companyId);

    return List<Map<String, dynamic>>.from(res)
        .map(EmployeeSkillAssignment.fromMap)
        .toList();
  }

  static Future<List<EmployeeSkillAssignment>> getAssignmentsForUser({
    required String companyId,
    required String userId,
  }) async {
    final res = await _db
        .from('employee_skill_assignments')
        .select()
        .eq('company_id', companyId)
        .eq('user_id', userId);

    return List<Map<String, dynamic>>.from(res)
        .map(EmployeeSkillAssignment.fromMap)
        .toList();
  }

  /// Manager-only in practice via employee_skill_assignments_insert RLS.
  static Future<void> assignSkill({
    required String companyId,
    required String userId,
    required String skillId,
  }) async {
    try {
      await _db.from('employee_skill_assignments').insert({
        'company_id': companyId,
        'user_id': userId,
        'skill_id': skillId,
      });
    } catch (_) {
      // Unique (user_id, skill_id) — already assigned. Not an error.
    }
  }

  /// Manager-only in practice via employee_skill_assignments_delete RLS.
  static Future<void> unassignSkill({
    required String companyId,
    required String userId,
    required String skillId,
  }) async {
    await _db
        .from('employee_skill_assignments')
        .delete()
        .eq('company_id', companyId)
        .eq('user_id', userId)
        .eq('skill_id', skillId);
  }

  // ----------------------------
  // ADVISORY CHECK (scheduling)
  // ----------------------------

  /// True if [userId] does NOT have [skillId] assigned. Used by the
  /// scheduling screen to warn (not block) when a shift requires a
  /// skill the assigned employee lacks.
  static Future<bool> userLacksSkill({
    required String companyId,
    required String userId,
    required String skillId,
  }) async {
    final res = await _db
        .from('employee_skill_assignments')
        .select('id')
        .eq('company_id', companyId)
        .eq('user_id', userId)
        .eq('skill_id', skillId)
        .maybeSingle();

    return res == null;
  }
}