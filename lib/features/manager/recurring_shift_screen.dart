// lib/features/manager/recurring_shift_screen.dart
//
// Recurring shift pattern generator (Feature 4): "this employee works
// every Mon/Wed/Fri 9-5 for N weeks" instead of one shift at a time.
// Generates individual `shifts` rows via ShiftService.createRecurringShifts
// (which loops createShift per occurrence) — no parallel recurring-shift
// table, shifts stay the single source of truth.

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/shift_service.dart';
import '../../core/services/employee_service.dart';
import '../../shared/models/employee_profile.dart';

class RecurringShiftScreen extends StatefulWidget {
  const RecurringShiftScreen({super.key});

  @override
  State<RecurringShiftScreen> createState() => _RecurringShiftScreenState();
}

class _RecurringShiftScreenState extends State<RecurringShiftScreen> {
  bool loadingEmployees = true;
  List<EmployeeProfile> employees = [];

  String? selectedUserId;
  final Set<int> selectedDays = {};
  TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);
  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now().add(const Duration(days: 28));

  bool generating = false;

  static const _dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) {
      setState(() => loadingEmployees = false);
      return;
    }

    try {
      employees = await EmployeeService.getCompanyEmployees(companyId);
    } catch (_) {
      employees = [];
    }

    if (mounted) setState(() => loadingEmployees = false);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(context: context, initialTime: startTime);
    if (picked != null) setState(() => startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(context: context, initialTime: endTime);
    if (picked != null) setState(() => endTime = picked);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() {
        startDate = picked;
        if (endDate.isBefore(picked)) {
          endDate = picked.add(const Duration(days: 28));
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: endDate,
      firstDate: startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => endDate = picked);
  }

  Future<void> _generate() async {
    final companyId = SessionService.activeCompanyId;
    final managerId = SessionService.activeUserId;
    if (companyId == null || managerId == null) return;

    if (selectedUserId == null) {
      _error("Pick an employee");
      return;
    }
    if (selectedDays.isEmpty) {
      _error("Pick at least one day of the week");
      return;
    }
    if (endTime.hour * 60 + endTime.minute <= startTime.hour * 60 + startTime.minute) {
      _error("End time must be after start time");
      return;
    }

    setState(() => generating = true);

    try {
      final result = await ShiftService.createRecurringShifts(
        companyId: companyId,
        userId: selectedUserId,
        createdBy: managerId,
        daysOfWeek: selectedDays,
        startTime: TimeOfDaySpec(hour: startTime.hour, minute: startTime.minute),
        endTime: TimeOfDaySpec(hour: endTime.hour, minute: endTime.minute),
        startDate: startDate,
        endDate: endDate,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Created ${result.created} shift${result.created == 1 ? '' : 's'}"
            "${result.skipped > 0 ? ' (${result.skipped} skipped — conflicts)' : ''}",
          ),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _error("$e");
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _fmtTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? "AM" : "PM";
    return "$hour:$minute $period";
  }

  String _fmtDate(DateTime d) {
    return "${d.month}/${d.day}/${d.year}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Recurring Shifts")),
      body: loadingEmployees
          ? const Center(child: CircularProgressIndicator())
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
                    "Create the same shift on a repeating schedule — "
                    "e.g. every Mon/Wed/Fri 9-5 for 4 weeks. Each "
                    "occurrence is created as a normal shift and "
                    "checked for conflicts individually.",
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: selectedUserId,
                  decoration: const InputDecoration(
                    labelText: "Employee",
                    border: OutlineInputBorder(),
                  ),
                  items: employees
                      .map((e) => DropdownMenuItem(
                            value: e.userId,
                            child: Text(e.displayName),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => selectedUserId = v),
                ),

                const SizedBox(height: 16),
                const Text(
                  "Days of the week",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: List.generate(7, (i) {
                    final day = i + 1;
                    final selected = selectedDays.contains(day);
                    return FilterChip(
                      label: Text(_dayNames[i]),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          selectedDays.add(day);
                        } else {
                          selectedDays.remove(day);
                        }
                      }),
                    );
                  }),
                ),

                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Start time"),
                  trailing: Text(_fmtTime(startTime)),
                  onTap: _pickStartTime,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("End time"),
                  trailing: Text(_fmtTime(endTime)),
                  onTap: _pickEndTime,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Start date"),
                  trailing: Text(_fmtDate(startDate)),
                  onTap: _pickStartDate,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("End date"),
                  trailing: Text(_fmtDate(endDate)),
                  onTap: _pickEndDate,
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: generating ? null : _generate,
                    child: Text(generating ? "Generating..." : "Generate Shifts"),
                  ),
                ),
              ],
            ),
    );
  }
}