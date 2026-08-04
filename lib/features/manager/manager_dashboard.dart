// lib/features/manager/manager_dashboard.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/session_service.dart';
import '../../core/services/employee_service.dart';
import '../../core/services/shift_service.dart';
import '../../core/services/payroll_analytics_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/subscription_service.dart';
import '../../core/services/invite_service.dart';

import '../../shared/models/employee_profile.dart';
import '../../shared/models/shift_model.dart';
import '../../shared/models/company_invite.dart';
import '../../shared/models/subscription_model.dart';

import 'scheduling_screen.dart';
import 'manage_invites_screen.dart';
import 'incident_reports_screen.dart';
import 'time_entries_screen.dart';
import 'bulk_import_hub_screen.dart';
import 'company_portfolio_screen.dart';
import 'setup_wizard.dart';
import '../payroll/payroll_screen.dart';
import '../company/employees_screen.dart';
import '../settings/settings_screen.dart';
import '../reports/reports_screen.dart';
import 'time_off_requests_screen.dart';
import '../notifications/notifications_screen.dart';
import '../billing/billing_screen.dart';

class ManagerDashboard extends StatefulWidget {
  const ManagerDashboard({super.key});

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  bool loading = true;
  int unreadCount = 0;
  CompanySubscription? subscription;

  List<EmployeeProfile> employees = [];
  List<CompanyInvite> invites = [];
  List<ShiftModel> shifts = [];

  // Hybrid-reconciled hours (time_entries primary, shifts fallback)
  // for the current week only — a quick-glance summary, not a
  // payroll figure. See PayrollScreen for period-specific payroll.
  final Map<String, double> hoursThisWeek = {};
  final Map<String, EmployeeProfile> employeeMap = {};

  final emailController = TextEditingController();
  String inviteRole = 'employee';
  bool _wizardChecked = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  // ----------------------------
  // LOAD DASHBOARD DATA
  // ----------------------------
  Future<void> load() async {
    final companyId = SessionService.activeCompanyId;

    if (companyId == null) {
      setState(() => loading = false);
      return;
    }

    setState(() => loading = true);

    try {
      final empFuture = EmployeeService.getCompanyEmployees(companyId);

      final invFuture = Supabase.instance.client
          .from('company_invites')
          .select()
          .eq('company_id', companyId)
          .then((r) => List<Map<String, dynamic>>.from(r)
              .map(CompanyInvite.fromMap)
              .toList());

      final shiftFuture = ShiftService.getCompanyShifts(companyId);

      final userId = SessionService.activeUserId;
      final unreadFuture = userId != null
          ? NotificationService.getUnreadCount(
              companyId: companyId, userId: userId)
          : Future.value(0);

      final subFuture = SubscriptionService.getSubscription(companyId);

      final results = await Future.wait([
        empFuture,
        invFuture,
        shiftFuture,
        unreadFuture,
        subFuture,
      ]);

      final empRes = results[0] as List<EmployeeProfile>;
      final invRes = results[1] as List<CompanyInvite>;
      final shiftRes = results[2] as List<ShiftModel>;
      final unreadRes = results[3] as int;
      final subRes = results[4] as CompanySubscription;

      // Current week: Monday through now.
      final now = DateTime.now();
      final weekStart = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - DateTime.monday));

      final weekShifts = shiftRes.where((s) {
        return s.startTime.isAfter(weekStart) ||
            s.startTime.isAtSameMomentAs(weekStart);
      }).toList();

      final hours = await PayrollAnalyticsService.calculateHoursByUser(
        companyId: companyId,
        shifts: weekShifts,
        start: weekStart,
        end: now,
      );

      final map = {
        for (final e in empRes) e.userId: e,
      };

      if (!mounted) return;

      setState(() {
        employees = empRes;
        invites = invRes;
        shifts = shiftRes;
        unreadCount = unreadRes;
        subscription = subRes;

        hoursThisWeek
          ..clear()
          ..addAll(hours);

        employeeMap
          ..clear()
          ..addAll(map);

        loading = false;
      });

