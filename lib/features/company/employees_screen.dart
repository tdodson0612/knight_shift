// lib/features/company/employees_screen.dart

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/employee_service.dart';
import '../../shared/models/employee_profile.dart';
import '../employees/employee_profile_screen.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  bool loading = true;
  List<EmployeeProfile> employees = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final companyId = SessionService.activeCompanyId;

    if (companyId == null) {
      setState(() {
        employees = [];
        loading = false;
      });
      return;
    }

    setState(() => loading = true);

    try {
      final data = await EmployeeService.getCompanyEmployees(companyId);
      employees = data;
    } catch (_) {
      employees = [];
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  void _openProfile(EmployeeProfile employee) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeProfileScreen(employee: employee),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Employees"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: "Refresh",
            onPressed: load,
          )
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : employees.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.people_outline, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          "No employees found",
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: employees.length,
                  itemBuilder: (context, index) {
                    final e = employees[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal.shade50,
                          child: Text(
                            e.initials,
                            style: TextStyle(
                              color: Colors.teal.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        title: Text(
                          e.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          e.role,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                        trailing: Text(
                          e.email.isEmpty ? "—" : e.email,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                        onTap: () => _openProfile(e),
                      ),
                    );
                  },
                ),
    );
  }
}