// lib/features/manager/bulk_import_screen.dart
//
// Employee bulk import via CSV. Shift import is intentionally NOT
// included here yet — that half needs shift_service.dart's actual
// create-shift logic (subscription gating, conflict checks) rather
// than a raw insert that could silently skip it. Employee import is
// fully self-contained: it reuses InviteService.inviteUser for every
// row, so nothing here bypasses existing validation/subscription
// logic.

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/invite_service.dart';
import '../../core/services/csv_import_service.dart';

class BulkImportScreen extends StatefulWidget {
  const BulkImportScreen({super.key});

  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen> {
  List<EmployeeImportRow> rows = [];
  bool importing = false;

  // Set after import: rowNumber -> result message. Only populated
  // once "Import" has actually run.
  final Map<int, String> importResults = {};

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
    final parsed = CsvImportService.parseEmployeeCsv(content);

    setState(() {
      rows = parsed;
      importResults.clear();
    });
  }

  Future<void> _import() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) return;

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
        await InviteService.inviteUser(
          email: row.email,
          companyId: companyId,
          role: row.role,
          hourlyRate: row.hourlyRate,
        );
        importResults[row.rowNumber] = "Invited";
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
      appBar: AppBar(title: const Text("Bulk Import Employees")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              "CSV needs an \"email\" column. Optional columns: "
              "\"role\" (employee/manager/admin, defaults to employee) "
              "and \"hourly_rate\". Each valid row sends a normal "
              "invite — same as inviting one at a time.",
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
                color: invalidCount > 0 ? Colors.orange[800] : Colors.green[800],
              ),
            ),
            const SizedBox(height: 8),
            ...rows.map((r) {
              final resultMsg = importResults[r.rowNumber];
              final failed = resultMsg != null && resultMsg.startsWith("Failed");

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
                  r.email.isEmpty ? "(row ${r.rowNumber})" : r.email,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  resultMsg ??
                      r.error ??
                      "${r.role}${r.hourlyRate != null ? ' • \$${r.hourlyRate!.toStringAsFixed(2)}/hr' : ''}",
                  style: const TextStyle(fontSize: 11),
                ),
              );
            }),

            if (!hasResults) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (importing || validCount == 0) ? null : _import,
                  child: Text(importing
                      ? "Importing..."
                      : "Import $validCount Employee${validCount == 1 ? '' : 's'}"),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}