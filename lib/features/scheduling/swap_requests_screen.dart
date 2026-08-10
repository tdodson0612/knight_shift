// lib/features/scheduling/swap_requests_screen.dart

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/shift_service.dart';
import '../../core/services/employee_service.dart';
import '../../shared/models/shift_model.dart';
import '../../shared/models/employee_profile.dart';

class SwapRequestsScreen extends StatefulWidget {
  const SwapRequestsScreen({super.key});

  @override
  State<SwapRequestsScreen> createState() => _SwapRequestsScreenState();
}

class _SwapRequestsScreenState extends State<SwapRequestsScreen> {
  bool loading = true;
  List<ShiftModel> incoming = [];
  List<EmployeeProfile> employees = [];

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
      final results = await Future.wait([
        ShiftService.getCompanyShifts(companyId),
        EmployeeService.getCompanyEmployees(companyId),
      ]);

      final allShifts = results[0] as List<ShiftModel>;
      employees = results[1] as List<EmployeeProfile>;

      incoming = allShifts
          .where((s) => s.isSwapRequested && s.swapTargetUserId == userId)
          .toList();
    } catch (_) {
      incoming = [];
      employees = [];
    }

    if (mounted) setState(() => loading = false);
  }

  String _nameFor(String? userId) {
    if (userId == null) return 'A coworker';
    return employees
        .firstWhere(
          (e) => e.userId == userId,
          orElse: () => EmployeeProfile(
            userId: userId,
            companyId: '',
            displayName: 'A coworker',
            email: '',
            role: 'employee',
          ),
        )
        .displayName;
  }

  Future<void> _respond(ShiftModel shift, bool accept) async {
    final userId = SessionService.activeUserId;
    if (userId == null) return;

    try {
      await ShiftService.respondToSwap(
        shiftId: shift.id,
        targetUserId: userId,
        accept: accept,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? "Swap accepted — awaiting manager approval"
                : "Swap declined",
          ),
        ),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e"), backgroundColor: Colors.red),
      );
    }
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Swap Requests"),
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
          : incoming.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.swap_horiz_outlined, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          "No incoming swap requests",
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: incoming.length,
                    itemBuilder: (context, i) {
                      final shift = incoming[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            "${_nameFor(shift.userId)} wants to swap",
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            "${_formatDateTime(shift.startTime)} – ${_formatDateTime(shift.endTime)}",
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close_outlined, color: Colors.red),
                                tooltip: "Decline",
                                onPressed: () => _respond(shift, false),
                              ),
                              IconButton(
                                icon: const Icon(Icons.check_outlined, color: Colors.green),
                                tooltip: "Accept",
                                onPressed: () => _respond(shift, true),
                              ),
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