// lib/features/incident_reports/incident_report_submit_screen.dart
//
// Employee-facing submission form. Only reachable if the company has
// incident_reports_enabled — the caller (nav entry point) is
// responsible for that gate; this screen re-checks defensively in
// case it's ever reached another way.

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/employee_service.dart';
import '../../core/services/incident_report_service.dart';
import '../../shared/models/employee_profile.dart';
import '../../shared/models/incident_report_model.dart';

class IncidentReportSubmitScreen extends StatefulWidget {
  const IncidentReportSubmitScreen({super.key});

  @override
  State<IncidentReportSubmitScreen> createState() =>
      _IncidentReportSubmitScreenState();
}

class _IncidentReportSubmitScreenState
    extends State<IncidentReportSubmitScreen> {
  bool loading = true;
  bool submitting = false;

  IncidentReportSettings? settings;
  List<EmployeeProfile> employees = [];

  String? selectedCoworkerId;
  DateTime? incidentDate;
  bool anonymous = false;
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final companyId = SessionService.activeCompanyId;
    final myUserId = SessionService.activeUserId;
    if (companyId == null) {
      setState(() => loading = false);
      return;
    }

    try {
      final results = await Future.wait([
        IncidentReportService.getSettings(companyId),
        EmployeeService.getCompanyEmployees(companyId),
      ]);
      settings = results[0] as IncidentReportSettings;
      employees = (results[1] as List<EmployeeProfile>)
          .where((e) => e.userId != myUserId)
          .toList();
    } catch (_) {
      settings = null;
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: incidentDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => incidentDate = picked);
  }

  Future<void> _submit() async {
    final companyId = SessionService.activeCompanyId;
    final userId = SessionService.activeUserId;
    final description = _descriptionController.text.trim();

    if (companyId == null || userId == null) return;

    if (description.isEmpty) {
      _error("Please describe what happened");
      return;
    }

    setState(() => submitting = true);

    try {
      await IncidentReportService.submitReport(
        companyId: companyId,
        description: description,
        reportedUserId: selectedCoworkerId,
        incidentDate: incidentDate,
        anonymous: anonymous,
        submittedByUserId: userId,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Report submitted")),
      );
    } catch (e) {
      _error("Couldn't submit report: $e");
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _formatDate(DateTime d) => "${d.month}/${d.day}/${d.year}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Report an Incident")),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : (settings == null || !settings!.enabled)
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "Incident reporting isn't enabled for this company.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "This goes directly to your manager. It is not "
                        "visible to other coworkers.",
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      initialValue: selectedCoworkerId,
                      decoration: const InputDecoration(
                        labelText: "About (optional)",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text("Not about a specific coworker"),
                        ),
                        ...employees.map((e) => DropdownMenuItem<String>(
                              value: e.userId,
                              child: Text(e.displayName),
                            )),
                      ],
                      onChanged: (v) =>
                          setState(() => selectedCoworkerId = v),
                    ),
                    const SizedBox(height: 12),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        incidentDate == null
                            ? "Date it happened (optional)"
                            : _formatDate(incidentDate!),
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined, size: 20),
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _descriptionController,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: "What happened",
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),

                    if (settings!.allowAnonymous) ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Submit anonymously"),
                        subtitle: const Text(
                          "Your name won't be recorded at all — not even "
                          "your manager will be able to see who submitted "
                          "this.",
                          style: TextStyle(fontSize: 11),
                        ),
                        value: anonymous,
                        onChanged: (v) => setState(() => anonymous = v),
                      ),
                    ],

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: submitting ? null : _submit,
                        child: Text(
                          submitting ? "Submitting..." : "Submit Report",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}