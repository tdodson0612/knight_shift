  // lib/features/scheduling/scheduling_screen.dart

  import 'package:flutter/material.dart';

  import '../../core/services/session_service.dart';
  import '../../core/services/shift_service.dart';
  import '../../core/services/employee_service.dart';

  import '../../shared/models/shift_model.dart';
  import '../../shared/models/employee_profile.dart';

  class SchedulingScreen extends StatefulWidget {
    const SchedulingScreen({super.key});

    @override
    State<SchedulingScreen> createState() => _SchedulingScreenState();
  }

  class _SchedulingScreenState extends State<SchedulingScreen> {
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
          title: const Text("My Schedule"),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: load,
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : _buildGrid(),
      );
    }

    Widget _buildGrid() {
      return Column(
        children: [
          _header(),
          Expanded(
            child: Row(
              children: List.generate(7, (day) => Expanded(child: _day(day))),
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
                onTap: () => _requestShift(dayIndex, hour),
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

    Widget _shift(ShiftModel s) {
      final start = s.startTime;
      final end = s.endTime;

      final top = ((start.hour - startHour) * 60 + start.minute).toDouble();
      final height = end.difference(start).inMinutes.toDouble();

      final currentUserId = SessionService.activeUserId;

      final label = s.isOpen
          ? "Open Shift"
          : employees
              .firstWhere(
                (e) => e.userId == s.userId,
                orElse: () => EmployeeProfile(
                  userId: s.userId ?? '',
                  companyId: '',
                  role: 'employee',
                  displayName: s.userId ?? 'Unknown',
                  email: '',
                ),
              )
              .displayName;

      final isOwnApprovedFutureShift = currentUserId != null &&
          s.userId == currentUserId &&
          s.isApproved &&
          s.startTime.isAfter(DateTime.now());

      final block = Container(
        height: height,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _statusColor(s),
          borderRadius: BorderRadius.circular(6),
          border: s.isOpen
              ? Border.all(color: Colors.teal, style: BorderStyle.solid, width: 1.5)
              : null,
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
      if (s.isOpen) {
        onTap = () => _claimShift(s);
      } else if (isOwnApprovedFutureShift) {
        onTap = () => _offerSwap(s);
      }

      return Positioned(
        top: top,
        left: 4,
        right: 4,
        child: onTap != null
            ? GestureDetector(onTap: onTap, child: block)
            : block,
      );
    }

    // ----------------------------
    // CLAIM AN OPEN SHIFT
    // ----------------------------
    Future<void> _claimShift(ShiftModel shift) async {
      final userId = SessionService.activeUserId;
      if (userId == null) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text("Claim This Shift?"),
          content: Text(
            "${_formatDateTime(shift.startTime)} – ${_formatDateTime(shift.endTime)}\n\n"
            "This will be submitted to your manager for approval.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Claim"),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      try {
        await ShiftService.claimOpenShift(
          shiftId: shift.id,
          claimingUserId: userId,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Shift claimed — awaiting approval")),
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
    // REQUEST SWAP (on your own approved, future shift)
    // ----------------------------
    Future<void> _offerSwap(ShiftModel shift) async {
      final currentUserId = SessionService.activeUserId;
      final coworkers =
          employees.where((e) => e.userId != currentUserId).toList();

      if (coworkers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No coworkers available to swap with")),
        );
        return;
      }

      final target = await showDialog<EmployeeProfile>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text("Request Swap"),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: coworkers.length,
                itemBuilder: (context, i) {
                  final e = coworkers[i];
                  return ListTile(
                    leading: CircleAvatar(child: Text(e.initials)),
                    title: Text(e.displayName),
                    onTap: () => Navigator.pop(dialogContext, e),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("Cancel"),
              ),
            ],
          );
        },
      );

      if (target == null || currentUserId == null) return;

      try {
        await ShiftService.requestSwap(
          shiftId: shift.id,
          requestingUserId: currentUserId,
          targetUserId: target.userId,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Swap proposed to ${target.displayName}")),
        );

        await load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$e"), backgroundColor: Colors.red),
        );
      }
    }

    Future<void> _requestShift(int day, int hour) async {
      if (creating) return;

      final companyId = SessionService.activeCompanyId;
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
              content: Text("Shift conflict detected"),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        await ShiftService.createShift(
          companyId: companyId,
          userId: userId,
          start: start,
          end: end,
          createdBy: userId,
          status: 'pending',
          origin: 'employee_request',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Shift request sent")),
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

    String _formatDateTime(DateTime dt) {
      return "${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    }
  }