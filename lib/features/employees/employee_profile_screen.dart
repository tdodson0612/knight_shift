// lib/features/employees/employee_profile_screen.dart

import 'package:flutter/material.dart';

import '../../shared/models/employee_profile.dart';
import '../../shared/models/availability_model.dart';
import '../../shared/models/reliability_settings_model.dart';
import '../../core/services/availability_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/shift_service.dart';
import '../../core/services/reliability_service.dart';
import '../../core/services/employee_service.dart';
import '../../core/services/employee_skill_service.dart';
import '../../shared/models/employee_skill_model.dart';

const List<String> _dayNames = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

// How far back the reliability snapshot on this screen looks. Not a
// user-adjustable filter (yet) — matches the "keep it simple for now"
// scope of this addition. Revisit if managers want a custom range.
const int _reliabilityLookbackDays = 30;

class EmployeeProfileScreen extends StatefulWidget {
  final EmployeeProfile employee;

  const EmployeeProfileScreen({
    super.key,
    required this.employee,
  });

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  bool loadingAvailability = true;
  List<AvailabilityWindow> availability = [];

  late double currentRate;
  bool savingRate = false;

  DateTime? currentHireDate;
  bool savingHireDate = false;

  bool loadingReliability = true;
  ReliabilitySettings? reliabilitySettings;
  ReliabilityStats? reliabilityStats;

  // Skills state.
  bool loadingSkills = true;
  List<EmployeeSkill> allSkills = [];
  Set<String> assignedSkillIds = {};
  bool savingSkills = false;

  @override
  void initState() {
    super.initState();
    currentRate = widget.employee.hourlyRate;
    currentHireDate = widget.employee.hireDate;
    _loadAvailability();
    _loadReliability();
    _loadSkills();
  }

