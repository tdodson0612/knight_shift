// lib/core/services/csv_import_service.dart
//
// Pure CSV parsing + row-level validation for bulk employee import.
// Does NOT talk to Supabase directly — actual writes go through
// InviteService.inviteUser, reusing its existing validation,
// duplicate-check, and subscription-lock logic rather than
// duplicating it here.
//
// Expected CSV headers (case-insensitive, order doesn't matter):
//   email        (required)
//   role         (optional, defaults to 'employee')
//   hourly_rate  (optional)

import 'package:csv/csv.dart';

class EmployeeImportRow {
  final int rowNumber; // 1-based, for user-facing error messages
  final String email;
  final String role;
  final double? hourlyRate;
  final String? error; // null = valid

  const EmployeeImportRow({
    required this.rowNumber,
    required this.email,
    required this.role,
    this.hourlyRate,
    this.error,
  });

  bool get isValid => error == null;
}

class ShiftImportRow {
  final int rowNumber;
  final String employeeEmail;
  final String? resolvedUserId; // null if email didn't match an employee
  final DateTime? start;
  final DateTime? end;
  final String? error;

  const ShiftImportRow({
    required this.rowNumber,
    required this.employeeEmail,
    this.resolvedUserId,
    this.start,
    this.end,
    this.error,
  });

  bool get isValid => error == null;
}

class CsvImportService {
  static List<EmployeeImportRow> parseEmployeeCsv(String csvContent) {
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(csvContent.replaceAll('\r\n', '\n'));

    if (rows.isEmpty) return [];

    final header =
        rows.first.map((h) => h.toString().trim().toLowerCase()).toList();

    final emailIdx = header.indexOf('email');
    final roleIdx = header.indexOf('role');
    final rateIdx = header.indexOf('hourly_rate');

    if (emailIdx == -1) {
      return [
        const EmployeeImportRow(
          rowNumber: 1,
          email: '',
          role: '',
          error: 'CSV must have an "email" column header',
        ),
      ];
    }

    final result = <EmployeeImportRow>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length == 1 && row.first.toString().trim().isEmpty) {
        continue; // skip blank trailing lines
      }

      final rowNumber = i + 1; // 1-based, including header line

      final email = emailIdx < row.length
          ? row[emailIdx].toString().trim()
          : '';
      final roleRaw = (roleIdx != -1 && roleIdx < row.length)
          ? row[roleIdx].toString().trim().toLowerCase()
          : '';
      final role = roleRaw.isEmpty ? 'employee' : roleRaw;
      final rateRaw = (rateIdx != -1 && rateIdx < row.length)
          ? row[rateIdx].toString().trim()
          : '';

      String? error;
      double? hourlyRate;

      if (email.isEmpty) {
        error = 'Missing email';
      } else if (!email.contains('@') || !email.contains('.')) {
        error = 'Doesn\'t look like a valid email';
      } else if (!['employee', 'manager', 'admin', 'accountant'].contains(role)) {
        error = 'Unknown role "$role" (expected employee, manager, admin, or accountant)';
      } else if (rateRaw.isNotEmpty) {
        hourlyRate = double.tryParse(rateRaw);
        if (hourlyRate == null || hourlyRate < 0) {
          error = 'Invalid hourly_rate "$rateRaw"';
        }
      }

      result.add(EmployeeImportRow(
        rowNumber: rowNumber,
        email: email,
        role: role,
        hourlyRate: hourlyRate,
        error: error,
      ));
    }

    return result;
  }

  /// employeeEmailToUserId should be built from the company's CURRENT
  /// employees (lowercase email -> userId) before calling this — a
  /// row for an email that isn't an existing employee is reported as
  /// an error rather than silently skipped or guessed at.
  ///
  /// Expected CSV headers: employee_email, start_time, end_time.
  /// Date/time values must parse as ISO 8601
  /// (e.g. "2026-08-15T09:00" or "2026-08-15 09:00:00").
  static List<ShiftImportRow> parseShiftCsv(
    String csvContent,
    Map<String, String> employeeEmailToUserId,
  ) {
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(csvContent.replaceAll('\r\n', '\n'));

    if (rows.isEmpty) return [];

    final header =
        rows.first.map((h) => h.toString().trim().toLowerCase()).toList();

    final emailIdx = header.indexOf('employee_email');
    final startIdx = header.indexOf('start_time');
    final endIdx = header.indexOf('end_time');

    if (emailIdx == -1 || startIdx == -1 || endIdx == -1) {
      return [
        const ShiftImportRow(
          rowNumber: 1,
          employeeEmail: '',
          error:
              'CSV must have employee_email, start_time, and end_time columns',
        ),
      ];
    }

    final result = <ShiftImportRow>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length == 1 && row.first.toString().trim().isEmpty) continue;

      final rowNumber = i + 1;
      final email = row[emailIdx].toString().trim();
      final startRaw = startIdx < row.length ? row[startIdx].toString().trim() : '';
      final endRaw = endIdx < row.length ? row[endIdx].toString().trim() : '';

      String? error;
      String? resolvedUserId;
      DateTime? start;
      DateTime? end;

      if (email.isEmpty) {
        error = 'Missing employee_email';
      } else {
        resolvedUserId = employeeEmailToUserId[email.toLowerCase()];
        if (resolvedUserId == null) {
          error = 'No employee found with this email — invite them first';
        }
      }

      if (error == null) {
        start = DateTime.tryParse(startRaw);
        end = DateTime.tryParse(endRaw);

        if (start == null) {
          error = 'Invalid start_time "$startRaw"';
        } else if (end == null) {
          error = 'Invalid end_time "$endRaw"';
        } else if (!end.isAfter(start)) {
          error = 'end_time must be after start_time';
        }
      }

      result.add(ShiftImportRow(
        rowNumber: rowNumber,
        employeeEmail: email,
        resolvedUserId: resolvedUserId,
        start: start,
        end: end,
        error: error,
      ));
    }

    return result;
  }
}