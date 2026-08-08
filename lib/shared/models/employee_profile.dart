// lib/shared/models/employee_profile.dart

class EmployeeProfile {
  final String userId;
  final String displayName;
  final String role;
  final String email;
  final String companyId;
  final double hourlyRate;

  /// Employee's actual hire date at the company (manager-set). Used
  /// as the seniority signal for seniority-first open-shift claiming.
  /// Null until a manager sets it.
  final DateTime? hireDate;

  EmployeeProfile({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.email,
    required this.companyId,
    this.hourlyRate = 20,
    this.hireDate,
  });

  factory EmployeeProfile.fromMap(Map<String, dynamic> map) {
    return EmployeeProfile(
      userId: map['user_id'] ?? '',
      displayName: map['display_name'] ?? '',
      role: map['role'] ?? 'employee',
      email: map['email'] ?? '',
      companyId: map['company_id'] ?? '',
      hourlyRate: (map['hourly_rate'] ?? 20).toDouble(),
      hireDate: map['hire_date'] == null
          ? null
          : DateTime.tryParse(map['hire_date'].toString()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'display_name': displayName,
      'role': role,
      'email': email,
      'company_id': companyId,
      'hourly_rate': hourlyRate,
      'hire_date': hireDate?.toIso8601String().split('T').first,
    };
  }

  String get initials {
    final name = displayName.trim();
    if (name.isEmpty) return '?';

    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get safeDisplayName {
    if (displayName.trim().isNotEmpty) return displayName;
    if (email.trim().isNotEmpty) return email;
    return 'Unknown User';
  }

  bool get isManager => role.toLowerCase() == 'manager';
  bool get isEmployee => role.toLowerCase() == 'employee';
}