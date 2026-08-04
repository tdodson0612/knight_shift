// lib/core/services/employee_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/employee_profile.dart';

class EmployeeService {
  static final _client = Supabase.instance.client;

  /// COMPANY MEMBERS = SINGLE SOURCE OF TRUTH
  static Future<List<EmployeeProfile>> getCompanyEmployees(
    String companyId,
  ) async {
    final response = await _client
        .from('company_members')
        .select('user_id, role, hourly_rate, profiles(email, full_name)')
        .eq('company_id', companyId);

    final List data = response as List;

    return data.map<EmployeeProfile>((row) {
      final profile = (row['profiles'] as Map?) ?? {};

      return EmployeeProfile(
        userId: (row['user_id'] ?? '').toString(),
        displayName: (profile['full_name'] ?? '').toString(),
        email: (profile['email'] ?? '').toString(),
        role: (row['role'] ?? 'employee').toString(),
        companyId: companyId,
        hourlyRate: (row['hourly_rate'] ?? 20).toDouble(),
      );
    }).toList();
  }

  static Future<EmployeeProfile?> getEmployee(
    String companyId,
    String userId,
  ) async {
    final response = await _client
        .from('company_members')
        .select('user_id, role, hourly_rate, profiles(email, full_name)')
        .eq('company_id', companyId)
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) return null;

    final profile = (response['profiles'] as Map?) ?? {};

    return EmployeeProfile(
      userId: (response['user_id'] ?? '').toString(),
      displayName: (profile['full_name'] ?? '').toString(),
      email: (profile['email'] ?? '').toString(),
      role: (response['role'] ?? 'employee').toString(),
      companyId: companyId,
      hourlyRate: (response['hourly_rate'] ?? 20).toDouble(),
    );
  }

  /// Manager-only in practice. NOTE: this assumes company_members'
  /// existing RLS UPDATE policy (not re-checked in this pass) allows
  /// a manager to update another member's row — that's the case for
  /// role changes elsewhere in this app already (RoleService), so
  /// it's reasonable to expect the same holds for hourly_rate, but
  /// worth a quick pg_policies check on company_members if this
  /// fails silently (empty result, no error) rather than throwing.
  static Future<void> updateHourlyRate({
    required String companyId,
    required String userId,
    required double hourlyRate,
  }) async {
    await _client
        .from('company_members')
        .update({'hourly_rate': hourlyRate})
        .eq('company_id', companyId)
        .eq('user_id', userId);
  }
}