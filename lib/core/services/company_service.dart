// lib/core/services/company_service.dart
//
// Creating a company is one server step (the `create_company` database
// function): it creates the company and makes the caller its manager
// together, so a half-created company can never be left behind.

import 'supabase_service.dart';

class CreatedCompany {
  final String companyId;
  final String companyName;
  final String role;

  const CreatedCompany({
    required this.companyId,
    required this.companyName,
    required this.role,
  });

  factory CreatedCompany.fromMap(Map<String, dynamic> map) {
    return CreatedCompany(
      companyId: map['company_id'].toString(),
      companyName: map['company_name']?.toString() ?? 'Company',
      role: map['role']?.toString() ?? 'manager',
    );
  }
}

class CompanyService {
  static Future<CreatedCompany> createCompany(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Enter a company name');
    }

    final res = await SupabaseService.client.rpc(
      'create_company',
      params: {'p_name': trimmed},
    );

    return CreatedCompany.fromMap(Map<String, dynamic>.from(res as Map));
  }
}
