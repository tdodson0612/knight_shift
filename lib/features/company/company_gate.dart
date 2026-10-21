// lib/features/company/company_gate.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/session_service.dart';
import '../../core/services/role_service.dart';
import '../../core/services/invite_service.dart';
import '../../core/utils/friendly_error.dart';
import '../../shared/models/company_invite.dart';
import '../manager/manager_dashboard.dart';
import '../time_clock/home_screen.dart';
import '../accountant/accountant_view_screen.dart';
import 'company_selection_screen.dart';
import '../auth/login_screen.dart';

class CompanyGate extends StatefulWidget {
  const CompanyGate({super.key});

  @override
  State<CompanyGate> createState() => _CompanyGateState();
}

class _CompanyGateState extends State<CompanyGate> {
  bool loading = true;
  String? acceptingInviteId;

  List<CompanyInvite> pendingInvites = [];

  @override
  void initState() {
    super.initState();
    boot();
  }

  Future<void> boot() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) {
        if (mounted) setState(() => loading = false);
        return;
      }

      await SessionService.restoreSession();

      final userId = user.id;

      final companyId = SessionService.activeCompanyId;

      if (companyId == null) {
        await loadInvites();
        if (mounted) setState(() => loading = false);
        return;
      }

      await RoleService.syncRole(
        companyId: companyId,
        userId: userId,
      );

      if (mounted) setState(() => loading = false);
    } catch (e) {
      debugPrint('CompanyGate boot skipped: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadInvites() async {
    pendingInvites = await InviteService.getMyInvites();
  }

  Future<void> acceptInvite(CompanyInvite invite) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || acceptingInviteId != null) return;

    setState(() => acceptingInviteId = invite.id);

    try {
      final joined = await InviteService.acceptInvite(invite.id);

      await SessionService.setActiveCompany(
        companyId: joined.companyId,
        companyName: joined.companyName,
        role: joined.role,
        userId: user.id,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CompanyGate()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => acceptingInviteId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  // ----------------------------
  // NAVIGATION
  // ----------------------------
  void _openCompanySelection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CompanySelectionScreen(),
      ),
    );
  }

  void _openLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
    // LoginScreen navigates back to a fresh CompanyGate on success,
    // so this gate re-runs boot() and re-branches correctly once
    // someone's actually signed in.
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    User? user;
    try {
      user = Supabase.instance.client.auth.currentUser;
    } catch (e) {
      debugPrint('CompanyGate build: Supabase not initialized — $e');
      user = null;
    }

    // ----------------------------
    // NOT AUTHENTICATED — previously a dead end with no way back
    // into the app. Now routes to the real LoginScreen, which
    // already existed and worked, but was never wired in anywhere.
    // ----------------------------
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  "You've been signed out.",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _openLogin,
                  child: const Text("Sign In"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final companyId = SessionService.activeCompanyId;

    // ----------------------------
    // NO COMPANY → ONBOARDING STATE
    // ----------------------------
    if (companyId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Join a Company")),
        body: pendingInvites.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "No invites found.\nAsk a manager to invite you, or create your own company.",
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _openCompanySelection,
                        child: const Text("Create a Company"),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                itemCount: pendingInvites.length,
                itemBuilder: (context, index) {
                  final invite = pendingInvites[index];

                  return ListTile(
                    leading: const Icon(Icons.mail),
                    title: Text(invite.companyName ?? 'Company'),
                    subtitle: Text("Role: ${invite.role}"),
                    trailing: ElevatedButton(
                      onPressed: acceptingInviteId == null
                          ? () => acceptInvite(invite)
                          : null,
                      child: Text(
                        acceptingInviteId == invite.id ? "Joining..." : "Accept",
                      ),
                    ),
                  );
                },
              ),
      );
    }

    // ----------------------------
    // ROLE ROUTING
    // ----------------------------
    final isManager = RoleService.isManager();

    if (isManager) {
      return const ManagerDashboard();
    }

    // Read-only bookkeeper seat — checked before the generic
    // employee fallback. Landing an accountant on HomeScreen would
    // be wrong (clock-in/out and a "Manager Dashboard" button don't
    // apply to them).
    if (RoleService.isAccountant()) {
      return const AccountantViewScreen();
    }

    return const HomeScreen();
  }
}