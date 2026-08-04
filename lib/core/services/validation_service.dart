// lib/core/services/validation_service.dart

class ValidationService {
  static String? validateEmail(String email) {
    final value = email.trim();

    if (value.isEmpty) return "Email is required";

    final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!regex.hasMatch(value)) return "Invalid email format";

    return null;
  }

  static String? validateRole(String role) {
    // 'accountant' added: read-only bookkeeper seat, scoped to
    // payroll viewing only. Deliberately excluded from
    // RoleService.isManager() — see that file's comment.
    const allowed = ['employee', 'manager', 'admin', 'accountant'];

    if (!allowed.contains(role)) {
      return "Invalid role";
    }

    return null;
  }

  static String? validateCompanyId(String? companyId) {
    if (companyId == null || companyId.isEmpty) {
      return "Missing company context";
    }
    return null;
  }

  static String? validateUserId(String? userId) {
    if (userId == null || userId.isEmpty) {
      return "Missing user context";
    }
    return null;
  }

  static String? validateShiftTime(DateTime start, DateTime end) {
    if (end.isBefore(start)) {
      return "Shift end must be after start";
    }

    final duration = end.difference(start).inHours;
    if (duration <= 0) {
      return "Invalid shift duration";
    }

    if (duration > 24) {
      return "Shift too long";
    }

    return null;
  }
}