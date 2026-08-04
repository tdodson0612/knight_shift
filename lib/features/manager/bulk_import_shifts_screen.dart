// lib/features/manager/bulk_import_shifts_screen.dart
//
// Shift bulk import. Every valid row goes through
// ShiftService.createShift — NOT a raw insert — so subscription
// gating, time validation, and conflict checking all still apply
// exactly as they do for a shift created one at a time.

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/employee_service.dart';
import '../../core/services/shift_service.dart';
import '../../core/services/csv_import_service.dart';

class BulkImportShiftsScreen extends StatefulWidget {
  const BulkImportShiftsScreen({super.key});

  @override
  State<BulkImportShiftsScreen> createState() =>
      _BulkImportShiftsScreenState();
}

class _BulkImportShiftsScreenState extends State<BulkImportShiftsScreen> {
  bool loadingEmployees = true;
  Map<String, String> emailToUserId = {}; // lowercase email -> userId

  List<ShiftImportRow> rows = [];
  bool importing = false;
  final Map<int, String> importResults = {};

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) {
      setState(() => loadingEmployees = false);
      return;
    }

    try {
      final employees = await EmployeeService.getCompanyEmployees(companyId);
      emailToUserId = {
        for (final e in employees)
          if (e.email.isNotEmpty) e.email.toLowerCase(): e.userId,
      };
    } catch (_) {
      emailToUserId = {};
    }

    if (mounted) setState(() => loadingEmployees = false);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    if (bytes == null) {
      _error("Couldn't read that file");
      return;
    }

    final content = utf8.decode(bytes);
    final parsed = CsvImportService.parseShiftCsv(content, emailToUserId);

    setState(() {
      rows = parsed;
      importResults.clear();
    });
  }

  Future<void> _import() async {
    final companyId = SessionService.activeCompanyId;
    final managerId = SessionService.activeUserId;
    if (companyId == null || managerId == null) return;

    final validRows = rows.where((r) => r.isValid).toList();
    if (validRows.isEmpty) {
      _error("No valid rows to import");
      return;
    }

    setState(() {
      importing = true;
      importResults.clear();
    });

    for (final row in validRows) {
      try {
        await ShiftService.createShift(
          companyId: companyId,
          userId: row.resolvedUserId,
          start: row.start!,
          end: row.end!,
          createdBy: managerId,
          status: 'approved',
          origin: 'manager_scheduled',
        );
        importResults[row.rowNumber] = "Created";
      } catch (e) {
        importResults[row.rowNumber] = "Failed: $e";
      }
    }

    if (mounted) setState(() => importing = false);
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validCount = rows.where((r) => r.isValid).length;
    final invalidCount = rows.length - validCount;
    final hasResults = importResults.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text("Bulk Import Shifts")),
      body: loadingEmployees
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    "CSV needs employee_email, start_time, end_time "
                    "columns. Dates must be like \"2026-08-15T09:00\". "
                    "The employee must already exist in this company — "
                    "invite them first if they're new. Each row goes "
                    "through the same checks as creating a shift by "
                    "hand (conflicts, trial status, etc.).",
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: importing ? null : _pickFile,
                  icon: const Icon(Icons.upload_file),
                  label: const Text("Choose CSV File"),
                ),

                if (rows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    "$validCount valid, $invalidCount with errors",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: invalidCount > 0
                          ? Colors.orange[800]
                          : Colors.green[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...rows.map((r) {
                    final resultMsg = importResults[r.rowNumber];
                    final failed =
                        resultMsg != null && resultMsg.startsWith("Failed");

                    return ListTile(
                      dense: true,
                      leading: Icon(
                        !r.isValid || failed
                            ? Icons.error_outline
                            : resultMsg != null
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                        size: 18,
                        color: !r.isValid || failed
                            ? Colors.red
                            : resultMsg != null
                                ? Colors.green
                                : Colors.grey,
                      ),
                      title: Text(
                        r.employeeEmail.isEmpty
                            ? "(row ${r.rowNumber})"
                            : r.employeeEmail,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        resultMsg ??
                            r.error ??
                            "${r.start} → ${r.end}",
                        style: const TextStyle(fontSize: 11),
                      ),
                    );
                  }),

                  if (!hasResults) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            (importing || validCount == 0) ? null : _import,
                        child: Text(importing
                            ? "Importing..."
                            : "Import $validCount Shift${validCount == 1 ? '' : 's'}"),
                      ),
                    ),
                  ],
                ],
              ],
            ),
    );
  }
}