  Future<void> _loadAvailability() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) {
      setState(() => loadingAvailability = false);
      return;
    }

    try {
      availability = await AvailabilityService.getAvailability(
        companyId,
        widget.employee.userId,
      );
    } catch (_) {
      availability = [];
    }

    if (mounted) setState(() => loadingAvailability = false);
  }

  Future<void> _loadSkills() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) {
      setState(() => loadingSkills = false);
      return;
    }

    try {
      final results = await Future.wait([
        EmployeeSkillService.getSkills(companyId),
        EmployeeSkillService.getAssignmentsForUser(
          companyId: companyId,
          userId: widget.employee.userId,
        ),
      ]);

      allSkills = results[0] as List<EmployeeSkill>;
      final assignments = results[1] as List<EmployeeSkillAssignment>;
      assignedSkillIds = assignments.map((a) => a.skillId).toSet();
    } catch (_) {
      allSkills = [];
      assignedSkillIds = {};
    }

    if (mounted) setState(() => loadingSkills = false);
  }

  Future<void> _toggleSkill(EmployeeSkill skill, bool assign) async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) return;

    setState(() {
      if (assign) {
        assignedSkillIds.add(skill.id);
      } else {
        assignedSkillIds.remove(skill.id);
      }
    });

    try {
      if (assign) {
        await EmployeeSkillService.assignSkill(
          companyId: companyId,
          userId: widget.employee.userId,
          skillId: skill.id,
        );
      } else {
        await EmployeeSkillService.unassignSkill(
          companyId: companyId,
          userId: widget.employee.userId,
          skillId: skill.id,
        );
      }
    } catch (e) {
      // Revert on failure so UI matches what's actually saved.
      setState(() {
        if (assign) {
          assignedSkillIds.remove(skill.id);
        } else {
          assignedSkillIds.add(skill.id);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadReliability() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) {
      setState(() => loadingReliability = false);
      return;
    }

    try {
      final settings = await ReliabilityService.getSettings(companyId);

      if (!settings.enabled) {
        reliabilitySettings = settings;
        reliabilityStats = null;
        if (mounted) setState(() => loadingReliability = false);
        return;
      }

      final end = DateTime.now();
      final start = end.subtract(const Duration(days: _reliabilityLookbackDays));

      final allShifts = await ShiftService.getCompanyShifts(companyId);
      final thisEmployeeShifts =
          allShifts.where((s) => s.userId == widget.employee.userId).toList();

      final statsByUser = await ReliabilityService.calculateStatsByUser(
        companyId: companyId,
        shifts: thisEmployeeShifts,
        start: start,
        end: end,
        settings: settings,
      );

      reliabilitySettings = settings;
      reliabilityStats = statsByUser[widget.employee.userId];
    } catch (_) {
      reliabilitySettings = null;
      reliabilityStats = null;
    }

    if (mounted) setState(() => loadingReliability = false);
  }

  Future<void> _editHireDate() async {
    final initial = currentHireDate ?? DateTime.now();

    final result = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: "Select Hire Date",
    );

    if (result == null) return;

    setState(() => savingHireDate = true);

    try {
      await EmployeeService.updateHireDate(
        companyId: widget.employee.companyId,
        userId: widget.employee.userId,
        hireDate: result,
      );

      if (!mounted) return;
      setState(() => currentHireDate = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save hire date: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => savingHireDate = false);
    }
  }

  Future<void> _editRate() async {
    final controller =
        TextEditingController(text: currentRate.toStringAsFixed(2));

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit Hourly Rate"),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            prefixText: "\$",
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              Navigator.pop(ctx, parsed);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (result == null || result < 0) return;

    setState(() => savingRate = true);

    try {
      await EmployeeService.updateHourlyRate(
        companyId: widget.employee.companyId,
        userId: widget.employee.userId,
        hourlyRate: result,
      );

      if (!mounted) return;
      setState(() => currentRate = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save rate: \$e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => savingRate = false);
    }
  }

  String _formatDate(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? "AM" : "PM";
    return "$hour:$minute $period";
  }

  Color _scoreColor(double score) {
    if (score >= 90) return Colors.green;
    if (score >= 70) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final employee = widget.employee;

    return Scaffold(
      appBar: AppBar(
        title: Text(employee.displayName),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("Name: ${employee.displayName}"),
          Text("Role: ${employee.role}"),
          Text("User ID: ${employee.userId}"),
          const SizedBox(height: 4),
          Row(
            children: [
              Text("Hourly Rate: \$${currentRate.toStringAsFixed(2)}"),
              const SizedBox(width: 8),
              InkWell(
                onTap: savingRate ? null : _editRate,
                child: Icon(Icons.edit, size: 16, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                currentHireDate == null
                    ? "Hire Date: Not set"
                    : "Hire Date: ${_formatDate(currentHireDate!)}",
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: savingHireDate ? null : _editHireDate,
                child: Icon(Icons.edit, size: 16, color: Colors.grey[600]),
              ),
            ],
          ),

          const SizedBox(height: 24),
          _skillsSection(),

          const SizedBox(height: 24),
          _reliabilitySection(),

          const SizedBox(height: 24),
          const Text(
            "Availability",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Divider(),

          if (loadingAvailability)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (availability.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                "No availability set yet",
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            for (int day = 1; day <= 7; day++) _availabilityRow(day),
        ],
      ),
    );
  }

  Widget _skillsSection() {
    if (loadingSkills) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (allSkills.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Skills",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const Divider(),
        ...allSkills.map((skill) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(skill.label, style: const TextStyle(fontSize: 13)),
              value: assignedSkillIds.contains(skill.id),
              onChanged: (v) => _toggleSkill(skill, v ?? false),
            )),
      ],
    );
  }

  Widget _reliabilitySection() {
    if (loadingReliability) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final settings = reliabilitySettings;

    if (settings == null || !settings.enabled) {
      // Not enabled for this company — say nothing dramatic, just
      // skip the section rather than showing an empty/zero score
      // that could look like a real judgment on the employee.
      return const SizedBox.shrink();
    }

    final stats = reliabilityStats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Reliability",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          "Last $_reliabilityLookbackDays days",
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const Divider(),
        if (stats == null || stats.shiftsEvaluated == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "No completed shifts in this period yet",
              style: TextStyle(color: Colors.grey),
            ),
          )
        else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Score", style: TextStyle(fontSize: 15)),
              Text(
                stats.score.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _scoreColor(stats.score),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (settings.trackLate)
            _kvRow("Late clock-ins", stats.lateCount.toString()),
          if (settings.trackEarlyLeave)
            _kvRow("Early leaves", stats.earlyLeaveCount.toString()),
          if (settings.trackNoShow)
            _kvRow("No-shows / missed shifts", stats.noShowCount.toString()),
          _kvRow("Shifts evaluated", stats.shiftsEvaluated.toString()),
        ],
      ],
    );
  }

  Widget _kvRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value),
        ],
      ),
    );
  }

  Widget _availabilityRow(int dayOfWeek) {
    final window = availability.where((w) => w.dayOfWeek == dayOfWeek);
    final label = _dayNames[dayOfWeek - 1];

    if (window.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            const Text("Not available", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final w = window.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text("${_formatTime(w.startTime)} – ${_formatTime(w.endTime)}"),
        ],
      ),
    );
  }
}