// lib/core/services/role_service.dart

import 'supabase_service.dart';
import 'session_service.dart';

class RoleService {
  static final _db = SupabaseService.client;

  /// Fetch role from DB (source of truth)
  static Future<String?> getRole({
    required String companyId,
    required String userId,
  }) async {
    final res = await _db
        .from('company_members')
        .select('role')
        .eq('company_id', companyId)
        .eq('user_id', userId)
        .maybeSingle();

    return res?['role']?.toString();
  }

  /// Sync SessionService role with DB
  static Future<void> syncRole({
    required String companyId,
    required String userId,
  }) async {
    final role = await getRole(
      companyId: companyId,
      userId: userId,
    );

    if (role != null) {
      SessionService.activeRole = role;
    }
  }

  /// Permission checks (single source of truth)
  static bool isManager() {
    return SessionService.activeRole == 'manager' ||
        SessionService.activeRole == 'admin';
  }

  static bool isAdmin() {
    return SessionService.activeRole == 'admin';
  }

  static bool isEmployee() {
    return SessionService.activeRole == 'employee';
  }

  /// Read-only bookkeeper/accountant seat — deliberately NOT included
  /// in isManager(). This role should never gain scheduling, invite,
  /// or employee-management permissions; it exists purely to view
  /// payroll history without a manager needing to export/email data.
  static bool isAccountant() {
    return SessionService.activeRole == 'accountant';
  }

  static bool canManageEmployees() {
    return isManager();
  }

  static bool canEditSchedule() {
    return isManager();
  }

  static bool canInviteUsers() {
    return isManager();
  }

  static bool canViewDashboard() {
    return SessionService.hasCompany;
  }
}