// lib/features/manager/scheduling_screen.dart

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/shift_service.dart';
import '../../core/services/employee_service.dart';
import '../../core/services/labor_budget_service.dart';
import '../../core/services/overtime_service.dart';
import '../../core/services/employee_skill_service.dart';

import '../../shared/models/shift_model.dart';
import '../../shared/models/employee_profile.dart';
import '../../shared/models/employee_skill_model.dart';
import '../scheduling/shift_detail_sheet.dart';
import 'recurring_shift_screen.dart';

class ManagerSchedulingScreen extends StatefulWidget {
  const ManagerSchedulingScreen({super.key});

  @override
  State<ManagerSchedulingScreen> createState() =>
      _ManagerSchedulingScreenState();
}

class _ManagerSchedulingScreenState extends State<ManagerSchedulingScreen> {
  bool loading = true;
  bool creating = false;

  List<ShiftModel> shifts = [];
  List<EmployeeProfile> employees = [];

  final int startHour = 6;
  final int endHour = 22;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final companyId = SessionService.activeCompanyId;

    setState(() => loading = true);

    if (companyId == null) {
      setState(() => loading = false);
      return;
    }

    try {
      final results = await Future.wait([
        ShiftService.getCompanyShifts(companyId),
        EmployeeService.getCompanyEmployees(companyId),
      ]);

      shifts = results[0] as List<ShiftModel>;
      employees = results[1] as List<EmployeeProfile>;
    } catch (_) {
      shifts = [];
      employees = [];
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Weekly Schedule"),
        actions: [
          IconButton(
            icon: const Icon(Icons.repeat),
            tooltip: "Recurring Shifts",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecurringShiftScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.content_copy),
            tooltip: "Copy This Week to Next Week",
            onPressed: _copyWeek,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: load,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  color: Colors.teal.shade50,
                  child: const Text(
                    "Tap an empty slot to schedule yourself • "
                    "Long-press to post an open shift • "
                    "Long-press an existing shift for comments/checklist",
                    style: TextStyle(fontSize: 11, color: Colors.teal),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(child: _buildGrid()),
              ],
            ),
    );
  }

  Widget _buildGrid() {
    return Column(
      children: [
        _header(),
        Expanded(
          child: Row(
            children: List.generate(
              7,
              (day) => Expanded(child: _day(day)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    return Row(
      children: days
          .map(
            (d) => Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                color: Colors.grey.shade200,
                child: Center(child: Text(d)),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _day(int dayIndex) {
    final dayShifts = shifts.where((s) {
      return s.startTime.weekday == dayIndex + 1;
    }).toList();

    return Stack(
      children: [
        Column(
          children: List.generate(endHour - startHour, (i) {
            final hour = i + startHour;

            return GestureDetector(
              onTap: () => _create(dayIndex, hour),
              onLongPress: () => _postOpenShift(dayIndex, hour),
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            );
          }),
        ),
        ...dayShifts.map(_shift),
      ],
    );
  }

  Color _statusColor(ShiftModel s) {
    if (s.isOpen) return Colors.teal.shade100;
    if (s.isPending) return Colors.orange.shade300;
    if (s.isRejected) return Colors.red.shade200;
    if (s.isCancelled) return Colors.grey.shade400;
    if (s.isSwapRequested || s.isSwapPending) return Colors.purple.shade200;
    return Colors.blue.shade200; // approved
  }

  EmployeeProfile? _employeeFor(String? userId) {
    if (userId == null) return null;
    return employees.firstWhere(
      (e) => e.userId == userId,
      orElse: () => EmployeeProfile(
        userId: userId,
        companyId: '',
        role: 'employee',
        displayName: userId,
        email: '',
      ),
    );
  }

  Widget _shift(ShiftModel s) {
    final start = s.startTime;
    final end = s.endTime;

    final top = ((start.hour - startHour) * 60 + start.minute).toDouble();
    final height = end.difference(start).inMinutes.toDouble();

    final emp = _employeeFor(s.userId);
    final label = s.isOpen ? "Open Shift" : (emp?.displayName ?? "Unknown");

    final block = Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _statusColor(s),
        borderRadius: BorderRadius.circular(6),
        border: s.isOpen ? Border.all(color: Colors.teal, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            s.displayStatus,
            style: const TextStyle(fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    VoidCallback? onTap;
    if (s.isPending && emp != null) {
      onTap = () => _reviewShift(s, emp);
    } else if (s.isSwapPending) {
      onTap = () => _reviewSwap(s);
    }

    return Positioned(
      top: top,
      left: 4,
      right: 4,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: () => showShiftDetailSheet(context, s),
        child: block,
      ),
    );
  }

  // ----------------------------
  // POST AN OPEN SHIFT (long-press an empty slot)
  // ----------------------------
  Future<void> _postOpenShift(int day, int hour) async {
    if (creating) return;

    final companyId = SessionService.activeCompanyId;
    final managerId = SessionService.activeUserId;
    if (companyId == null || managerId == null) return;

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, hour)
        .add(Duration(days: day - now.weekday));
    final end = start.add(const Duration(hours: 8));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Post Open Shift"),
        content: Text(
          "${_formatTime(start)} – ${_formatTime(end)}\n\n"
          "Any employee will be able to claim this shift, subject to "
          "your approval.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Post"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => creating = true);
    try {
      await ShiftService.postOpenShift(
        companyId: companyId,
        start: start,
        end: end,
        createdBy: managerId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Open shift posted")),
      );

      await load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  // ----------------------------
  // APPROVE / REJECT DIALOG (shift requests — also covers claimed
  // open shifts, since claiming just moves a shift to 'pending')
  // ----------------------------
  Future<void> _reviewShift(ShiftModel shift, EmployeeProfile emp) async {
    final noteController = TextEditingController();

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text("Shift Request — ${emp.displayName}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${_formatTime(shift.startTime)} – ${_formatTime(shift.endTime)}",
              ),
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
        await ShiftService.approveShift(
          shiftId: shift.id,
          managerId: managerId,
          note: note.isEmpty ? null : note,
        );
      } else {
        await ShiftService.rejectShift(
          shiftId: shift.id,
          managerId: managerId,
          note: note.isEmpty ? null : note,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'approve' ? "Shift approved" : "Shift rejected"),
        ),
      );

      await load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e"), backgroundColor: Colors.red),
      );
    }
  }

  // ----------------------------
  // APPROVE / REJECT DIALOG (shift swaps)
  // ----------------------------
  Future<void> _reviewSwap(ShiftModel shift) async {
    final originalEmp = _employeeFor(shift.userId);
    final targetEmp = _employeeFor(shift.swapTargetUserId);

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Shift Swap Approval"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${_formatTime(shift.startTime)} – ${_formatTime(shift.endTime)}"),
              const SizedBox(height: 8),
              Text("Currently: ${originalEmp?.displayName ?? 'Unknown'}"),
              Text("Proposed: ${targetEmp?.displayName ?? 'Unknown'}"),
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

    try {
      if (action == 'approve') {
        await ShiftService.approveSwap(shiftId: shift.id, managerId: managerId);
      } else {
        await ShiftService.rejectSwap(shiftId: shift.id, managerId: managerId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'approve' ? "Swap approved" : "Swap rejected"),
        ),
      );

      await load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e"), backgroundColor: Colors.red),
      );
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  Future<String?> _pickRequiredSkill(List<EmployeeSkill> skills) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text("Required Skill (optional)"),
        children: [
          const SimpleDialogOption(
            onPressed: null,
            child: Text("No required skill"),
          ),
          ...skills.map((s) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, s.id),
                child: Text(s.label),
              )),
        ],
      ),
    );
  }

  // ----------------------------
  // COPY THIS WEEK TO NEXT WEEK (schedule templates)
  // ----------------------------
  Future<void> _copyWeek() async {
    if (creating) return;

    final companyId = SessionService.activeCompanyId;
    final managerId = SessionService.activeUserId;
    if (companyId == null || managerId == null) return;

    final now = DateTime.now();

    // Source = this week (Monday through Sunday).
    final sourceStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - DateTime.monday));
    final sourceEnd = sourceStart.add(const Duration(days: 7));

    // Target = next week.
    final targetStart = sourceStart.add(const Duration(days: 7));
    final targetEnd = sourceEnd.add(const Duration(days: 7));

    final sourceCount = shifts.where((s) {
      return (s.startTime.isAfter(sourceStart) ||
              s.startTime.isAtSameMomentAs(sourceStart)) &&
          (s.startTime.isBefore(sourceEnd) ||
              s.startTime.isAtSameMomentAs(sourceEnd));
    }).length;

    if (sourceCount == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No shifts in the current week to copy"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Copy This Week?"),
        content: Text(
          "Copy $sourceCount shift${sourceCount == 1 ? '' : 's'} from the "
          "current week to next week? Each shift is copied as a fresh "
          "manager-approved schedule entry — conflicts are skipped.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Copy"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => creating = true);

    try {
      final copied = await ShiftService.copyShifts(
        companyId: companyId,
        createdBy: managerId,
        sourceStart: sourceStart,
        sourceEnd: sourceEnd,
        targetStart: targetStart,
        targetEnd: targetEnd,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Copied $copied shift${copied == 1 ? '' : 's'} to next week")),
      );

      await load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  // ----------------------------
  // CREATE (manager scheduling = official, auto-approved, for self)
  // ----------------------------
  Future<void> _create(int day, int hour) async {
    if (creating) return;

    final companyId = SessionService.activeCompanyId;

    // IMPORTANT:
    // This should eventually be selected employee, not current user.
    // Preserved from original manager screen — not fixed in this
    // pass. Long-press now covers "assign to anyone" via open shifts.
    final userId = SessionService.activeUserId;

    if (companyId == null || userId == null) return;

    setState(() => creating = true);

    final now = DateTime.now();

    final start = DateTime(now.year, now.month, now.day, hour)
        .add(Duration(days: day - now.weekday));

    final end = start.add(const Duration(hours: 8));

    try {
      final analysis = await ShiftService.analyzeShift(
        companyId: companyId,
        userId: userId,
        start: start,
        end: end,
      );

      if (!analysis.canCreate) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("This shift conflicts with an existing shift"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Collect advisory warnings in one pass: the standard
      // availability/time-off warning from analyzeShift, plus the
      // new live overtime-risk and labor-budget projections. All are
      // non-blocking — the manager can always proceed.
      final advisoryWarnings = <String>[];

      if (analysis.warning != null) {
        advisoryWarnings.add(analysis.warning!);
      }

      try {
        final overtimeSettings = await OvertimeService.getSettings(companyId);
        final projectedHours = LaborBudgetService.projectedWeeklyHours(
          shifts: shifts,
          newStart: start,
          newEnd: end,
          userId: userId,
        );
        if (LaborBudgetService.crossesOvertimeThreshold(
          projectedHours: projectedHours,
          overtime: overtimeSettings,
        )) {
          advisoryWarnings.add(
            "Projected ${projectedHours.toStringAsFixed(1)} hrs this week — "
            "crosses the ${overtimeSettings.weeklyThresholdHours.toStringAsFixed(0)}-hr "
            "overtime threshold",
          );
        }
      } catch (_) {
        // Projection failed — fail open, don't block scheduling.
      }

      try {
        final budgetSettings =
            await LaborBudgetService.getSettings(companyId);
        final projectedCost = await LaborBudgetService
            .projectedWeeklyLaborCost(
          companyId: companyId,
          shifts: shifts,
          newStart: start,
          newEnd: end,
          userId: userId,
        );
        if (LaborBudgetService.exceedsBudget(
          projectedCost: projectedCost,
          budget: budgetSettings,
        )) {
          advisoryWarnings.add(
            "Projected weekly labor: \$${projectedCost.toStringAsFixed(2)} "
            "(budget \$${budgetSettings.amount.toStringAsFixed(2)})",
          );
        }
      } catch (_) {
        // Projection failed — fail open, don't block scheduling.
      }

      String? requiredSkillId;
      try {
        final allSkills = await EmployeeSkillService.getSkills(companyId);
        if (allSkills.isNotEmpty) {
          requiredSkillId = await _pickRequiredSkill(allSkills);
          if (requiredSkillId != null) {
            final lacksSkill = await EmployeeSkillService.userLacksSkill(
              companyId: companyId,
              userId: userId,
              skillId: requiredSkillId,
            );
            if (lacksSkill) {
              final skill = allSkills.firstWhere((s) => s.id == requiredSkillId);
              final emp = _employeeFor(userId);
              advisoryWarnings.add(
                "${emp?.displayName ?? 'Assigned employee'} lacks required skill: ${skill.label}",
              );
            }
          }
        }
      } catch (_) {
        // Skill check failed — fail open, don't block scheduling.
      }

      if (advisoryWarnings.isNotEmpty) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text("Heads up"),
            content: Text(advisoryWarnings.join("\n\n")),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Schedule Anyway"),
              ),
            ],
          ),
        );

        if (proceed != true) return;
      }

      await ShiftService.createShift(
        companyId: companyId,
        userId: userId,
        start: start,
        end: end,
        createdBy: userId,
        status: 'approved',
        origin: 'manager_scheduled',
        requiredSkillId: requiredSkillId,
      );

      await load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }
}