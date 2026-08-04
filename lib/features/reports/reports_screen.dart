// lib/features/reports/reports_screen.dart

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/shift_service.dart';
import '../../core/services/shift_analytics_service.dart';
import '../../core/services/employee_service.dart';
import '../../core/services/payroll_service.dart';
import '../../core/services/time_off_service.dart';
import '../../core/services/team_insights_service.dart';
import '../../core/services/reliability_service.dart';
import '../../core/services/forecasting_service.dart';

import '../../shared/models/shift_model.dart';
import '../../shared/models/employee_profile.dart';
import '../../shared/models/payroll_model.dart';
import '../../shared/models/time_off_model.dart';
import '../../shared/models/reliability_settings_model.dart';

/// Reports — manager-only.
///
/// Sections: Labor, Payroll, Team Insights, Reliability. Each is an
/// independent builder so future sections can be added without
/// restructuring. This screen is presentation-only — it never
/// queries Supabase directly, only through services.
///
/// Reliability is intentionally its OWN section, not folded into
/// Team Insights — TeamInsightsService's stated charter is "no
/// invented business rules, only direct counts/rates," and a
/// manager-configured weighted score doesn't fit that. Same pattern
/// as Payroll being its own section backed by PayrollService rather
/// than living inside Team Insights.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool loading = true;
  String? error;

  List<ShiftModel> shifts = [];
  List<EmployeeProfile> employees = [];
  List<PayrollRun> payrollRuns = [];
  List<TimeOffRequest> timeOffRequests = [];

  final Map<String, List<PayrollSummary>> entriesByRun = {};

  ReliabilitySettings? reliabilitySettings;
  Map<String, ReliabilityStats> reliabilityByUser = {};

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
        ShiftService.getCompanyShifts(companyId),
        EmployeeService.getCompanyEmployees(companyId),
        PayrollService.getPayrollRuns(companyId),
        TimeOffService.getCompanyTimeOff(companyId),
      ]);

      shifts = results[0] as List<ShiftModel>;
      employees = results[1] as List<EmployeeProfile>;
      payrollRuns = results[2] as List<PayrollRun>;
      timeOffRequests = results[3] as List<TimeOffRequest>;

      entriesByRun.clear();
      for (final run in payrollRuns) {
        entriesByRun[run.id] =
            await PayrollService.getPayrollEntries(run.id);
      }

      // Reliability — separate load, doesn't block the rest of the
      // screen if it fails (e.g. company predates the migration).
      try {
        final settings = await ReliabilityService.getSettings(companyId);
        reliabilitySettings = settings;

        if (settings.enabled && shifts.isNotEmpty) {
          final earliest = shifts
              .map((s) => s.startTime)
              .reduce((a, b) => a.isBefore(b) ? a : b);

          reliabilityByUser = await ReliabilityService.calculateStatsByUser(
            companyId: companyId,
            shifts: shifts,
            start: earliest,
            end: DateTime.now(),
            settings: settings,
          );
        } else {
          reliabilityByUser = {};
        }
      } catch (_) {
        reliabilitySettings = null;
        reliabilityByUser = {};
      }

      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = "Failed to load reports: $e";
      });
    }
  }

  String _nameFor(String? userId) {
    if (userId == null) return "Unassigned";
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
        title: const Text("Reports"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
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
                    const SizedBox(height: 32),
                    _teamInsightsSection(),
                    if (reliabilitySettings?.enabled == true) ...[
                      const SizedBox(height: 32),
                      _reliabilitySection(),
                    ],
                    const SizedBox(height: 32),
                    _forecastingSection(),
                  ],
                ),
    );
  }

  // ============================================================
  // LABOR SECTION
  // ============================================================
  Widget _laborSection() {
    final totalHours = ShiftAnalyticsService.totalHours(shifts);
    final byUser = ShiftAnalyticsService.calculateHoursByUser(shifts);
    final byWeek = ShiftAnalyticsService.calculateHoursByWeek(shifts);
    final byMonth = ShiftAnalyticsService.calculateHoursByMonth(shifts);

    final sortedUsers = byUser.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedWeeks = byWeek.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    final sortedMonths = byMonth.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return _section(
      title: "Labor",
      children: [
        _statRow("Total Hours", totalHours.toStringAsFixed(1)),
        const SizedBox(height: 12),
        _subheading("By Employee"),
        if (sortedUsers.isEmpty)
          _emptyLine("No shifts recorded")
        else
          ...sortedUsers.map(
            (e) => _kvRow(_nameFor(e.key), "${e.value.toStringAsFixed(1)} hrs"),
          ),
        const SizedBox(height: 12),
        _subheading("By Week (starting Monday)"),
        if (sortedWeeks.isEmpty)
          _emptyLine("No shifts recorded")
        else
          ...sortedWeeks.map(
            (e) => _kvRow(e.key, "${e.value.toStringAsFixed(1)} hrs"),
          ),
        const SizedBox(height: 12),
        _subheading("By Month"),
        if (sortedMonths.isEmpty)
          _emptyLine("No shifts recorded")
        else
          ...sortedMonths.map(
            (e) => _kvRow(e.key, "${e.value.toStringAsFixed(1)} hrs"),
          ),
      ],
    );
  }

  // ============================================================
  // PAYROLL SECTION
  // ============================================================
  Widget _payrollSection() {
    double grossPayroll = 0;
    final Map<String, double> payByUser = {};

    for (final run in payrollRuns) {
      final entries = entriesByRun[run.id] ?? [];
      for (final entry in entries) {
        grossPayroll += entry.totalPay;
        payByUser[entry.userId] =
            (payByUser[entry.userId] ?? 0) + entry.totalPay;
      }
    }

    final sortedPayByUser = payByUser.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _section(
      title: "Payroll",
      children: [
        _statRow("Gross Payroll (all history)", "\$${grossPayroll.toStringAsFixed(2)}"),
        const SizedBox(height: 12),
        _subheading("By Employee"),
        if (sortedPayByUser.isEmpty)
          _emptyLine("No payroll history")
        else
          ...sortedPayByUser.map(
            (e) => _kvRow(_nameFor(e.key), "\$${e.value.toStringAsFixed(2)}"),
          ),
        const SizedBox(height: 12),
        _subheading("By Pay Period"),
        if (payrollRuns.isEmpty)
          _emptyLine("No payroll runs yet")
        else
          ...payrollRuns.map((run) {
            final entries = entriesByRun[run.id] ?? [];
            final periodTotal =
                entries.fold<double>(0, (sum, e) => sum + e.totalPay);
            final label =
                "${_formatDate(run.periodStart)} → ${_formatDate(run.periodEnd)}";

            return _kvRow(
              "$label  •  ${run.status}",
              "\$${periodTotal.toStringAsFixed(2)}",
            );
          }),
      ],
    );
  }

  // ============================================================
  // TEAM INSIGHTS SECTION
  // ============================================================
  Widget _teamInsightsSection() {
    final shiftStats = TeamInsightsService.shiftRequestStats(shifts);
    final shiftStatsByUser = TeamInsightsService.shiftRequestStatsByUser(shifts);
    final fillStats = TeamInsightsService.openShiftFillStats(shifts);
    final fillRate = TeamInsightsService.openShiftFillRate(shifts);
    final swaps = TeamInsightsService.activeSwaps(shifts);
    final timeOffStats = TeamInsightsService.timeOffStats(timeOffRequests);
    final timeOffByUser =
        TeamInsightsService.timeOffStatsByUser(timeOffRequests);
    final shiftVolume =
        TeamInsightsService.shiftRequestVolumeByWeek(shifts);
    final timeOffVolume =
        TeamInsightsService.timeOffVolumeByWeek(timeOffRequests);

    final sortedShiftUsers = shiftStatsByUser.entries.toList()
      ..sort((a, b) => b.value.resolved.compareTo(a.value.resolved));
    final sortedTimeOffUsers = timeOffByUser.entries.toList()
      ..sort((a, b) => b.value.resolved.compareTo(a.value.resolved));
    final sortedShiftVolume = shiftVolume.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    final sortedTimeOffVolume = timeOffVolume.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return _section(
      title: "Team Insights",
      children: [
        const Text(
          "Based on activity since these features were added — earlier "
          "history isn't classifiable and is excluded rather than guessed.",
          style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 12),

        _subheading("Shift Requests"),
        _statRow(
          "Approval Rate",
          shiftStats.approvalRate != null
              ? "${(shiftStats.approvalRate! * 100).toStringAsFixed(0)}%"
              : "No data yet",
        ),
        _kvRow("Approved", shiftStats.approved.toString()),
        _kvRow("Rejected", shiftStats.rejected.toString()),
        _kvRow("Still Pending", shiftStats.pending.toString()),
        if (sortedShiftUsers.isNotEmpty) ...[
          const SizedBox(height: 8),
          _subheading("By Employee"),
          ...sortedShiftUsers.map((e) => _kvRow(
                _nameFor(e.key),
                e.value.approvalRate != null
                    ? "${(e.value.approvalRate! * 100).toStringAsFixed(0)}% approved (${e.value.resolved})"
                    : "${e.value.pending} pending",
              )),
        ],

        const SizedBox(height: 16),
        _subheading("Open Shifts"),
        _statRow(
          "Fill Rate",
          fillRate != null ? "${(fillRate * 100).toStringAsFixed(0)}%" : "No data yet",
        ),
        _kvRow("Filled", fillStats.filled.toString()),
        _kvRow("Still Open", fillStats.unfilled.toString()),

        const SizedBox(height: 16),
        _subheading("Active Swaps (right now)"),
        _kvRow("Awaiting Coworker Response", swaps.awaitingResponse.toString()),
        _kvRow("Awaiting Manager Approval", swaps.awaitingApproval.toString()),
        const Text(
          "Snapshot only — resolved swaps aren't retained as history.",
          style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
        ),

        const SizedBox(height: 16),
        _subheading("Time Off Requests"),
        _statRow(
          "Approval Rate",
          timeOffStats.approvalRate != null
              ? "${(timeOffStats.approvalRate! * 100).toStringAsFixed(0)}%"
              : "No data yet",
        ),
        _kvRow("Approved", timeOffStats.approved.toString()),
        _kvRow("Rejected", timeOffStats.rejected.toString()),
        _kvRow("Still Pending", timeOffStats.pending.toString()),
        if (sortedTimeOffUsers.isNotEmpty) ...[
          const SizedBox(height: 8),
          _subheading("By Employee"),
          ...sortedTimeOffUsers.map((e) => _kvRow(
                _nameFor(e.key),
                e.value.approvalRate != null
                    ? "${(e.value.approvalRate! * 100).toStringAsFixed(0)}% approved (${e.value.resolved})"
                    : "${e.value.pending} pending",
              )),
        ],

        const SizedBox(height: 16),
        _subheading("Shift Requests — Volume by Week"),
        if (sortedShiftVolume.isEmpty)
          _emptyLine("No data yet")
        else
          ...sortedShiftVolume.map((e) => _kvRow(e.key, "${e.value} requests")),

        const SizedBox(height: 12),
        _subheading("Time Off Requests — Volume by Week"),
        if (sortedTimeOffVolume.isEmpty)
          _emptyLine("No data yet")
        else
          ...sortedTimeOffVolume.map((e) => _kvRow(e.key, "${e.value} requests")),
      ],
    );
  }

  // ============================================================
  // RELIABILITY SECTION
  // ============================================================
  Widget _reliabilitySection() {
    final settings = reliabilitySettings;
    if (settings == null) return const SizedBox.shrink();

    final sorted = reliabilityByUser.entries.toList()
      ..sort((a, b) => a.value.score.compareTo(b.value.score)); // worst first

    final avgScore = reliabilityByUser.isEmpty
        ? null
        : reliabilityByUser.values.map((s) => s.score).reduce((a, b) => a + b) /
            reliabilityByUser.length;

    return _section(
      title: "Reliability",
      children: [
        Text(
          "Since the earliest shift on record. Scoring rules are set in "
          "Settings — ${settings.isWeighted ? 'weighted per infraction type' : 'flat points per infraction'}.",
          style: const TextStyle(
              fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 12),
        _statRow(
          "Average Score",
          avgScore != null ? avgScore.toStringAsFixed(0) : "No data yet",
        ),
        const SizedBox(height: 12),
        _subheading("By Employee"),
        if (sorted.isEmpty)
          _emptyLine("No completed shifts to evaluate yet")
        else
          ...sorted.map((e) {
            final s = e.value;
            final label = [
              if (settings.trackLate) "${s.lateCount} late",
              if (settings.trackEarlyLeave) "${s.earlyLeaveCount} early leave",
              if (settings.trackNoShow) "${s.noShowCount} no-show",
            ].join(', ');

            return _kvRow(
              _nameFor(e.key),
              "${s.score.toStringAsFixed(0)}  ($label)",
            );
          }),
      ],
    );
  }

  // ============================================================
  // FORECASTING SECTION — historical heatmap, not predictive AI.
  // ============================================================
  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _bucketLabels = [
    '12-4a', '4-8a', '8a-12p', '12-4p', '4-8p', '8p-12a',
  ];

  Widget _forecastingSection() {
    final byDayHour = ForecastingService.hoursByDayAndHour(shifts);

    // Bucket 24 hours into 6 four-hour blocks for a readable grid.
    final Map<int, List<double>> byDayBucket = {
      for (var d = 1; d <= 7; d++)
        d: List.generate(6, (b) {
          var sum = 0.0;
          for (var h = b * 4; h < b * 4 + 4; h++) {
            sum += byDayHour[d]?[h] ?? 0;
          }
          return sum;
        }),
    };

    var max = 0.0;
    for (final row in byDayBucket.values) {
      for (final v in row) {
        if (v > max) max = v;
      }
    }

    return _section(
      title: "Forecasting",
      children: [
        const Text(
          "Historical hours worked by day and time of day, across "
          "all shifts on record. A guide, not a prediction — busier "
          "cells mean you've needed more people at that time before.",
          style: TextStyle(
              fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 12),
        if (max == 0)
          _emptyLine("No shift data yet")
        else
          _heatmapGrid(byDayBucket, max),
      ],
    );
  }

  Widget _heatmapGrid(Map<int, List<double>> byDayBucket, double max) {
    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: [
        TableRow(children: [
          const SizedBox(width: 36),
          ..._bucketLabels.map((l) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Text(l, style: const TextStyle(fontSize: 9, color: Colors.grey)),
              )),
        ]),
        for (var d = 1; d <= 7; d++)
          TableRow(children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(_dayLabels[d - 1], style: const TextStyle(fontSize: 11)),
            ),
            ...byDayBucket[d]!.map((v) {
              final intensity = max == 0 ? 0.0 : (v / max).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.all(2),
                child: Container(
                  width: 36,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08 + intensity * 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    v > 0 ? v.toStringAsFixed(0) : '',
                    style: TextStyle(
                      fontSize: 10,
                      color: intensity > 0.5 ? Colors.white : Colors.blue[900],
                    ),
                  ),
                ),
              );
            }),
          ]),
      ],
    );
  }

  // ============================================================
  // SHARED PRESENTATION HELPERS
  // ============================================================
  Widget _section({required String title, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _subheading(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 15)),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
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
      child: Text(
        text,
        style: const TextStyle(color: Colors.grey, fontSize: 13),
      ),
    );
  }

  String _formatDate(DateTime d) {
    return "${d.month}/${d.day}/${d.year}";
  }
}