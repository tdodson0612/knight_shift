// lib/features/notifications/notifications_screen.dart

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/shift_service.dart';
import '../../shared/models/notification_model.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool loading = true;
  List<NotificationModel> notifications = [];

  // Tracks which notification is mid-action, so its buttons disable
  // individually rather than blocking the whole list.
  String? _actingOnId;

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
      notifications = await NotificationService.getMyNotifications(
        companyId: companyId,
        userId: userId,
      );
    } catch (_) {
      notifications = [];
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> _markAllRead() async {
    final companyId = SessionService.activeCompanyId;
    final userId = SessionService.activeUserId;
    if (companyId == null || userId == null) return;

    await NotificationService.markAllAsRead(companyId: companyId, userId: userId);
    await _load();
  }

  Future<void> _tap(NotificationModel n) async {
    if (n.isUnread) {
      await NotificationService.markAsRead(n.id);
      await _load();
    }
  }

  // ----------------------------
  // ONE-TAP SWAP ACCEPT/DECLINE
  // ----------------------------
  Future<void> _respondToSwap(NotificationModel n, bool accept) async {
    final userId = SessionService.activeUserId;
    if (userId == null || n.relatedId == null) return;

    setState(() => _actingOnId = n.id);

    try {
      await ShiftService.respondToSwap(
        shiftId: n.relatedId!,
        targetUserId: userId,
        accept: accept,
      );

      await NotificationService.markAsRead(n.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? "Swap accepted" : "Swap declined")),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _actingOnId = null);
    }
  }

  String _timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return "just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    return "${diff.inDays}d ago";
  }

  bool _isActionableSwap(NotificationModel n) {
    return n.type == 'swap_requested' && n.relatedId != null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: "Mark all as read",
            onPressed: _markAllRead,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : notifications.isEmpty
              ? const Center(child: Text("No notifications yet"))
              : ListView.builder(
                  itemCount: notifications.length,
                  itemBuilder: (context, i) {
                    final n = notifications[i];

                    if (_isActionableSwap(n)) {
                      return _swapRequestTile(n);
                    }

                    return ListTile(
                      tileColor: n.isUnread
                          ? Colors.blue.withValues(alpha: 0.06)
                          : null,
                      leading: Icon(
                        n.isUnread ? Icons.circle : Icons.circle_outlined,
                        size: 10,
                        color: n.isUnread ? Colors.blue : Colors.grey,
                      ),
                      title: Text(
                        n.title,
                        style: TextStyle(
                          fontWeight:
                              n.isUnread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: n.body != null ? Text(n.body!) : null,
                      trailing: Text(
                        _timeAgo(n.createdAt),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      onTap: () => _tap(n),
                    );
                  },
                ),
    );
  }

  Widget _swapRequestTile(NotificationModel n) {
    final acting = _actingOnId == n.id;

    return Container(
      color: n.isUnread ? Colors.blue.withValues(alpha: 0.06) : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                n.isUnread ? Icons.circle : Icons.circle_outlined,
                size: 10,
                color: n.isUnread ? Colors.blue : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  n.title,
                  style: TextStyle(
                    fontWeight:
                        n.isUnread ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              Text(
                _timeAgo(n.createdAt),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          if (n.body != null)
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 2),
              child: Text(n.body!, style: const TextStyle(fontSize: 13)),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 18, top: 6),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: acting ? null : () => _respondToSwap(n, true),
                  child: Text(acting ? "..." : "Accept"),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: acting ? null : () => _respondToSwap(n, false),
                  child: const Text("Decline"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}