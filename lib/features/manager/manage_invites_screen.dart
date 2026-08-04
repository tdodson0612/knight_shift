// lib/features/manager/manage_invites_screen.dart

import 'package:flutter/material.dart';

import '../../core/services/invite_service.dart';
import '../../core/services/session_service.dart';
import '../../shared/models/company_invite.dart';

class ManageInvitesScreen extends StatefulWidget {
  const ManageInvitesScreen({super.key});

  @override
  State<ManageInvitesScreen> createState() => _ManageInvitesScreenState();
}

class _ManageInvitesScreenState extends State<ManageInvitesScreen> {
  bool loading = true;
  List<CompanyInvite> invites = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) {
      setState(() => loading = false);
      return;
    }

    setState(() => loading = true);

    try {
      final results = await InviteService.getCompanyInvites(companyId);
      if (!mounted) return;
      setState(() {
        invites = results;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading invites: $e")),
      );
    }
  }

  Future<void> _revokeInvite(CompanyInvite invite) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Revoke Invite"),
        content: Text("Revoke the invite sent to ${invite.email}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Revoke"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await InviteService.revokeInvite(invite.id);
      await load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Invite revoked for ${invite.email}")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error revoking invite: $e")),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.green;
      case 'expired':
      case 'revoked':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_empty;
      case 'accepted':
        return Icons.check_circle;
      case 'expired':
        return Icons.timer_off;
      case 'revoked':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Invites"),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: invites.isEmpty
                  ? const Center(
                      child: Text(
                        "No invites sent yet",
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: invites.length,
                      itemBuilder: (context, index) {
                        final invite = invites[index];
                        final isPending = invite.status == 'pending';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              _statusIcon(invite.status),
                              color: _statusColor(invite.status),
                            ),
                            title: Text(invite.email),
                            subtitle: Row(
                              children: [
                                Chip(
                                  label: Text(
                                    invite.status.toUpperCase(),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  backgroundColor: _statusColor(invite.status)
                                      .withValues(alpha: 0.15),
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  invite.role,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                            trailing: isPending
                                ? IconButton(
                                    icon: const Icon(Icons.undo,
                                        color: Colors.red),
                                    tooltip: "Revoke",
                                    onPressed: () =>
                                        _revokeInvite(invite),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}