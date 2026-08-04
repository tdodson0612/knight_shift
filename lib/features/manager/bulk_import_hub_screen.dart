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
              leading: const Icon(Icons.people_outline),
              title: const Text("Import Employees"),
              subtitle: const Text("From a CSV of email, role, hourly_rate"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BulkImportScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text("Import Shifts"),
              subtitle: const Text(
                "From a CSV of employee_email, start_time, end_time",
              ),
              trailing: const Icon(Icons.chevron_right),
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