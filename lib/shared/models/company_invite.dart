// lib/shared/models/company_invite.dart

class CompanyInvite {
  final String id;
  final String email;
  final String role;
  final String status;
  final String companyId;

  // Not backed by a real column on company_invites — there is no
  // company_name field in the schema. Kept nullable so call sites
  // fall back explicitly (e.g. companyName ?? 'Company') instead of
  // the model silently implying data that doesn't exist.
  final String? companyName;

  CompanyInvite({
    required this.id,
    required this.email,
    required this.role,
    required this.status,
    required this.companyId,
    this.companyName,
  });

  factory CompanyInvite.fromMap(Map<String, dynamic> map) {
    return CompanyInvite(
      id: map['id']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      role: map['role']?.toString() ?? 'employee',
      status: map['status']?.toString() ?? 'pending',
      companyId: map['company_id']?.toString() ?? '',
      companyName: map['company_name']?.toString(),
    );
  }
}