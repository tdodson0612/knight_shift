// lib/core/services/session_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionService {
  static String? activeCompanyId;
  static String? activeCompanyName;
  static String? activeRole;
  static String? activeUserId;

  static const _kCompanyId = "company_id";
  static const _kCompanyName = "company_name";
  static const _kRole = "role";
  static const _kUserId = "user_id";

  // ----------------------------
  // SET SESSION
  // ----------------------------

  static Future<void> setActiveCompany({
    required String companyId,
    required String companyName,
    required String role,
    required String userId,
  }) async {
    activeCompanyId = companyId;
    activeCompanyName = companyName;
    activeRole = role;
    activeUserId = userId;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_kCompanyId, companyId);
    await prefs.setString(_kCompanyName, companyName);
    await prefs.setString(_kRole, role);
    await prefs.setString(_kUserId, userId);
  }

  // ----------------------------
  // RESTORE SESSION
  // ----------------------------

  static Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();

    activeCompanyId = prefs.getString(_kCompanyId);
    activeCompanyName = prefs.getString(_kCompanyName);
    activeRole = prefs.getString(_kRole);
    activeUserId = prefs.getString(_kUserId);
  }

  // ----------------------------
  // CLEAR SESSION
  // ----------------------------

  static Future<void> clear() async {
    activeCompanyId = null;
    activeCompanyName = null;
    activeRole = null;
    activeUserId = null;

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_kCompanyId);
    await prefs.remove(_kCompanyName);
    await prefs.remove(_kRole);
    await prefs.remove(_kUserId);
  }

  // ----------------------------
  // HELPERS
  // ----------------------------

  // NOTE: an `isManager` getter used to live here, checking only
  // `activeRole == 'manager'` — silently excluding 'admin', unlike
  // RoleService.isManager() (the actual source of truth everywhere
  // else in this app, per the project's own convention: "never check
  // roles inline in UI"). Confirmed zero call sites via
  // `grep -rn "SessionService.isManager" lib/` before removing it —
  // it was dead code, not a behavior change for anything live. Use
  // RoleService.isManager() for any manager check.
  static bool get hasCompany => activeCompanyId != null;

  // ----------------------------
  // COMPANY LOOKUP (used by CompanySelectionScreen)
  // ----------------------------

  /// Returns every company_members row for the current user, each
  /// joined with its company name — the shape CompanySelectionScreen
  /// expects: row['company_id'], row['companies']['name'], row['role'].
  static Future<List<Map<String, dynamic>>> getMyCompanies() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    final res = await Supabase.instance.client
        .from('company_members')
        .select('company_id, role, companies(name)')
        .eq('user_id', user.id);

    return List<Map<String, dynamic>>.from(res);
  }
}