      _maybeShowSetupWizard(companyId);
    } catch (e) {
      if (!mounted) return;

      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Dashboard error: $e")),
      );
    }
  }

  // ----------------------------
  // SETUP WIZARD (new, empty companies only)
  // ----------------------------
  Future<void> _maybeShowSetupWizard(String companyId) async {
    if (_wizardChecked) return;
    if (employees.isNotEmpty || shifts.isNotEmpty) return;

    final dismissed = await SetupWizardPrefs.isDismissed(companyId);
    if (dismissed) return;

    _wizardChecked = true; // only ever auto-show once per screen instance
    if (!mounted) return;
    showSetupWizard(context, companyId: companyId);
  }

  // ----------------------------
  // HELPERS
  // ----------------------------
  String nameFor(String? userId) {
    if (userId == null) return "Open Shift";
    return employeeMap[userId]?.displayName ?? "Unknown";
  }

  double totalHours() {
    return hoursThisWeek.values.fold(0, (a, b) => a + b);
  }

  // ----------------------------
  // INVITE EMPLOYEE
  // ----------------------------
  Future<void> sendInvite() async {
    final email = emailController.text.trim();
    final companyId = SessionService.activeCompanyId;

    if (email.isEmpty || companyId == null) return;

    try {
      await InviteService.inviteUser(
        email: email,
        companyId: companyId,
        role: inviteRole,
      );

      emailController.clear();
      setState(() => inviteRole = 'employee');
      await load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e")),
      );
    }
  }

  // ----------------------------
  // NAVIGATION
  // ----------------------------
  void _openScheduling() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ManagerSchedulingScreen(),
      ),
    );
  }

  void _openPayroll() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PayrollScreen(),
      ),
    );
  }

  void _openEmployees() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const EmployeesScreen(),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  void _openReports() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ReportsScreen(),
      ),
    );
  }

  void _openTimeOffRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TimeOffRequestsScreen(),
      ),
    );
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    await load();
  }

  Future<void> _openBilling() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BillingScreen()),
    );
    await load();
  }

  Future<void> _openManageInvites() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManageInvitesScreen()),
    );
    await load();
  }

  Future<void> _openIncidentReports() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const IncidentReportsScreen()),
    );
    await load();
  }

  Future<void> _openTimeEntries() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TimeEntriesScreen()),
    );
    await load();
  }

  Future<void> _openBulkImport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BulkImportHubScreen()),
    );
    await load();
  }

  void _openCompanyPortfolio() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CompanyPortfolioScreen()),
    );
    // No reload-on-return needed: if they switch companies, that
    // pushes a brand new ManagerDashboard (old stack cleared) rather
    // than returning here; if they just go back, nothing changed.
  }

  // ----------------------------
  // UI
  // ----------------------------
  @override
  Widget build(BuildContext context) {
    final companyName =
        SessionService.activeCompanyName ?? "No Company";

    return Scaffold(
      appBar: AppBar(
        title: Text("Manager • $companyName"),
        actions: [
          IconButton(
            icon: Badge(
              label: Text(unreadCount.toString()),
              isLabelVisible: unreadCount > 0,
              child: const Icon(Icons.notifications),
            ),
            tooltip: "Notifications",
            onPressed: _openNotifications,
          ),
          IconButton(
            icon: const Icon(Icons.mail_outline),
            tooltip: "Manage Invites",
            onPressed: _openManageInvites,
          ),
          IconButton(
            icon: const Icon(Icons.report_outlined),
            tooltip: "Incident Reports",
            onPressed: _openIncidentReports,
          ),
          IconButton(
            icon: const Icon(Icons.punch_clock_outlined),
            tooltip: "Time Entries",
            onPressed: _openTimeEntries,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: "Bulk Import Employees",
            onPressed: _openBulkImport,
          ),
          IconButton(
            icon: const Icon(Icons.apartment_outlined),
            tooltip: "My Companies",
            onPressed: _openCompanyPortfolio,
          ),
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: "Employees",
            onPressed: _openEmployees,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: "Scheduling",
            onPressed: _openScheduling,
          ),
          IconButton(
            icon: const Icon(Icons.beach_access),
            tooltip: "Time Off Requests",
            onPressed: _openTimeOffRequests,
          ),
          IconButton(
            icon: const Icon(Icons.payments),
            tooltip: "Payroll",
            onPressed: _openPayroll,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: "Reports",
            onPressed: _openReports,
          ),
          IconButton(
            icon: const Icon(Icons.credit_card),
            tooltip: "Billing",
            onPressed: _openBilling,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: "Settings",
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: load,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (subscription != null) _subscriptionBanner(subscription!),
                  _summaryRow(),
                  const SizedBox(height: 20),
                  _inviteBox(),
                  const SizedBox(height: 20),
                  _employeesList(),
                  const SizedBox(height: 20),
                  _invitesList(),
                  const SizedBox(height: 20),
                  _shiftsList(),
                ],
              ),
            ),
    );
  }

  // ----------------------------
  // SUBSCRIPTION BANNER
  // ----------------------------
  Widget _subscriptionBanner(CompanySubscription s) {
    if (s.isLocked) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock, color: Colors.red),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Your trial has ended. Scheduling, payroll generation, "
                "and invites are disabled. Your data is safe and fully visible.",
                style: TextStyle(color: Colors.red),
              ),
            ),
            TextButton(
              onPressed: _openBilling,
              child: const Text("Upgrade"),
            ),
          ],
        ),
      );
    }

    if (s.isTrialing && s.daysLeftInTrial <= 7) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "${s.daysLeftInTrial} day${s.daysLeftInTrial == 1 ? '' : 's'} left in your free trial.",
                style: const TextStyle(color: Colors.orange),
              ),
            ),
            TextButton(
              onPressed: _openBilling,
              child: const Text("View Plans"),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ----------------------------
  // SUMMARY CARDS
  // ----------------------------
  Widget _summaryRow() {
    return Row(
      children: [
        _card("Employees", employees.length.toString()),
        _card("Invites", invites.length.toString()),
        _card("Hours (This Week)", totalHours().toStringAsFixed(1)),
      ],
    );
  }

  Widget _card(String title, String value) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      );

  // ----------------------------
  // INVITE BOX
  // ----------------------------
  Widget _inviteBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Invite Someone",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        TextField(
          controller: emailController,
          decoration: const InputDecoration(hintText: "Email"),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: inviteRole,
          decoration: const InputDecoration(
            labelText: "Role",
            border: OutlineInputBorder(),
            isDense: true,
          ),
          // 'admin' deliberately excluded from this casual invite
          // box — granting full admin should be a more deliberate
          // action than a quick email + role pick.
          items: const [
            DropdownMenuItem(value: 'employee', child: Text("Employee")),
            DropdownMenuItem(value: 'manager', child: Text("Manager")),
            DropdownMenuItem(
                value: 'accountant', child: Text("Accountant (read-only payroll)")),
          ],
          onChanged: (v) => setState(() => inviteRole = v ?? 'employee'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: sendInvite,
          child: const Text("Send Invite"),
        ),
      ],
    );
  }

  // ----------------------------
  // EMPLOYEES
  // ----------------------------
  Widget _employeesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Employees",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        if (employees.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text("No employees yet", style: TextStyle(color: Colors.grey)),
          )
        else
          ...employees.map((e) => ListTile(
                leading: CircleAvatar(
                  child: Text(e.initials),
                ),
                title: Text(e.displayName),
                subtitle: Text(e.role),
              )),
      ],
    );
  }

  // ----------------------------
  // INVITES
  // ----------------------------
  Widget _invitesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Invites",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        if (invites.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text("No pending invites", style: TextStyle(color: Colors.grey)),
          )
        else
          ...invites.map((i) => ListTile(
                leading: const Icon(Icons.mail),
                title: Text(i.email),
                subtitle: Text(i.status),
              )),
      ],
    );
  }

  // ----------------------------
  // SHIFTS
  // ----------------------------
  Widget _shiftsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Shifts",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        if (shifts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text("No shifts scheduled yet", style: TextStyle(color: Colors.grey)),
          )
        else
          ...shifts.take(15).map((s) => ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(nameFor(s.userId)),
                subtitle: Text(
                  "In: ${s.startTime} • Out: ${s.endTime}",
                ),
              )),
      ],
    );
  }
}