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
import '../../core/services/role_service.dart';
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
        actions: [
          if (RoleService.isManager()) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: "Edit profile",
              onPressed: null, // Future: inline edit mode
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: Colors.grey.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.teal.shade100,
                        child: Text(
                          employee.initials,
                          style: TextStyle(
                            color: Colors.teal.shade800,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              employee.displayName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _roleColor(employee.role),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                employee.role,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _roleTextColor(employee.role),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _infoRow(
                    icon: Icons.email_outlined,
                    label: "Email",
                    value: employee.email,
                  ),
                  const SizedBox(height: 12),
                  _infoRow(
                    icon: Icons.payments_outlined,
                    label: "Hourly Rate",
                    value: "\$${currentRate.toStringAsFixed(2)}",
                    onTap: savingRate ? null : _editRate,
                  ),
                  const SizedBox(height: 12),
                  _infoRow(
                    icon: Icons.calendar_today_outlined,
                    label: "Hire Date",
                    value: currentHireDate == null
                        ? "Not set"
                        : _formatDate(currentHireDate!),
                    onTap: savingHireDate ? null : _editHireDate,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _skillsSection(),
          const SizedBox(height: 20),
          _reliabilitySection(),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.schedule_outlined, size: 18, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        "Availability",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (loadingAvailability)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (availability.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        "No availability set yet",
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                      ),
                    )
                  else
                    ...List.generate(7, (day) => _availabilityRow(day + 1)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case 'manager':
        return Colors.blue.shade50;
      case 'admin':
        return Colors.purple.shade50;
      case 'accountant':
        return Colors.amber.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  Color _roleTextColor(String role) {
    switch (role.toLowerCase()) {
      case 'manager':
        return Colors.blue.shade700;
      case 'admin':
        return Colors.purple.shade700;
      case 'accountant':
        return Colors.amber.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade900,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade400),
          ],
        ),
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

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_outlined, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  "Skills",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allSkills.map((skill) {
                final assigned = assignedSkillIds.contains(skill.id);
                return FilterChip(
                  label: Text(skill.label),
                  selected: assigned,
                  onSelected: (v) => _toggleSkill(skill, v),
                  selectedColor: Colors.teal.shade100,
                  checkmarkColor: Colors.teal.shade700,
                  labelStyle: TextStyle(
                    color: assigned ? Colors.teal.shade800 : Colors.grey.shade700,
                    fontWeight: assigned ? FontWeight.w600 : FontWeight.w400,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
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
      return const SizedBox.shrink();
    }

    final stats = reliabilityStats;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  "Reliability",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Last $_reliabilityLookbackDays days",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            if (stats == null || stats.shiftsEvaluated == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "No completed shifts in this period yet",
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Score",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stats.score.toStringAsFixed(0),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: _scoreColor(stats.score),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.grey.shade200,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Shifts evaluated",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stats.shiftsEvaluated.toString(),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              if (settings.trackLate)
                _kvRow("Late clock-ins", stats.lateCount.toString(), Icons.access_time),
              if (settings.trackEarlyLeave)
                _kvRow("Early leaves", stats.earlyLeaveCount.toString(), Icons.exit_to_app),
              if (settings.trackNoShow)
                _kvRow("No-shows", stats.noShowCount.toString(), Icons.event_busy),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kvRow(String label, String value, [IconData? icon]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
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