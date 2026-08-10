// lib/features/time_off/time_off_screen.dart

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/time_off_service.dart';
import '../../shared/models/time_off_model.dart';

class TimeOffScreen extends StatefulWidget {
  const TimeOffScreen({super.key});

  @override
  State<TimeOffScreen> createState() => _TimeOffScreenState();
}

class _TimeOffScreenState extends State<TimeOffScreen> {
  bool loading = true;
  List<TimeOffRequest> requests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final companyId = SessionService.activeCompanyId;
    final userId = SessionService.activeUserId;

    if (companyId == null || userId == null) {
      setState(() => loading = false);
      return;
    }

    setState(() => loading = true);

    try {
      requests = await TimeOffService.getUserTimeOff(companyId, userId);
    } catch (_) {
      requests = [];
    }

    if (mounted) setState(() => loading = false);
  }

  Color _statusColor(TimeOffRequest r) {
    if (r.isPending) return Colors.orange;
    if (r.isRejected) return Colors.red;
    if (r.isCancelled) return Colors.grey;
    return Colors.green; // approved
  }

  String _statusLabel(TimeOffRequest r) {
    if (r.isPending) return "Pending";
    if (r.isRejected) return "Rejected";
    if (r.isCancelled) return "Cancelled";
    return "Approved";
  }

  Future<void> _requestDialog() async {
    DateTime? start;
    DateTime? end;
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Request Time Off"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(start == null
                        ? "Select start date"
                        : "Start: ${_formatDate(start!)}"),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => start = picked);
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(end == null
                        ? "Select end date"
                        : "End: ${_formatDate(end!)}"),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: start ?? DateTime.now(),
                        firstDate: start ?? DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => end = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: "Reason (optional)",
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: (start != null && end != null)
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: const Text("Submit"),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || start == null || end == null) return;

    final companyId = SessionService.activeCompanyId;
    final userId = SessionService.activeUserId;
    if (companyId == null || userId == null) return;

    try {
      await TimeOffService.requestTimeOff(
        companyId: companyId,
        userId: userId,
        start: start!,
        end: end!,
        reason: reasonController.text.trim().isEmpty
            ? null
            : reasonController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Time off request sent")),
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
        title: const Text("Time Off"),
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
          : requests.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.event_busy_outlined, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          "No time off requests yet",
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: requests.length,
                  itemBuilder: (context, i) {
                    final r = requests[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          "${_formatDate(r.startDate)} → ${_formatDate(r.endDate)}",
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: r.reason != null && r.reason!.isNotEmpty
                            ? Text(r.reason!)
                            : (r.managerNote != null
                                ? Text("Manager note: ${r.managerNote}")
                                : null),
                        trailing: Chip(
                          label: Text(_statusLabel(r)),
                          backgroundColor: _statusColor(r).withValues(alpha: 0.15),
                          labelStyle: TextStyle(color: _statusColor(r)),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _requestDialog,
        icon: const Icon(Icons.add_outlined),
        label: const Text("Request Time Off"),
      ),
    );
  }
}