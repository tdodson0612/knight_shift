// lib/features/time_clock/home_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/session_service.dart';
import '../../core/services/role_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/subscription_service.dart';
import '../../shared/models/subscription_model.dart';
import 'history_screen.dart';
import '../manager/manager_dashboard.dart';
import '../settings/settings_screen.dart';
import '../availability/availability_screen.dart';
import '../time_off/time_off_screen.dart';
import '../notifications/notifications_screen.dart';
import '../scheduling/swap_requests_screen.dart';
import '../incident_reports/incident_report_submit_screen.dart';
import '../../core/services/geofence_service.dart';
import '../../shared/models/geofence_settings_model.dart';
import 'package:geolocator/geolocator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool loading = true;

  bool clockedIn = false;
  String? activeShiftId;
  int unreadCount = 0;
  CompanySubscription? subscription;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    await _loadShiftState();
    await _loadUnreadCount();
    await _loadSubscription();

    if (!mounted) return;
    setState(() => loading = false);
  }

  Future<void> _loadSubscription() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) return;

    try {
      subscription = await SubscriptionService.getSubscription(companyId);
    } catch (_) {
      subscription = null;
    }
  }

  Future<void> _loadUnreadCount() async {
    final companyId = SessionService.activeCompanyId;
    final userId = SessionService.activeUserId;
    if (companyId == null || userId == null) return;

    try {
      unreadCount = await NotificationService.getUnreadCount(
        companyId: companyId,
        userId: userId,
      );
    } catch (_) {
      unreadCount = 0;
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    await _loadUnreadCount();
    if (mounted) setState(() {});
  }

  Future<void> _loadShiftState() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final openShift = await Supabase.instance.client
        .from('time_entries')
        .select()
        .eq('user_id', user.id)
        .isFilter('clock_out', null)
        .maybeSingle();

    if (!mounted) return;

    if (openShift != null) {
      clockedIn = true;
      activeShiftId = openShift['id']?.toString();
    } else {
      clockedIn = false;
      activeShiftId = null;
    }
  }

  Future<bool> _passesGeofenceCheck(String companyId) async {
    GeofenceSettings settings;
    try {
      settings = await GeofenceService.getSettings(companyId);
    } catch (_) {
      return true; // fails open — can't check, don't block clock-in
    }

    if (!settings.enabled || !settings.hasLocationSet) return true;

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "This company requires location to clock in — enable location access",
              ),
            ),
          );
        }
        return false;
      }

      final position = await Geolocator.getCurrentPosition();
      final within = GeofenceService.isWithinGeofence(
        settings: settings,
        currentLat: position.latitude,
        currentLng: position.longitude,
      );

      if (!within && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You're too far from the job site to clock in"),
          ),
        );
      }

      return within;
    } catch (_) {
      // Location unavailable for some other reason (GPS off, etc.)
      // — fail open rather than lock someone out of clocking in.
      return true;
    }
  }

  Future<void> _toggleClock() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final companyId = SessionService.activeCompanyId;

    if (companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No company selected")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      if (!clockedIn) {
        final allowed = await _passesGeofenceCheck(companyId);
        if (!allowed) {
          if (mounted) setState(() => loading = false);
          return;
        }

        final res = await Supabase.instance.client
            .from('time_entries')
            .insert({
              'user_id': user.id,
              'company_id': companyId,
              'clock_in': DateTime.now().toIso8601String(),
            })
            .select()
            .single();

        clockedIn = true;
        activeShiftId = res['id']?.toString();
      } else {
        if (activeShiftId != null) {
          await Supabase.instance.client
              .from('time_entries')
              .update({
                'clock_out': DateTime.now().toIso8601String(),
              })
              .eq('id', activeShiftId!);
        }

        clockedIn = false;
        activeShiftId = null;
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }

    if (!mounted) return;
    setState(() => loading = false);
  }

  void _openIncidentReport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const IncidentReportSubmitScreen()),
    );
    // No reload needed on return — this screen doesn't affect
    // anything shown on HomeScreen. If the company doesn't have
    // incident reporting enabled, IncidentReportSubmitScreen shows
    // that message itself rather than this icon being hidden —
    // keeps HomeScreen from needing an extra settings fetch just to
    // decide whether to show the icon.
  }

  @override
  Widget build(BuildContext context) {
    final role = SessionService.activeRole ?? 'employee';
    final companyName = SessionService.activeCompanyName ?? 'No Company';
    final isManager = RoleService.isManager();

    return Scaffold(
      appBar: AppBar(
        title: Text(companyName),
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
            icon: const Icon(Icons.swap_horiz),
            tooltip: "Swap Requests",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SwapRequestsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.event_available),
            tooltip: "My Availability",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AvailabilityScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.beach_access),
            tooltip: "Time Off",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TimeOffScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.report_outlined),
            tooltip: "Report an Incident",
            onPressed: _openIncidentReport,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: "Shift History",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: "Settings",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (subscription != null && subscription!.isLocked)
                  _lockedBanner(),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Role: $role"),
                        const SizedBox(height: 10),

                        Text(
                          clockedIn ? "ON SHIFT" : "OFF SHIFT",
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 20),

                        ElevatedButton(
                          onPressed: _toggleClock,
                          child: Text(clockedIn ? "Clock Out" : "Clock In"),
                        ),

                        const SizedBox(height: 20),

                        Text(
                          activeShiftId != null
                              ? "Shift active"
                              : "No active shift",
                        ),

                        const SizedBox(height: 30),

                        if (isManager)
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ManagerDashboard(),
                                ),
                              );
                            },
                            child: const Text("Manager Dashboard"),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _lockedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.red.withValues(alpha: 0.1),
      child: const Text(
        "This company's trial has ended. Clocking in/out still works, "
        "but new shift requests are temporarily disabled until a "
        "manager upgrades.",
        style: TextStyle(color: Colors.red, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}