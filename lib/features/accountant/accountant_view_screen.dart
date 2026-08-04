// lib/features/accountant/accountant_view_screen.dart
//
// Landing screen for the read-only accountant/bookkeeper role.
// Deliberately narrower than ReportsScreen — payroll history and
// basic labor hour totals only. Team Insights and Reliability data
// (approval rates, late/no-show counts on named employees) are NOT
// shown here; that's individual behavioral data an outside
// bookkeeper has no reason to see, even though the underlying tables
// happen to be readable to any company member. Scope is enforced by
// what this screen chooses to query, not by RLS alone.

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/employee_service.dart';
import '../../core/services/shift_service.dart';
import '../../core/services/shift_analytics_service.dart';
import '../../core/services/payroll_service.dart';
import '../settings/settings_screen.dart';

import '../../shared/models/employee_profile.dart';
import '../../shared/models/shift_model.dart';
import '../../shared/models/payroll_model.dart';

class AccountantViewScreen extends StatefulWidget {
  const AccountantViewScreen({super.key});

  @override
  State<AccountantViewScreen> createState() => _AccountantViewScreenState();
}

class _AccountantViewScreenState extends State<AccountantViewScreen> {
  bool loading = true;
  String? error;

  List<EmployeeProfile> employees = [];
  List<ShiftModel> shifts = [];
  List<PayrollRun> payrollRuns = [];
  final Map<String, List<PayrollSummary>> entriesByRun = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) {
      setState(() {
        loading = false;
        error = "No company selected";
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final results = await Future.wait([
        EmployeeService.getCompanyEmployees(companyId),
        ShiftService.getCompanyShifts(companyId),
        PayrollService.getPayrollRuns(companyId),
      ]);

      employees = results[0] as List<EmployeeProfile>;
      shifts = results[1] as List<ShiftModel>;
      payrollRuns = results[2] as List<PayrollRun>;

      entriesByRun.clear();
      for (final run in payrollRuns) {
        entriesByRun[run.id] = await PayrollService.getPayrollEntries(run.id);
      }

      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = "Failed to load: $e";
      });
    }
  }

  String _nameFor(String userId) {
    final match = employees.where((e) => e.userId == userId);
    return match.isEmpty ? "Unknown" : match.first.displayName;
  }

  String _formatDate(DateTime d) => "${d.month}/${d.day}/${d.year}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(SessionService.activeCompanyName ?? "Payroll"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: "Settings",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _laborSection(),
                    const SizedBox(height: 32),
                    _payrollSection(),
                  ],
                ),
    );
  }

  Widget _laborSection() {
    final totalHours = ShiftAnalyticsService.totalHours(shifts);
    final byUser = ShiftAnalyticsService.calculateHoursByUser(shifts);
    final sorted = byUser.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _section(
      title: "Labor Hours",
      children: [
        _statRow("Total Hours (all history)", totalHours.toStringAsFixed(1)),
        const SizedBox(height: 12),
        if (sorted.isEmpty)
          _emptyLine("No shifts recorded")
        else
          ...sorted.map(
            (e) => _kvRow(_nameFor(e.key), "${e.value.toStringAsFixed(1)} hrs"),
          ),
      ],
    );
  }

  Widget _payrollSection() {
    double grossPayroll = 0;
    final Map<String, double> payByUser = {};

    for (final run in payrollRuns) {
      final entries = entriesByRun[run.id] ?? [];
      for (final entry in entries) {
        grossPayroll += entry.totalPay;
        payByUser[entry.userId] = (payByUser[entry.userId] ?? 0) + entry.totalPay;
      }
    }

    final sortedPayByUser = payByUser.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _section(
      title: "Payroll",
      children: [
        _statRow("Gross Payroll (all history)",
            "\$${grossPayroll.toStringAsFixed(2)}"),
        const SizedBox(height: 12),
        const Text("By Employee",
            style: TextStyle(fontWeight: FontWeight.w600)),
        if (sortedPayByUser.isEmpty)
          _emptyLine("No payroll history")
        else
          ...sortedPayByUser.map(
            (e) => _kvRow(_nameFor(e.key), "\$${e.value.toStringAsFixed(2)}"),
          ),
        const SizedBox(height: 12),
        const Text("By Pay Period",
            style: TextStyle(fontWeight: FontWeight.w600)),
        if (payrollRuns.isEmpty)
          _emptyLine("No payroll runs yet")
        else
          ...payrollRuns.map((run) {
            final entries = entriesByRun[run.id] ?? [];
            final periodTotal =
                entries.fold<double>(0, (sum, e) => sum + e.totalPay);
            return _kvRow(
              "${_formatDate(run.periodStart)} → ${_formatDate(run.periodEnd)}  •  ${run.status}",
              "\$${periodTotal.toStringAsFixed(2)}",
            );
          }),
      ],
    );
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 15)),
        Text(value,
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _kvRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          Text(value),
        ],
      ),
    );
  }

  Widget _emptyLine(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text, style: const TextStyle(color: Colors.grey, fontSize: 13)),
    );
  }
}