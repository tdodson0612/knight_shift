// lib/features/manager/bulk_import_hub_screen.dart

import 'package:flutter/material.dart';

import 'bulk_import_screen.dart';
import 'bulk_import_shifts_screen.dart';

class BulkImportHubScreen extends StatelessWidget {
  const BulkImportHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Bulk Import")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.people_outline, size: 24),
              title: const Text(
                "Import Employees",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text("From a CSV of email, role, hourly_rate"),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BulkImportScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined, size: 24),
              title: const Text(
                "Import Shifts",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                "From a CSV of employee_email, start_time, end_time",
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const BulkImportShiftsScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}