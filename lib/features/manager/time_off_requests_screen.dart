// lib/features/manager/time_off_requests_screen.dart

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/time_off_service.dart';
import '../../core/services/employee_service.dart';
import '../../shared/models/time_off_model.dart';
import '../../shared/models/employee_profile.dart';

class TimeOffRequestsScreen extends StatefulWidget {
  const TimeOffRequestsScreen({super.key});

  @override
  State<TimeOffRequestsScreen> createState() => _TimeOffRequestsScreenState();
}

class _TimeOffRequestsScreenState extends State<TimeOffRequestsScreen> {
  bool loading = true;
  List<TimeOffRequest> requests = [];
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
        TimeOffService.getCompanyTimeOff(companyId),
        EmployeeService.getCompanyEmployees(companyId),
      ]);
      requests = results[0] as List<TimeOffRequest>;
      employees = results[1] as List<EmployeeProfile>;
    } catch (_) {
      requests = [];
      employees = [];
    }

    if (mounted) setState(() => loading = false);
  }

  String _nameFor(String userId) {
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

  Color _statusColor(TimeOffRequest r) {
    if (r.isPending) return Colors.orange;
    if (r.isRejected) return Colors.red;
    if (r.isCancelled) return Colors.grey;
    return Colors.green;
  }

  String _statusLabel(TimeOffRequest r) {
    if (r.isPending) return "Pending";
    if (r.isRejected) return "Rejected";
    if (r.isCancelled) return "Cancelled";
    return "Approved";
  }

  Future<void> _review(TimeOffRequest r) async {
    final noteController = TextEditingController();

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text("Time Off — ${_nameFor(r.userId)}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${_formatDate(r.startDate)} → ${_formatDate(r.endDate)}"),
              if (r.reason != null && r.reason!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text("Reason: ${r.reason}"),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: "Note (optional)",
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'reject'),
              child: const Text("Reject", style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, 'approve'),
              child: const Text("Approve"),
            ),
          ],
        );
      },
    );

    if (action == null) return;

    final managerId = SessionService.activeUserId;
    if (managerId == null) return;

    final note = noteController.text.trim();

    try {
      if (action == 'approve') {
        await TimeOffService.approveTimeOff(
          requestId: r.id,
          managerId: managerId,
          note: note.isEmpty ? null : note,
        );
      } else {
        await TimeOffService.rejectTimeOff(
          requestId: r.id,
          managerId: managerId,
          note: note.isEmpty ? null : note,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'approve' ? "Approved" : "Rejected")),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  String _formatDate(DateTime d) => "${d.month}/${d.day}/${d.year}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Time Off Requests"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : requests.isEmpty
              ? const Center(child: Text("No time off requests"))
              : ListView.builder(
                  itemCount: requests.length,
                  itemBuilder: (context, i) {
                    final r = requests[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Text(_nameFor(r.userId)),
                        subtitle: Text(
                          "${_formatDate(r.startDate)} → ${_formatDate(r.endDate)}"
                          "${r.reason != null && r.reason!.isNotEmpty ? ' • ${r.reason}' : ''}",
                        ),
                        trailing: Chip(
                          label: Text(_statusLabel(r)),
                          backgroundColor: _statusColor(r).withValues(alpha: 0.15),
                          labelStyle: TextStyle(color: _statusColor(r)),
                        ),
                        onTap: r.isPending ? () => _review(r) : null,
                      ),
                    );
                  },
                ),
    );
  }
}