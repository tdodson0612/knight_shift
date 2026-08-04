// lib/features/manager/incident_reports_screen.dart
//
// Manager-facing review screen. Lists all incident reports for the
// company (RLS already restricts SELECT to managers) and lets a
// manager set status, add resolution notes, and decide — per report
// — whether to share it with the reported employee.

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/employee_service.dart';
import '../../core/services/incident_report_service.dart';
import '../../shared/models/employee_profile.dart';
import '../../shared/models/incident_report_model.dart';

class IncidentReportsScreen extends StatefulWidget {
  const IncidentReportsScreen({super.key});

  @override
  State<IncidentReportsScreen> createState() => _IncidentReportsScreenState();
}

class _IncidentReportsScreenState extends State<IncidentReportsScreen> {
  bool loading = true;
  List<IncidentReport> reports = [];
  List<EmployeeProfile> employees = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) {
      setState(() => loading = false);
      return;
    }

    setState(() => loading = true);

    try {
      final results = await Future.wait([
        IncidentReportService.getCompanyReports(companyId),
        EmployeeService.getCompanyEmployees(companyId),
      ]);
      reports = results[0] as List<IncidentReport>;
      employees = results[1] as List<EmployeeProfile>;
    } catch (_) {
      reports = [];
    }

    if (mounted) setState(() => loading = false);
  }

  String _nameFor(String? userId) {
    if (userId == null) return "Unspecified";
    final match = employees.where((e) => e.userId == userId);
    return match.isEmpty ? "Former employee" : match.first.displayName;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'submitted':
        return Colors.orange;
      case 'under_review':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      case 'dismissed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Future<void> _openDetail(IncidentReport report) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _IncidentDetailSheet(
        report: report,
        reportedName: _nameFor(report.reportedUserId),
        submittedByName:
            report.isAnonymous ? "Anonymous" : _nameFor(report.submittedByUserId),
      ),
    );

    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Incident Reports"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : reports.isEmpty
              ? const Center(
                  child: Text(
                    "No incident reports",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: reports.length,
                    itemBuilder: (context, index) {
                      final r = reports[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () => _openDetail(r),
                          title: Text(
                            r.reportedUserId == null
                                ? "General report"
                                : "About: ${_nameFor(r.reportedUserId)}",
                          ),
                          subtitle: Text(
                            r.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Chip(
                            label: Text(
                              r.status.replaceAll('_', ' '),
                              style: const TextStyle(fontSize: 11),
                            ),
                            backgroundColor:
                                _statusColor(r.status).withValues(alpha: 0.15),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _IncidentDetailSheet extends StatefulWidget {
  final IncidentReport report;
  final String reportedName;
  final String submittedByName;

  const _IncidentDetailSheet({
    required this.report,
    required this.reportedName,
    required this.submittedByName,
  });

  @override
  State<_IncidentDetailSheet> createState() => _IncidentDetailSheetState();
}

class _IncidentDetailSheetState extends State<_IncidentDetailSheet> {
  late String status;
  late bool sharedWithReported;
  late final TextEditingController _notesController;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    status = widget.report.status;
    sharedWithReported = widget.report.sharedWithReported;
    _notesController =
        TextEditingController(text: widget.report.managerNotes ?? '');
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final managerId = SessionService.activeUserId;
    setState(() => saving = true);

    try {
      await IncidentReportService.updateStatus(
        reportId: widget.report.id,
        status: status,
        managerNotes: _notesController.text.trim(),
        sharedWithReported: sharedWithReported,
        resolvedByUserId: managerId,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.reportedUserId == null
                  ? "General report"
                  : "About: ${widget.reportedName}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              "Submitted by: ${widget.submittedByName}"
              "${r.incidentDate != null ? '  •  ${r.incidentDate!.month}/${r.incidentDate!.day}/${r.incidentDate!.year}' : ''}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Text(r.description),
            const Divider(height: 24),

            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(
                labelText: "Status",
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'submitted', child: Text("Submitted")),
                DropdownMenuItem(value: 'under_review', child: Text("Under Review")),
                DropdownMenuItem(value: 'resolved', child: Text("Resolved")),
                DropdownMenuItem(value: 'dismissed', child: Text("Dismissed")),
              ],
              onChanged: (v) => setState(() => status = v ?? status),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: "Manager notes / resolution",
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),

            if (r.reportedUserId != null) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Share this report with the reported employee"),
                subtitle: const Text(
                  "Your decision, per report — not a company-wide setting.",
                  style: TextStyle(fontSize: 11),
                ),
                value: sharedWithReported,
                onChanged: (v) => setState(() => sharedWithReported = v),
              ),
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving ? null : _save,
                child: Text(saving ? "Saving..." : "Save"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}