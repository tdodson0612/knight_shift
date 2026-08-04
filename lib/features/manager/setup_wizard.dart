// lib/features/manager/setup_wizard.dart
//
// Guided walkthrough shown once on a brand-new, empty company
// (0 employees, 0 shifts) — see ManagerDashboard for the trigger
// logic. Each step's action pushes the REAL screen (Employees,
// Scheduling, Settings) rather than being a mockup. No new database
// column: "don't show again" is stored locally via SharedPreferences,
// keyed per company, since the failure mode of forgetting on a new
// device (seeing it once more) is harmless — not worth a migration.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/overtime_service.dart';
import '../../core/services/reliability_service.dart';
import '../../core/services/incident_report_service.dart';
import '../../core/services/geofence_service.dart';
import '../../shared/models/overtime_settings_model.dart';
import '../../shared/models/reliability_settings_model.dart';
import '../../shared/models/incident_report_model.dart';
import '../../shared/models/geofence_settings_model.dart';

import 'scheduling_screen.dart';

class SetupWizardPrefs {
  static String _key(String companyId) => 'setup_wizard_dismissed_$companyId';

  static Future<bool> isDismissed(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(companyId)) ?? false;
  }

  static Future<void> dismiss(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(companyId), true);
  }
}

class _WizardStep {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final WidgetBuilder? destination; // null = no navigation, just info

  const _WizardStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    this.destination,
  });
}

final List<_WizardStep> _steps = [
  const _WizardStep(
    icon: Icons.people_outline,
    title: "Add your team",
    body: "Invite employees one at a time from the dashboard, or bring "
        "in a whole team at once with Bulk Import.",
    actionLabel: "Go to Employees",
    destination: null, // handled specially — see below
  ),
  _WizardStep(
    icon: Icons.calendar_month_outlined,
    title: "Build your schedule",
    body: "Create shifts, post open shifts anyone can claim, and let "
        "employees request the ones they want.",
    actionLabel: "Open Scheduling",
    destination: (_) => const ManagerSchedulingScreen(),
  ),
  // Third page is NOT in this generic list — it's the dedicated
  // _FeatureTogglesPage widget below, special-cased in the sheet
  // (same pattern NotificationsScreen uses for swap-request tiles:
  // a custom widget replacing the generic template for one item).
];

const int _totalPages = 3; // 2 generic _steps + 1 feature-toggle page

Future<void> showSetupWizard(BuildContext context, {required String companyId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    builder: (_) => _SetupWizardSheet(companyId: companyId),
  );
}

class _SetupWizardSheet extends StatefulWidget {
  final String companyId;
  const _SetupWizardSheet({required this.companyId});

  @override
  State<_SetupWizardSheet> createState() => _SetupWizardSheetState();
}

