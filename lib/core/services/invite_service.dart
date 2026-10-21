// lib/core/services/invite_service.dart

import 'supabase_service.dart';
import 'validation_service.dart';
import 'subscription_service.dart';
import 'company_service.dart';
import '../../shared/models/company_invite.dart';

class InviteService {
  static final _db = SupabaseService.client;

  static Future<void> inviteUser({
    required String email,
    required String companyId,
    required String role,
    double? hourlyRate,
  }) async {
    // Emails are compared in lowercase everywhere (the database also
    // lowercases them), so "John@Gmail.com" matches "john@gmail.com".
    final normalizedEmail = email.trim().toLowerCase();

    final emailError = ValidationService.validateEmail(normalizedEmail);
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
        .select('id')
        .eq('email', normalizedEmail)
        .eq('company_id', companyId)
        .eq('status', 'pending')
        .maybeSingle();

    if (existing != null) {
      throw Exception("An invite for $normalizedEmail is already waiting");
    }

    await _db.from('company_invites').insert({
      'email': normalizedEmail,
      'company_id': companyId,
      'role': role,
      'status': 'pending',
      if (hourlyRate != null) 'hourly_rate': hourlyRate,
    });
  }

  /// Pending invites for the signed-in user's email, with company
  /// names (the `list_my_invites` database function).
  static Future<List<CompanyInvite>> getMyInvites() async {
    final res = await _db.rpc('list_my_invites');

    return List<Map<String, dynamic>>.from(res as List)
        .map(
          (row) => CompanyInvite(
            id: row['invite_id'].toString(),
            email: '',
            role: row['role']?.toString() ?? 'employee',
            status: 'pending',
            companyId: row['company_id'].toString(),
            companyName: row['company_name']?.toString(),
          ),
        )
        .toList();
  }

  /// Accepts one invite in a single server step (the `accept_invite`
  /// database function), which checks the invite really is for the
  /// signed-in user's email before adding them to the company.
  static Future<CreatedCompany> acceptInvite(String inviteId) async {
    final res = await _db.rpc(
      'accept_invite',
      params: {'p_invite_id': inviteId},
    );

    return CreatedCompany.fromMap(Map<String, dynamic>.from(res as Map));
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
