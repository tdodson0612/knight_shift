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
            onPressed: load,
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : employees.isEmpty
              ? const Center(
                  child: Text("No employees found"),
                )
              : ListView.builder(
                  itemCount: employees.length,
                  itemBuilder: (context, index) {
                    final e = employees[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(e.initials),
                      ),
                      title: Text(e.displayName),
                      subtitle: Text(e.role),
                      trailing: Text(
                        e.email.isEmpty ? "—" : e.email,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () => _openProfile(e),
                    );
                  },
                ),
    );
  }
}