class _SetupWizardSheetState extends State<_SetupWizardSheet> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _dismissForever() {
    SetupWizardPrefs.dismiss(widget.companyId);
    Navigator.pop(context);
  }

  void _goToStep(_WizardStep step) {
    Navigator.pop(context); // close the sheet first

    if (step.destination != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: step.destination!),
      );
    } else {
      // Step 1 (Employees) has no dedicated screen of its own to
      // push to — the invite box lives directly on the dashboard.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Look for "Invite Someone" on your dashboard'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Getting Started",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  tooltip: "Skip for now",
                ),
              ],
            ),
            SizedBox(
              height: 320,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _totalPages,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
                  // Last page is the dedicated feature-toggle widget,
                  // not one of the generic _steps.
                  if (index == _steps.length) {
                    return _FeatureTogglesPage(companyId: widget.companyId);
                  }

                  final step = _steps[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(step.icon, size: 48, color: Theme.of(context).primaryColor),
                        const SizedBox(height: 16),
                        Text(
                          step.title,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          step.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 20),
                        OutlinedButton(
                          onPressed: () => _goToStep(step),
                          child: Text(step.actionLabel),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalPages, (i) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page
                        ? Theme.of(context).primaryColor
                        : Colors.grey[300],
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            if (_page == _totalPages - 1)
              TextButton(
                onPressed: _dismissForever,
                child: const Text("Don't show this again"),
              ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------
// FEATURE TOGGLES PAGE
//
// Toggling here writes the SAME `enabled` flag Settings itself
// writes — nothing special-cased, no separate storage. A manager can
// come back to Settings later and change any of this exactly like
// they'd change anything else; the wizard is just a faster first
// pass, not a separate system.
// ----------------------------
class _FeatureTogglesPage extends StatefulWidget {
  final String companyId;
  const _FeatureTogglesPage({required this.companyId});

  @override
  State<_FeatureTogglesPage> createState() => _FeatureTogglesPageState();
}

class _FeatureTogglesPageState extends State<_FeatureTogglesPage> {
  bool loading = true;
  OvertimeSettings? overtime;
  ReliabilitySettings? reliability;
  IncidentReportSettings? incidentReports;
  GeofenceSettings? geofence;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        OvertimeService.getSettings(widget.companyId),
        ReliabilityService.getSettings(widget.companyId),
        IncidentReportService.getSettings(widget.companyId),
        GeofenceService.getSettings(widget.companyId),
      ]);
      overtime = results[0] as OvertimeSettings;
      reliability = results[1] as ReliabilitySettings;
      incidentReports = results[2] as IncidentReportSettings;
      geofence = results[3] as GeofenceSettings;
    } catch (_) {
      // Leave whichever ones failed null — that toggle just won't
      // render rather than crashing the whole wizard.
    }
    if (mounted) setState(() => loading = false);
  }

  // The wizard's single "Overtime Rules" switch turns on just the
  // weekly threshold (the more common default) — a manager wanting
  // daily, both, or to tune the multiplier goes to Settings, same as
  // any other later change.
  Future<void> _toggleOvertime(bool v) async {
    final updated = overtime!.copyWith(weeklyEnabled: v);
    setState(() => overtime = updated);
    await OvertimeService.updateSettings(companyId: widget.companyId, settings: updated);
  }

  Future<void> _toggleReliability(bool v) async {
    final updated = reliability!.copyWith(enabled: v);
    setState(() => reliability = updated);
    await ReliabilityService.updateSettings(companyId: widget.companyId, settings: updated);
  }

  Future<void> _toggleIncidentReports(bool v) async {
    final updated = incidentReports!.copyWith(enabled: v);
    setState(() => incidentReports = updated);
    await IncidentReportService.updateSettings(companyId: widget.companyId, settings: updated);
  }

  Future<void> _toggleGeofence(bool v) async {
    // Geofencing additionally needs a location before it can actually
    // enforce anything — the toggle here just opts in; the manager
    // still needs to set a location in Settings for it to take effect
    // (GeofenceService.isWithinGeofence passes everyone through until
    // a location exists, so this is safe to flip here regardless).
    final updated = geofence!.copyWith(enabled: v);
    setState(() => geofence = updated);
    await GeofenceService.updateSettings(companyId: widget.companyId, settings: updated);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 8),
          Icon(Icons.tune, size: 40, color: Theme.of(context).primaryColor),
          const SizedBox(height: 8),
          const Text(
            "Turn on what fits your business",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            "Everything here is off by default and fully changeable "
            "later in Settings.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (overtime != null)
            SwitchListTile(
              dense: true,
              title: const Text("Overtime Rules", style: TextStyle(fontSize: 13)),
              value: overtime!.weeklyEnabled,
              onChanged: _toggleOvertime,
            ),
          if (reliability != null)
            SwitchListTile(
              dense: true,
              title: const Text("Reliability Tracking", style: TextStyle(fontSize: 13)),
              value: reliability!.enabled,
              onChanged: _toggleReliability,
            ),
          if (incidentReports != null)
            SwitchListTile(
              dense: true,
              title: const Text("Incident Reports", style: TextStyle(fontSize: 13)),
              value: incidentReports!.enabled,
              onChanged: _toggleIncidentReports,
            ),
          if (geofence != null)
            SwitchListTile(
              dense: true,
              title: const Text("Geofenced Clock-In", style: TextStyle(fontSize: 13)),
              value: geofence!.enabled,
              onChanged: _toggleGeofence,
            ),
        ],
      ),
    );
  }
}