// lib/features/manager/company_portfolio_screen.dart
//
// Roll-up view for a user who manages multiple Knight Shift
// companies. Opt-in via a dashboard icon, NOT a change to default
// routing — CompanyGate still always lands on the single
// last-active company, same as before. This is purely additive.

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/employee_service.dart';
import '../../core/services/subscription_service.dart';
import '../../core/services/shift_service.dart';
import '../../core/services/payroll_analytics_service.dart';
import '../../shared/models/subscription_model.dart';
import 'manager_dashboard.dart';

class _CompanySummary {
  final String companyId;
  final String companyName;
  final String role;
  int employeeCount = 0;
  double hoursThisWeek = 0;
  CompanySubscription? subscription;
  String? loadError;

  _CompanySummary({
    required this.companyId,
    required this.companyName,
    required this.role,
  });
}

class CompanyPortfolioScreen extends StatefulWidget {
  const CompanyPortfolioScreen({super.key});

  @override
  State<CompanyPortfolioScreen> createState() =>
      _CompanyPortfolioScreenState();
}

class _CompanyPortfolioScreenState extends State<CompanyPortfolioScreen> {
  bool loading = true;
  List<_CompanySummary> companies = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);

    try {
      final rows = await SessionService.getMyCompanies();

      final managed = rows.where((r) {
        final role = r['role']?.toString();
        return role == 'manager' || role == 'admin';
      }).toList();

      final summaries = managed.map((r) {
        final companyId = r['company_id']?.toString() ?? '';
        final companyName =
            (r['companies'] as Map?)?['name']?.toString() ?? 'Company';
        final role = r['role']?.toString() ?? 'manager';
        return _CompanySummary(
          companyId: companyId,
          companyName: companyName,
          role: role,
        );
      }).toList();

      await Future.wait(summaries.map(_loadDetails));

      if (!mounted) return;
      setState(() {
        companies = summaries;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  Future<void> _loadDetails(_CompanySummary s) async {
    try {
      final employees = await EmployeeService.getCompanyEmployees(s.companyId);
      s.employeeCount = employees.length;

      final now = DateTime.now();
      final weekStart = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - DateTime.monday));

      final shifts = await ShiftService.getCompanyShifts(s.companyId);
      final weekShifts = shifts
          .where((sh) =>
              sh.startTime.isAfter(weekStart) ||
              sh.startTime.isAtSameMomentAs(weekStart))
          .toList();

      final hours = await PayrollAnalyticsService.calculateHoursByUser(
        companyId: s.companyId,
        shifts: weekShifts,
        start: weekStart,
        end: now,
      );
      s.hoursThisWeek = hours.values.fold(0.0, (a, b) => a + b);

      s.subscription = await SubscriptionService.getSubscription(s.companyId);
    } catch (e) {
      s.loadError = "$e";
    }
  }

  Future<void> _switchTo(_CompanySummary s) async {
    final userId = SessionService.activeUserId;
    if (userId == null) return;

    await SessionService.setActiveCompany(
      companyId: s.companyId,
      companyName: s.companyName,
      role: s.role,
      userId: userId,
    );

    if (!mounted) return;

    // Fresh ManagerDashboard, old stack cleared — switching
    // companies resets context the same way accepting an invite
    // does elsewhere in this app.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const ManagerDashboard()),
      (route) => false,
    );
  }

  String _statusLabel(CompanySubscription? s) {
    if (s == null) return "Unknown";
    if (s.isLocked) return "Locked";
    if (s.isTrialing) return "Trial";
    if (s.isActive) return "Active";
    return s.status;
  }

  Color _statusColor(CompanySubscription? s) {
    if (s == null) return Colors.grey;
    if (s.isLocked) return Colors.red;
    if (s.isTrialing) return Colors.orange;
    if (s.isActive) return Colors.green;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Companies"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: "Refresh",
            onPressed: _load,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : companies.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "You don't manage any companies yet",
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: companies.length,
                  itemBuilder: (context, index) {
                    final s = companies[index];
                    final isCurrent =
                        s.companyId == SessionService.activeCompanyId;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isCurrent
                            ? const BorderSide(color: Colors.blue, width: 2)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        onTap: isCurrent ? null : () => _switchTo(s),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.companyName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (isCurrent)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "Current",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: s.loadError != null
                            ? Text(
                                "Couldn't load details",
                                style: TextStyle(
                                    color: Colors.red[300], fontSize: 12),
                              )
                            : Text(
                                "${s.employeeCount} employees  •  ${s.hoursThisWeek.toStringAsFixed(1)} hrs this week",
                                style: const TextStyle(fontSize: 12),
                              ),
                        trailing: Chip(
                          label: Text(_statusLabel(s.subscription),
                              style: const TextStyle(fontSize: 11)),
                          backgroundColor:
                              _statusColor(s.subscription).withValues(alpha: 0.15),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}