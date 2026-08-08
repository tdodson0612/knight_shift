// lib/shared/models/employee_skill_model.dart

/// A company-wide skill tag (e.g. "bartender", "certified forklift"),
/// manager-managed. Shifts can optionally note a required skill.
/// Advisory only — a manager assigning someone without the required
/// tag gets a warning, never a block.
class EmployeeSkill {
  final String id;
  final String companyId;
  final String label;
  final DateTime createdAt;

  const EmployeeSkill({
    required this.id,
    required this.companyId,
    required this.label,
    required this.createdAt,
  });

  factory EmployeeSkill.fromMap(Map<String, dynamic> map) {
    return EmployeeSkill(
      id: map['id']?.toString() ?? '',
      companyId: map['company_id']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// Which employees have which skill.
class EmployeeSkillAssignment {
  final String id;
  final String companyId;
  final String userId;
  final String skillId;
  final DateTime createdAt;

  const EmployeeSkillAssignment({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.skillId,
    required this.createdAt,
  });

  factory EmployeeSkillAssignment.fromMap(Map<String, dynamic> map) {
    return EmployeeSkillAssignment(
      id: map['id']?.toString() ?? '',
      companyId: map['company_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      skillId: map['skill_id']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}