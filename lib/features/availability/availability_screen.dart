// lib/features/availability/availability_screen.dart

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/availability_service.dart';
import '../../shared/models/availability_model.dart';

const List<String> _dayNames = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  bool loading = true;
  bool saving = false;

  // Index 0..6 = Mon..Sun (dayOfWeek = index + 1).
  final List<bool> available = List.filled(7, false);
  final List<TimeOfDay> startTimes =
      List.filled(7, const TimeOfDay(hour: 9, minute: 0));
  final List<TimeOfDay> endTimes =
      List.filled(7, const TimeOfDay(hour: 17, minute: 0));

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

    try {
      final windows = await AvailabilityService.getAvailability(
        companyId,
        userId,
      );

      for (final w in windows) {
        final idx = w.dayOfWeek - 1;
        if (idx < 0 || idx > 6) continue;
        available[idx] = true;
        startTimes[idx] = w.startTime;
        endTimes[idx] = w.endTime;
      }
    } catch (_) {
      // leave defaults
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final companyId = SessionService.activeCompanyId;
    final userId = SessionService.activeUserId;

    if (companyId == null || userId == null) return;

    setState(() => saving = true);

    final windows = <AvailabilityWindow>[];
    for (int i = 0; i < 7; i++) {
      if (!available[i]) continue;
      windows.add(AvailabilityWindow(
        dayOfWeek: i + 1,
        startTime: startTimes[i],
        endTime: endTimes[i],
      ));
    }

    try {
      await AvailabilityService.setAvailability(
        companyId: companyId,
        userId: userId,
        windows: windows,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Availability saved")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error saving: $e")),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _pickTime(int dayIndex, bool isStart) async {
    final initial = isStart ? startTimes[dayIndex] : endTimes[dayIndex];
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;

    setState(() {
      if (isStart) {
        startTimes[dayIndex] = picked;
      } else {
        endTimes[dayIndex] = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Availability"),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  "Let your manager know which days and times you're generally available to work. No row = not available that day.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                for (int i = 0; i < 7; i++) _dayRow(i),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: saving ? null : _save,
                    child: Text(saving ? "Saving..." : "Save Availability"),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _dayRow(int i) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(_dayNames[i], style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Switch(
              value: available[i],
              onChanged: (v) => setState(() => available[i] = v),
            ),
            if (available[i]) ...[
              Expanded(
                child: TextButton(
                  onPressed: () => _pickTime(i, true),
                  child: Text(_formatTime(startTimes[i])),
                ),
              ),
              const Text("–"),
              Expanded(
                child: TextButton(
                  onPressed: () => _pickTime(i, false),
                  child: Text(_formatTime(endTimes[i])),
                ),
              ),
            ] else
              const Expanded(
                flex: 2,
                child: Text("Not available", style: TextStyle(color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? "AM" : "PM";
    return "$hour:$minute $period";
  }
}