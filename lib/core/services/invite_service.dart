// lib/core/services/invite_service.dart

import 'supabase_service.dart';
import 'validation_service.dart';
import 'subscription_service.dart';
import '../../shared/models/company_invite.dart';

class InviteService {
  static final _db = SupabaseService.client;

  static Future<void> inviteUser({
    required String email,
    required String companyId,
    required String role,
    double? hourlyRate,
  }) async {
    final emailError = ValidationService.validateEmail(email);
    if (emailError != null) throw Exception(emailError);

    final roleError = ValidationService.validateRole(role);
    if (roleError != null) throw Exception(roleError);

    final companyError =
        ValidationService.validateCompanyId(companyId);
    if (companyError != null) throw Exception(companyError);

    if (await SubscriptionService.isLocked(companyId)) {
      throw Exception(
        "Employee invites are disabled — your trial has ended. Upgrade to continue.",
      );
    }

    final existing = await _db
        .from('company_invites')
        .select()
        .eq('email', email)
        .eq('company_id', companyId)
        .eq('status', 'pending')
        .maybeSingle();

    if (existing != null) {
      throw Exception("Invite already exists");
    }

    await _db.from('company_invites').insert({
      'email': email,
      'company_id': companyId,
      'role': role,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
      if (hourlyRate != null) 'hourly_rate': hourlyRate,
    });
  }

  static Future<void> acceptInvite({
    required String userId,
    required String email,
    required String companyId,
  }) async {
    final companyError =
        ValidationService.validateCompanyId(companyId);
    if (companyError != null) throw Exception(companyError);

    final userError = ValidationService.validateUserId(userId);
    if (userError != null) throw Exception(userError);

    final invite = await _db
        .from('company_invites')
        .select()
        .eq('email', email)
        .eq('company_id', companyId)
        .eq('status', 'pending')
        .maybeSingle();

    if (invite == null) {
      throw Exception("No valid invite found");
    }

    await _db.from('company_members').insert({
      'user_id': userId,
      'company_id': companyId,
      'role': invite['role'] ?? 'employee',
      if (invite['hourly_rate'] != null) 'hourly_rate': invite['hourly_rate'],
    });

    await _db
        .from('company_invites')
        .update({'status': 'accepted'})
        .eq('id', invite['id']);
  }

  static Future<List<CompanyInvite>> getCompanyInvites(
    String companyId,
  ) async {
    final res = await _db
        .from('company_invites')
        .select()
        .eq('company_id', companyId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res)
        .map(CompanyInvite.fromMap)
        .toList();
  }

  static Future<void> revokeInvite(String inviteId) async {
    await _db
        .from('company_invites')
        .update({'status': 'revoked'})
        .eq('id', inviteId);
  }
}