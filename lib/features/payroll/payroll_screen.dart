// lib/features/payroll/payroll_screen.dart

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/shift_service.dart';
import '../../core/services/employee_service.dart';
import '../../core/services/payroll_service.dart';
import '../../core/services/payroll_analytics_service.dart';
import '../../core/services/overtime_service.dart';
import '../../core/services/export_service.dart';

import '../../shared/models/shift_model.dart';
import '../../shared/models/employee_profile.dart';
import '../../shared/models/overtime_settings_model.dart';

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  bool loading = true;
  bool generating = false;
  bool exporting = false;

  List<ShiftModel> shifts = [];
  List<EmployeeProfile> employees = [];

  OvertimeSettings overtimeSettings = OvertimeSettings.defaults;

  // Populated either way, for display purposes — the flat hours
  // total per user, regardless of whether overtime is enabled.
  final Map<String, double> hoursByUser = {};

  // Only populated when overtimeSettings.anyThresholdEnabled — the
  // per-user regular/overtime split used both for display and for
  // payroll generation.
  final Map<String, OvertimeBreakdown> breakdownByUser = {};

  final Map<String, double> hourlyRates = {}; // sourced from EmployeeProfile.hourlyRate

  DateTime start = DateTime.now().subtract(const Duration(days: 7));
  DateTime end = DateTime.now();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) return;

    setState(() => loading = true);

    try {
      final results = await Future.wait([
        ShiftService.getCompanyShifts(companyId),
        EmployeeService.getCompanyEmployees(companyId),
        OvertimeService.getSettings(companyId),
      ]);

      shifts = results[0] as List<ShiftModel>;
      employees = results[1] as List<EmployeeProfile>;
      overtimeSettings = results[2] as OvertimeSettings;

      final filtered = shifts.where((s) {
        final t = s.startTime;
        return (t.isAfter(start) || t.isAtSameMomentAs(start)) &&
               (t.isBefore(end) || t.isAtSameMomentAs(end));
      }).toList();

      hourlyRates.clear();
      for (final e in employees) {
        hourlyRates[e.userId] = e.hourlyRate;
      }

      hoursByUser.clear();
      breakdownByUser.clear();

      if (overtimeSettings.anyThresholdEnabled) {
        final daily = await PayrollAnalyticsService.calculateDailyHoursByUser(
          companyId: companyId,
          shifts: filtered,
          start: start,
          end: end,
        );

        for (final entry in daily.entries) {
          final userId = entry.key;
          final rate = hourlyRates[userId] ?? 20.0;

          final breakdown = OvertimeService.splitHours(
            dailyHours: entry.value,
            hourlyRate: rate,
            settings: overtimeSettings,
          );

          breakdownByUser[userId] = breakdown;
          hoursByUser[userId] = breakdown.totalHours;
        }
      } else {
        final hours = await PayrollAnalyticsService.calculateHoursByUser(
          companyId: companyId,
          shifts: filtered,
          start: start,
          end: end,
        );

        hoursByUser
          ..clear()
          ..addAll(hours);
      }

      setState(() => loading = false);
    } catch (_) {
      setState(() => loading = false);
    }
  }

  Future<void> generatePayroll() async {
    final companyId = SessionService.activeCompanyId;
    final userId = SessionService.activeUserId;

    if (companyId == null || userId == null) return;

    setState(() => generating = true);

    try {
      final runId = await PayrollService.createPayrollRun(
        companyId: companyId,
        start: start,
        end: end,
        createdBy: userId,
      );

      if (overtimeSettings.anyThresholdEnabled) {
        await PayrollService.addEntriesWithOvertime(
          payrollRunId: runId,
          breakdownByUser: breakdownByUser,
          hourlyRateByUser: hourlyRates,
        );
      } else {
        final entries = hoursByUser.entries.map((e) {
          return {
            'userId': e.key,
            'hours': e.value,
            'rate': hourlyRates[e.key] ?? 20.0,
          };
        }).toList();

        await PayrollService.addEntries(
          payrollRunId: runId,
          entries: entries,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Payroll generated")),
      );
    } catch (e) {
      // Catches subscription-lock and any other service exception —
      // e.g. "Payroll generation is disabled — your trial has ended."
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => generating = false);
      }
    }
  }

  // ----------------------------
  // EXPORT (CSV, local file only — no sharing yet)
  // NOTE: does not yet include the overtime breakdown columns even
  // when overtime is enabled — ExportService's row shape wasn't
  // touched as part of this change. Flag if you want that added.
  // ----------------------------
  Future<void> exportPayroll() async {
    if (hoursByUser.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nothing to export")),
      );
      return;
    }

    setState(() => exporting = true);

    try {
      final rows = hoursByUser.entries.map((e) {
        final rate = hourlyRates[e.key] ?? 20.0;
        final hours = e.value;
        final total = breakdownByUser[e.key]?.totalPay ?? (hours * rate);

        return {
          'name': name(e.key),
          'hours': hours,
          'rate': rate,
          'total': total,
        };
      }).toList();

      await ExportService.exportPayrollCSV(rows);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Payroll exported successfully")),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Export failed")),
      );
    } finally {
      if (mounted) {
        setState(() => exporting = false);
      }
    }
  }

  String name(String userId) {
    return employees
        .firstWhere(
          (e) => e.userId == userId,
          orElse: () => EmployeeProfile(
            userId: userId,
            companyId: '',
            displayName: 'Unknown',
            email: '',
            role: 'employee',
          ),
        )
        .displayName;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Payroll"),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: () async {},
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: exporting ? null : exportPayroll,
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: generating ? null : generatePayroll,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  "Period: ${start.toLocal()} → ${end.toLocal()}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (overtimeSettings.anyThresholdEnabled) ...[
                  const SizedBox(height: 8),
                  _overtimeModeChip(),
                ],
                const SizedBox(height: 20),
                ...hoursByUser.entries.map((e) {
                  final breakdown = breakdownByUser[e.key];

                  if (breakdown == null) {
                    // No overtime thresholds enabled — original,
                    // simple display.
                    final rate = hourlyRates[e.key] ?? 20.0;
                    final pay = e.value * rate;

                    return ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(name(e.key)),
                      subtitle:
                          Text("${e.value.toStringAsFixed(2)} hrs × \$$rate"),
                      trailing: Text("\$${pay.toStringAsFixed(2)}"),
                    );
                  }

                  final hasOT = breakdown.overtimeHours > 0;

                  return ListTile(
                    leading: Icon(
                      Icons.person,
                      color: hasOT ? Colors.orange : null,
                    ),
                    title: Text(name(e.key)),
                    subtitle: Text(
                      hasOT
                          ? "${breakdown.regularHours.toStringAsFixed(2)} reg + "
                              "${breakdown.overtimeHours.toStringAsFixed(2)} OT hrs"
                          : "${breakdown.totalHours.toStringAsFixed(2)} hrs",
                    ),
                    trailing: Text(
                      "\$${breakdown.totalPay.toStringAsFixed(2)}",
                      style: TextStyle(
                        color: hasOT ? Colors.orange[800] : null,
                        fontWeight: hasOT ? FontWeight.bold : null,
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _overtimeModeChip() {
    final label = overtimeSettings.calculatesPay
        ? "Overtime pay enabled (${overtimeSettings.multiplier}×)"
        : "Overtime hours tracked (straight pay)";

    return Chip(
      avatar: const Icon(Icons.schedule, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: Colors.orange.withValues(alpha: 0.12),
      visualDensity: VisualDensity.compact,
    );
  }
}