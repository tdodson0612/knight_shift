// lib/features/manager/time_entries_screen.dart
//
// Manager view of raw clock punches — correct a mistaken punch, and
// see the full edit history for any entry (backed by
// trg_time_entry_audit, see the migration). This is the missing
// piece that makes "audit trail" meaningful — without an edit path,
// there'd be nothing to audit.

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/employee_service.dart';
import '../../core/services/time_entry_service.dart';
import '../../core/services/clock_in_photo_service.dart';
import '../../shared/models/employee_profile.dart';
import '../../shared/models/time_entry_model.dart';

class TimeEntriesScreen extends StatefulWidget {
  const TimeEntriesScreen({super.key});

  @override
  State<TimeEntriesScreen> createState() => _TimeEntriesScreenState();
}

class _TimeEntriesScreenState extends State<TimeEntriesScreen> {
  bool loading = true;
  List<TimeEntry> entries = [];
  List<EmployeeProfile> employees = [];

  DateTime start = DateTime.now().subtract(const Duration(days: 7));
  DateTime end = DateTime.now();

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
        TimeEntryService.getCompanyTimeEntries(
          companyId: companyId,
          start: start,
          end: end,
        ),
        EmployeeService.getCompanyEmployees(companyId),
      ]);
      entries = results[0] as List<TimeEntry>;
      employees = results[1] as List<EmployeeProfile>;
    } catch (_) {
      entries = [];
    }

    if (mounted) setState(() => loading = false);
  }

  String _nameFor(String userId) {
    final match = employees.where((e) => e.userId == userId);
    return match.isEmpty ? "Unknown" : match.first.displayName;
  }

  String _fmt(DateTime? d) {
    if (d == null) return "—";
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final period = d.hour >= 12 ? "PM" : "AM";
    return "${d.month}/${d.day} $h:${d.minute.toString().padLeft(2, '0')} $period";
  }

  Future<void> _viewPhoto(String path) async {
    try {
      final url = await ClockInPhotoService.getSignedUrl(path);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => Dialog(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't load photo: \$e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openEntry(TimeEntry entry) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TimeEntryEditSheet(
        entry: entry,
        employeeName: _nameFor(entry.userId),
      ),
    );

    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Time Entries"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? const Center(
                  child: Text("No punches in this period",
                      style: TextStyle(color: Colors.grey)),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final e = entries[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () => _openEntry(e),
                          leading: Icon(
                            e.isOpen ? Icons.timer : Icons.check_circle_outline,
                            color: e.isOpen ? Colors.orange : null,
                          ),
                          title: Text(_nameFor(e.userId)),
                          subtitle: Text(
                            "In: ${_fmt(e.clockIn)}  •  Out: ${_fmt(e.clockOut)}",
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (e.hasPhoto)
                                IconButton(
                                  icon: const Icon(Icons.photo_camera_outlined, size: 20),
                                  tooltip: "View clock-in photo",
                                  onPressed: () => _viewPhoto(e.clockInPhotoPath!),
                                ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _TimeEntryEditSheet extends StatefulWidget {
  final TimeEntry entry;
  final String employeeName;

  const _TimeEntryEditSheet({required this.entry, required this.employeeName});

  @override
  State<_TimeEntryEditSheet> createState() => _TimeEntryEditSheetState();
}

class _TimeEntryEditSheetState extends State<_TimeEntryEditSheet> {
  late DateTime clockIn;
  DateTime? clockOut;
  bool saving = false;
  bool loadingHistory = true;
  List<TimeEntryAuditEntry> history = [];

  @override
  void initState() {
    super.initState();
    clockIn = widget.entry.clockIn;
    clockOut = widget.entry.clockOut;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      history = await TimeEntryService.getAuditLog(widget.entry.id);
    } catch (_) {
      history = [];
    }
    if (mounted) setState(() => loadingHistory = false);
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _editClockIn() async {
    final picked = await _pickDateTime(clockIn);
    if (picked != null) setState(() => clockIn = picked);
  }

  Future<void> _editClockOut() async {
    final picked = await _pickDateTime(clockOut ?? clockIn);
    if (picked != null) setState(() => clockOut = picked);
  }

  Future<void> _save() async {
    if (clockOut != null && clockOut!.isBefore(clockIn)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Clock out can't be before clock in"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => saving = true);

    try {
      await TimeEntryService.updateTimeEntry(
        timeEntryId: widget.entry.id,
        clockIn: clockIn,
        clockOut: clockOut,
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

  String _fmt(DateTime? d) {
    if (d == null) return "—";
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final period = d.hour >= 12 ? "PM" : "AM";
    return "${d.month}/${d.day} $h:${d.minute.toString().padLeft(2, '0')} $period";
  }

  @override
  Widget build(BuildContext context) {
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
              widget.employeeName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),

            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Clock In"),
              subtitle: Text(_fmt(clockIn)),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: _editClockIn,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Clock Out"),
              subtitle: Text(_fmt(clockOut)),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: _editClockOut,
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving ? null : _save,
                child: Text(saving ? "Saving..." : "Save Correction"),
              ),
            ),

            const Divider(height: 32),
            const Text(
              "Edit History",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            if (loadingHistory)
              const Center(child: CircularProgressIndicator())
            else if (history.isEmpty)
              const Text("No edits recorded",
                  style: TextStyle(color: Colors.grey, fontSize: 13))
            else
              ...history.map((h) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${h.changeType[0].toUpperCase()}${h.changeType.substring(1)} — ${_fmt(h.changedAt)}",
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        if (h.changeType == 'updated') ...[
                          if (h.oldClockIn != h.newClockIn)
                            Text(
                              "Clock in: ${_fmt(h.oldClockIn)} → ${_fmt(h.newClockIn)}",
                              style: const TextStyle(fontSize: 12),
                            ),
                          if (h.oldClockOut != h.newClockOut)
                            Text(
                              "Clock out: ${_fmt(h.oldClockOut)} → ${_fmt(h.newClockOut)}",
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}