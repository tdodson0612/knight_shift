// lib/features/settings/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/session_service.dart';
import '../../core/services/employee_service.dart';
import '../../core/services/role_service.dart';
import '../../core/services/overtime_service.dart';
import '../../core/services/reliability_service.dart';
import '../../core/services/incident_report_service.dart';
import '../../core/services/geofence_service.dart';
import '../../shared/models/geofence_settings_model.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/services/shift_comment_service.dart';
import '../../core/services/shift_checklist_service.dart';
import '../../core/services/clock_in_photo_service.dart';
import '../../shared/models/shift_checklist_model.dart';
import '../legal/legal_reference_screen.dart';
import '../../core/services/labor_budget_service.dart';
import '../../shared/models/labor_budget_settings_model.dart';
import '../../core/services/employee_skill_service.dart';
import '../../shared/models/employee_skill_model.dart';
import '../../core/services/supabase_service.dart';
import '../../shared/models/employee_profile.dart';
import '../../shared/models/overtime_settings_model.dart';
import '../../shared/models/reliability_settings_model.dart';
import '../../shared/models/incident_report_model.dart';
import '../splash/splash_router.dart';

// Static — not read from package_info_plus (no such dependency exists
// in this project yet). Keep in sync with pubspec.yaml's `version:`
// manually until/unless a dynamic version display is requested.
const String _appVersion = "1.0.0+1";

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool loading = true;
  EmployeeProfile? profile;

  // Manager-only overtime settings state.
  OvertimeSettings? overtimeSettings;
  bool savingOvertime = false;
  late final TextEditingController _dailyController;
  late final TextEditingController _weeklyController;
  late final TextEditingController _multiplierController;

  // Manager-only reliability settings state.
  ReliabilitySettings? reliabilitySettings;
  bool savingReliability = false;
  late final TextEditingController _graceController;
  late final TextEditingController _flatPointsController;
  late final TextEditingController _weightLateController;
  late final TextEditingController _weightEarlyController;
  late final TextEditingController _weightNoShowController;

  // Manager-only incident report settings state.
  IncidentReportSettings? incidentReportSettings;
  bool savingIncidentReports = false;

  // Manager-only geofence settings state.
  GeofenceSettings? geofenceSettings;
  bool savingGeofence = false;
  bool locatingNow = false;
  late final TextEditingController _radiusController;

  // Manager-only labor budget state.
  LaborBudgetSettings? laborBudgetSettings;
  bool savingLaborBudget = false;
  late final TextEditingController _laborBudgetController;

  // Manager-only skills state.
  List<EmployeeSkill> skills = [];
  bool skillsEnabled = false; // presence of the section is the "enabled" signal
  bool savingSkills = false;
  late final TextEditingController _newSkillController;

  // Manager-only open-shift priority state.
  String? openShiftPriority; // 'first_come' | 'seniority_first'
  bool savingOpenShiftPriority = false;

  // Manager-only shift comments / checklist state.
  bool? shiftCommentsEnabled;
  bool? shiftChecklistsEnabled;
  List<ShiftChecklistItem> checklistItems = [];
  late final TextEditingController _newChecklistItemController;
  bool savingShiftExtras = false;

  // Manager-only photo-at-clock-in state.
  bool? clockInPhotoEnabled;

  @override
  void initState() {
    super.initState();
    _dailyController = TextEditingController();
    _weeklyController = TextEditingController();
    _multiplierController = TextEditingController();
    _graceController = TextEditingController();
    _flatPointsController = TextEditingController();
    _weightLateController = TextEditingController();
    _weightEarlyController = TextEditingController();
    _weightNoShowController = TextEditingController();
    _radiusController = TextEditingController();
    _laborBudgetController = TextEditingController();
    _newSkillController = TextEditingController();
    _newChecklistItemController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _dailyController.dispose();
    _weeklyController.dispose();
    _multiplierController.dispose();
    _graceController.dispose();
    _flatPointsController.dispose();
    _weightLateController.dispose();
    _weightEarlyController.dispose();
    _weightNoShowController.dispose();
    _radiusController.dispose();
    _newChecklistItemController.dispose();
    _laborBudgetController.dispose();
    _newSkillController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final companyId = SessionService.activeCompanyId;
    final userId = SessionService.activeUserId;

    if (companyId == null || userId == null) {
      setState(() => loading = false);
      return;
    }

    try {
      profile = await EmployeeService.getEmployee(companyId, userId);
    } catch (_) {
      profile = null;
    }

    if (RoleService.isManager()) {
      try {
        overtimeSettings = await OvertimeService.getSettings(companyId);
        _syncOvertimeControllers();
      } catch (_) {
        overtimeSettings = null;
      }

      try {
        reliabilitySettings = await ReliabilityService.getSettings(companyId);
        _syncReliabilityControllers();
      } catch (_) {
        reliabilitySettings = null;
      }

      try {
        incidentReportSettings =
            await IncidentReportService.getSettings(companyId);
      } catch (_) {
        incidentReportSettings = null;
      }

      try {
        geofenceSettings = await GeofenceService.getSettings(companyId);
        _radiusController.text = geofenceSettings!.radiusMeters.toStringAsFixed(0);
      } catch (_) {
        geofenceSettings = null;
      }

      try {
        shiftCommentsEnabled = await ShiftCommentService.isEnabled(companyId);
        shiftChecklistsEnabled = await ShiftChecklistService.isEnabled(companyId);
        checklistItems = await ShiftChecklistService.getItems(companyId);
      } catch (_) {
        shiftCommentsEnabled = null;
        shiftChecklistsEnabled = null;
      }

      try {
        clockInPhotoEnabled = await ClockInPhotoService.isRequired(companyId);
      } catch (_) {
        clockInPhotoEnabled = null;
      }

      try {
        laborBudgetSettings = await LaborBudgetService.getSettings(companyId);
        _laborBudgetController.text =
            laborBudgetSettings!.amount.toStringAsFixed(2);
      } catch (_) {
        laborBudgetSettings = null;
      }

      try {
        skills = await EmployeeSkillService.getSkills(companyId);
        skillsEnabled = true;
      } catch (_) {
        skills = [];
        skillsEnabled = false;
      }

      try {
        final res = await SupabaseService.client
            .from('companies')
            .select('open_shift_priority')
            .eq('id', companyId)
            .single();
        openShiftPriority = res['open_shift_priority']?.toString() ?? 'first_come';
      } catch (_) {
        openShiftPriority = null;
      }
    }

    if (mounted) setState(() => loading = false);
  }

  void _syncOvertimeControllers() {
    final s = overtimeSettings;
    if (s == null) return;
    _dailyController.text = s.dailyThresholdHours.toString();
    _weeklyController.text = s.weeklyThresholdHours.toString();
    _multiplierController.text = s.multiplier.toString();
  }

  void _syncReliabilityControllers() {
    final s = reliabilitySettings;
    if (s == null) return;
    _graceController.text = s.graceMinutes.toString();
    _flatPointsController.text = s.flatPoints.toString();
    _weightLateController.text = s.weightLate.toString();
    _weightEarlyController.text = s.weightEarlyLeave.toString();
    _weightNoShowController.text = s.weightNoShow.toString();
  }

  Future<void> _saveOvertimeSettings() async {
    final companyId = SessionService.activeCompanyId;
    final s = overtimeSettings;
    if (companyId == null || s == null) return;

    final daily = double.tryParse(_dailyController.text.trim());
    final weekly = double.tryParse(_weeklyController.text.trim());
    final multiplier = double.tryParse(_multiplierController.text.trim());

    if (daily == null || daily <= 0) {
      _error("Daily threshold must be a positive number");
      return;
    }
    if (weekly == null || weekly <= 0) {
      _error("Weekly threshold must be a positive number");
      return;
    }
    if (multiplier == null || multiplier <= 0) {
      _error("Overtime multiplier must be a positive number");
      return;
    }

    final updated = s.copyWith(
      dailyThresholdHours: daily,
      weeklyThresholdHours: weekly,
      multiplier: multiplier,
    );

    setState(() => savingOvertime = true);

    try {
      await OvertimeService.updateSettings(
        companyId: companyId,
        settings: updated,
      );

      if (!mounted) return;
      setState(() => overtimeSettings = updated);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Overtime settings saved")),
      );
    } catch (e) {
      _error("Couldn't save overtime settings: $e");
    } finally {
      if (mounted) setState(() => savingOvertime = false);
    }
  }

  Future<void> _saveReliabilitySettings() async {
    final companyId = SessionService.activeCompanyId;
    final s = reliabilitySettings;
    if (companyId == null || s == null) return;

    final grace = int.tryParse(_graceController.text.trim());
    final flat = double.tryParse(_flatPointsController.text.trim());
    final wLate = double.tryParse(_weightLateController.text.trim());
    final wEarly = double.tryParse(_weightEarlyController.text.trim());
    final wNoShow = double.tryParse(_weightNoShowController.text.trim());

    if (grace == null || grace < 0) {
      _error("Grace period must be zero or a positive number of minutes");
      return;
    }
    if (!s.isWeighted && (flat == null || flat < 0)) {
      _error("Points per infraction must be zero or a positive number");
      return;
    }
    if (s.isWeighted &&
        (wLate == null ||
            wLate < 0 ||
            wEarly == null ||
            wEarly < 0 ||
            wNoShow == null ||
            wNoShow < 0)) {
      _error("All three weights must be zero or a positive number");
      return;
    }

    final updated = s.copyWith(
      graceMinutes: grace,
      flatPoints: flat ?? s.flatPoints,
      weightLate: wLate ?? s.weightLate,
      weightEarlyLeave: wEarly ?? s.weightEarlyLeave,
      weightNoShow: wNoShow ?? s.weightNoShow,
    );

    setState(() => savingReliability = true);

    try {
      await ReliabilityService.updateSettings(
        companyId: companyId,
        settings: updated,
      );

      if (!mounted) return;
      setState(() => reliabilitySettings = updated);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Reliability settings saved")),
      );
    } catch (e) {
      _error("Couldn't save reliability settings: $e");
    } finally {
      if (mounted) setState(() => savingReliability = false);
    }
  }

  Future<void> _saveIncidentReportSettings(
    IncidentReportSettings updated,
  ) async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) return;

    setState(() => savingIncidentReports = true);

    try {
      await IncidentReportService.updateSettings(
        companyId: companyId,
        settings: updated,
      );

      if (!mounted) return;
      setState(() => incidentReportSettings = updated);
    } catch (e) {
      _error("Couldn't save incident report settings: $e");
    } finally {
      if (mounted) setState(() => savingIncidentReports = false);
    }
  }

  Future<void> _useCurrentLocationForGeofence() async {
    setState(() => locatingNow = true);

    try {
      final permission = await Geolocator.checkPermission();
      var granted = permission;
      if (permission == LocationPermission.denied) {
        granted = await Geolocator.requestPermission();
      }

      if (granted == LocationPermission.denied ||
          granted == LocationPermission.deniedForever) {
        _error("Location permission denied — enable it in device settings");
        return;
      }

      final position = await Geolocator.getCurrentPosition();

      setState(() {
        geofenceSettings = geofenceSettings?.copyWith(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      });
    } catch (e) {
      _error("Couldn't get current location: \$e");
    } finally {
      if (mounted) setState(() => locatingNow = false);
    }
  }

  Future<void> _saveGeofenceSettings() async {
    final companyId = SessionService.activeCompanyId;
    final s = geofenceSettings;
    if (companyId == null || s == null) return;

    final radius = double.tryParse(_radiusController.text.trim());
    if (radius == null || radius <= 0) {
      _error("Radius must be a positive number of meters");
      return;
    }

    if (s.enabled && !s.hasLocationSet) {
      _error('Set a location with "Use My Current Location" before enabling');
      return;
    }

    final updated = s.copyWith(radiusMeters: radius);

    setState(() => savingGeofence = true);

    try {
      await GeofenceService.updateSettings(companyId: companyId, settings: updated);
      if (!mounted) return;
      setState(() => geofenceSettings = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Geofence settings saved")),
      );
    } catch (e) {
      _error("Couldn't save geofence settings: \$e");
    } finally {
      if (mounted) setState(() => savingGeofence = false);
    }
  }

  Future<void> _toggleShiftComments(bool v) async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) return;
    setState(() => shiftCommentsEnabled = v);
    try {
      await ShiftCommentService.setEnabled(companyId, v);
    } catch (e) {
      _error("Couldn't save: \$e");
    }
  }

  Future<void> _toggleShiftChecklists(bool v) async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) return;
    setState(() => shiftChecklistsEnabled = v);
    try {
      await ShiftChecklistService.setEnabled(companyId, v);
    } catch (e) {
      _error("Couldn't save: \$e");
    }
  }

  Future<void> _addChecklistItem() async {
    final companyId = SessionService.activeCompanyId;
    final label = _newChecklistItemController.text.trim();
    if (companyId == null || label.isEmpty) return;

    setState(() => savingShiftExtras = true);
    try {
      await ShiftChecklistService.addItem(
        companyId: companyId,
        label: label,
        sortOrder: checklistItems.length,
      );
      _newChecklistItemController.clear();
      checklistItems = await ShiftChecklistService.getItems(companyId);
    } catch (e) {
      _error("Couldn't add item: \$e");
    } finally {
      if (mounted) setState(() => savingShiftExtras = false);
    }
  }

  Future<void> _deleteChecklistItem(ShiftChecklistItem item) async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) return;

    try {
      await ShiftChecklistService.deleteItem(item.id);
      checklistItems = await ShiftChecklistService.getItems(companyId);
      if (mounted) setState(() {});
    } catch (e) {
      _error("Couldn't remove item: \$e");
    }
  }

  Future<void> _toggleClockInPhoto(bool v) async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) return;
    setState(() => clockInPhotoEnabled = v);
    try {
      await ClockInPhotoService.setRequired(companyId, v);
    } catch (e) {
      _error("Couldn't save: \$e");
    }
  }

  Future<void> _saveLaborBudgetSettings() async {
    final companyId = SessionService.activeCompanyId;
    final s = laborBudgetSettings;
    if (companyId == null || s == null) return;

    final amount = double.tryParse(_laborBudgetController.text.trim());
    if (s.enabled && (amount == null || amount <= 0)) {
      _error("Budget must be a positive dollar amount");
      return;
    }

    final updated = s.copyWith(amount: amount ?? s.amount);

    setState(() => savingLaborBudget = true);

    try {
      await LaborBudgetService.updateSettings(
        companyId: companyId,
        settings: updated,
      );
      if (!mounted) return;
      setState(() => laborBudgetSettings = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Labor budget saved")),
      );
    } catch (e) {
      _error("Couldn't save labor budget: \$e");
    } finally {
      if (mounted) setState(() => savingLaborBudget = false);
    }
  }

  Future<void> _addSkill() async {
    final companyId = SessionService.activeCompanyId;
    final label = _newSkillController.text.trim();
    if (companyId == null || label.isEmpty) return;

    setState(() => savingSkills = true);
    try {
      await EmployeeSkillService.addSkill(companyId: companyId, label: label);
      _newSkillController.clear();
      skills = await EmployeeSkillService.getSkills(companyId);
    } catch (e) {
      _error("Couldn't add skill: \$e");
    } finally {
      if (mounted) setState(() => savingSkills = false);
    }
  }

  Future<void> _deleteSkill(EmployeeSkill skill) async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) return;

    try {
      await EmployeeSkillService.deleteSkill(skill.id);
      skills = await EmployeeSkillService.getSkills(companyId);
      if (mounted) setState(() {});
    } catch (e) {
      _error("Couldn't remove skill: \$e");
    }
  }

  Future<void> _saveOpenShiftPriority(String value) async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) return;

    setState(() {
      openShiftPriority = value;
      savingOpenShiftPriority = true;
    });

    try {
      await SupabaseService.client
          .from('companies')
          .update({'open_shift_priority': value})
          .eq('id', companyId);
    } catch (e) {
      _error("Couldn't save open-shift priority: \$e");
    } finally {
      if (mounted) setState(() => savingOpenShiftPriority = false);
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    await SessionService.clear();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const SplashRouter()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyName = SessionService.activeCompanyName ?? "No Company";
    final role = SessionService.activeRole ?? "employee";
    final email = Supabase.instance.client.auth.currentUser?.email ?? "—";
    final displayName = profile?.safeDisplayName ?? "Unknown";
    final isManager = RoleService.isManager();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionHeader("Profile"),
                _infoTile(Icons.person, "Display Name", displayName),
                _infoTile(Icons.email, "Email", email),

                const SizedBox(height: 24),
                _sectionHeader("Company"),
                _infoTile(Icons.business, "Company", companyName),
                _infoTile(Icons.badge, "Role", role),

                if (isManager && overtimeSettings != null) ...[
                  const SizedBox(height: 24),
                  _overtimeSection(),
                ],

                if (isManager && reliabilitySettings != null) ...[
                  const SizedBox(height: 24),
                  _reliabilitySection(),
                ],

                if (isManager && incidentReportSettings != null) ...[
                  const SizedBox(height: 24),
                  _incidentReportsSection(),
                ],

                if (isManager) ...[
                  const SizedBox(height: 24),
                  _legalReferenceLink(context),
                ],

                if (isManager && geofenceSettings != null) ...[
                  const SizedBox(height: 24),
                  _geofenceSection(),
                ],

                if (isManager && shiftCommentsEnabled != null) ...[
                  const SizedBox(height: 24),
                  _shiftExtrasSection(),
                ],

                if (isManager && clockInPhotoEnabled != null) ...[
                  const SizedBox(height: 24),
                  _clockInPhotoSection(),
                ],

                if (isManager && laborBudgetSettings != null) ...[
                  const SizedBox(height: 24),
                  _laborBudgetSection(),
                ],

                if (isManager && skillsEnabled) ...[
                  const SizedBox(height: 24),
                  _skillsSection(),
                ],

                if (isManager && openShiftPriority != null) ...[
                  const SizedBox(height: 24),
                  _openShiftPrioritySection(),
                ],

                const SizedBox(height: 24),
                _sectionHeader("About"),
                _infoTile(Icons.info_outline, "App Version", _appVersion),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text("Sign Out"),
                  ),
                ),
              ],
            ),
    );
  }

  // ----------------------------
  // OVERTIME SETTINGS (manager-only)
  // ----------------------------
  Widget _overtimeSection() {
    final s = overtimeSettings!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Overtime Rules",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              "Set your own thresholds — nothing is applied until you "
              "turn it on.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Daily threshold"),
              value: s.dailyEnabled,
              onChanged: (v) => setState(
                  () => overtimeSettings = s.copyWith(dailyEnabled: v)),
            ),
            if (s.dailyEnabled)
              _numberField(
                controller: _dailyController,
                label: "Hours per day before overtime",
              ),

            const Divider(),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Weekly threshold"),
              value: s.weeklyEnabled,
              onChanged: (v) => setState(
                  () => overtimeSettings = s.copyWith(weeklyEnabled: v)),
            ),
            if (s.weeklyEnabled)
              _numberField(
                controller: _weeklyController,
                label: "Hours per week before overtime",
              ),

            const Divider(),

            const Text(
              "Pay mode",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            RadioGroup<String>(
              groupValue: s.payMode,
              onChanged: (v) {
                if (v != null) {
                  setState(() => overtimeSettings = s.copyWith(payMode: v));
                }
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                        "Track hours only (pay stays at straight rate)"),
                    value: 'hours_only',
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text("Calculate overtime pay automatically"),
                    value: 'calculate_pay',
                  ),
                ],
              ),
            ),

            if (s.calculatesPay) ...[
              const SizedBox(height: 8),
              _numberField(
                controller: _multiplierController,
                label: "Overtime pay multiplier (e.g. 1.5)",
              ),
            ],

            if (s.dailyEnabled && s.weeklyEnabled) ...[
              const SizedBox(height: 8),
              const Text(
                "Note: hours counted as daily overtime are also "
                "counted toward the weekly total, so some hours may "
                "be paid at the overtime rate under both rules.",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: savingOvertime ? null : _saveOvertimeSettings,
                child: Text(
                    savingOvertime ? "Saving..." : "Save Overtime Settings"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------
  // RELIABILITY SETTINGS (manager-only)
  // ----------------------------
  Widget _reliabilitySection() {
    final s = reliabilitySettings!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Reliability Rules",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              "Tracks late clock-ins, early leaves, and no-shows "
              "against scheduled shifts. Nothing is applied until you "
              "turn it on.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Enable reliability tracking"),
              value: s.enabled,
              onChanged: (v) => setState(
                  () => reliabilitySettings = s.copyWith(enabled: v)),
            ),

            if (s.enabled) ...[
              const Divider(),

              _numberField(
                controller: _graceController,
                label: "Grace period (minutes) before something counts",
                integer: true,
              ),

              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text("Track late clock-ins"),
                value: s.trackLate,
                onChanged: (v) => setState(
                    () => reliabilitySettings = s.copyWith(trackLate: v)),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text("Track early leaves"),
                value: s.trackEarlyLeave,
                onChanged: (v) => setState(() =>
                    reliabilitySettings = s.copyWith(trackEarlyLeave: v)),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text("Track no-shows / missed shifts"),
                value: s.trackNoShow,
                onChanged: (v) => setState(
                    () => reliabilitySettings = s.copyWith(trackNoShow: v)),
              ),

              const Divider(),

              const Text(
                "Scoring",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              RadioGroup<String>(
                groupValue: s.weightMode,
                onChanged: (v) {
                  if (v != null) {
                    setState(
                        () => reliabilitySettings = s.copyWith(weightMode: v));
                  }
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text("Same point cost for any infraction"),
                      value: 'flat',
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title:
                          const Text("Different point cost per infraction type"),
                      value: 'weighted',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              if (!s.isWeighted)
                _numberField(
                  controller: _flatPointsController,
                  label: "Points off per infraction",
                )
              else ...[
                _numberField(
                  controller: _weightLateController,
                  label: "Points off per late clock-in",
                ),
                _numberField(
                  controller: _weightEarlyController,
                  label: "Points off per early leave",
                ),
                _numberField(
                  controller: _weightNoShowController,
                  label: "Points off per no-show",
                ),
              ],

              const SizedBox(height: 4),
              const Text(
                "Scores start at 100 for each employee per period and "
                "can't go below 0.",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    savingReliability ? null : _saveReliabilitySettings,
                child: Text(savingReliability
                    ? "Saving..."
                    : "Save Reliability Settings"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------
  // INCIDENT REPORTS (manager-only)
  // ----------------------------
  Widget _incidentReportsSection() {
    final s = incidentReportSettings!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Incident Reports",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              "Lets employees report workplace incidents directly to "
              "you. Off by default.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Enable incident reporting"),
              value: s.enabled,
              onChanged: (v) => setState(() {
                incidentReportSettings = s.copyWith(enabled: v);
              }),
            ),

            if (s.enabled) ...[
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Allow anonymous submissions"),
                subtitle: const Text(
                  "When on, an anonymous submitter's identity is never "
                  "recorded — not even you will be able to see who "
                  "submitted it.",
                  style: TextStyle(fontSize: 11),
                ),
                value: s.allowAnonymous,
                onChanged: (v) => setState(() {
                  incidentReportSettings = s.copyWith(allowAnonymous: v);
                }),
              ),
              const Text(
                "Whether a specific report gets shared with the "
                "employee it's about is a separate decision you make "
                "per report, in Incident Reports.",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: savingIncidentReports
                    ? null
                    : () => _saveIncidentReportSettings(s),
                child: Text(savingIncidentReports
                    ? "Saving..."
                    : "Save Incident Report Settings"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _geofenceSection() {
    final s = geofenceSettings!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Geofenced Clock-In",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              "Requires employees to be near a set location to clock in. "
              "Off by default.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Require location to clock in"),
              value: s.enabled,
              onChanged: (v) => setState(() => geofenceSettings = s.copyWith(enabled: v)),
            ),
            const Divider(),
            Text(
              s.hasLocationSet
                  ? "Location set (\${s.latitude!.toStringAsFixed(5)}, \${s.longitude!.toStringAsFixed(5)})"
                  : "No location set yet",
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: locatingNow ? null : _useCurrentLocationForGeofence,
              icon: const Icon(Icons.my_location, size: 16),
              label: Text(locatingNow ? "Getting location..." : "Use My Current Location"),
            ),
            const SizedBox(height: 8),
            _numberField(controller: _radiusController, label: "Allowed radius (meters)"),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: savingGeofence ? null : _saveGeofenceSettings,
                child: Text(savingGeofence ? "Saving..." : "Save Geofence Settings"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shiftExtrasSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Shift Comments & Checklists",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              "Both off by default. Available by long-pressing any shift.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Enable shift comments"),
              value: shiftCommentsEnabled ?? false,
              onChanged: _toggleShiftComments,
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Enable shift checklists"),
              value: shiftChecklistsEnabled ?? false,
              onChanged: _toggleShiftChecklists,
            ),
            if (shiftChecklistsEnabled == true) ...[
              const SizedBox(height: 8),
              ...checklistItems.map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(item.label, style: const TextStyle(fontSize: 13)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => _deleteChecklistItem(item),
                    ),
                  )),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newChecklistItemController,
                      decoration: const InputDecoration(
                        hintText: "e.g. Lock the register",
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: savingShiftExtras ? null : _addChecklistItem,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _clockInPhotoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Photo at Clock-In",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              "Requires a quick front-camera photo every time someone "
              "clocks in. Off by default. Photos are private — only "
              "visible to managers, never public.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Require photo to clock in"),
              value: clockInPhotoEnabled ?? false,
              onChanged: _toggleClockInPhoto,
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------
  // LABOR BUDGET (manager-only)
  // ----------------------------
  Widget _laborBudgetSection() {
    final s = laborBudgetSettings!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Labor Budget",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              "Get a heads-up while scheduling if a week's projected "
              "labor cost goes over budget. Advisory only — never "
              "blocks a shift from being created.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Enable labor budget warnings"),
              value: s.enabled,
              onChanged: (v) =>
                  setState(() => laborBudgetSettings = s.copyWith(enabled: v)),
            ),
            if (s.enabled) ...[
              const Divider(),
              _numberField(
                controller: _laborBudgetController,
                label: "Weekly labor budget (\$)",
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: savingLaborBudget ? null : _saveLaborBudgetSettings,
                child: Text(
                    savingLaborBudget ? "Saving..." : "Save Labor Budget"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------
  // SKILLS (manager-only) — company-wide tag management. Assigning
  // tags to individual employees happens on their profile screen,
  // not here.
  // ----------------------------
  Widget _skillsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Skills",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              "Tag skills like \"bartender\" or \"certified forklift\". "
              "A shift can optionally require one — assigning someone "
              "without it just warns, never blocks. Assign tags to "
              "specific employees from their profile.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ...skills.map((skill) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(skill.label, style: const TextStyle(fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => _deleteSkill(skill),
                  ),
                )),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newSkillController,
                    decoration: const InputDecoration(
                      hintText: "e.g. Certified bartender",
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: savingSkills ? null : _addSkill,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------
  // OPEN-SHIFT PRIORITY (manager-only)
  // ----------------------------
  Widget _openShiftPrioritySection() {
    final value = openShiftPriority ?? 'first_come';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Open-Shift Claim Priority",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              "Decides who gets an open shift when more than one "
              "person tries to claim it. First-come-first-served by "
              "default.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            RadioGroup<String>(
              groupValue: value,
              onChanged: (v) {
                if (v != null && !savingOpenShiftPriority) _saveOpenShiftPriority(v);
              },
              child: const Column(
                children: [
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text("First come, first served"),
                    value: 'first_come',
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text("Most senior employee (by hire date)"),
                    value: 'seniority_first',
                  ),
                ],
              ),
            ),
            if (value == 'seniority_first') ...[
              const SizedBox(height: 4),
              const Text(
                "Employees with no hire date set rank below everyone "
                "who has one — set hire dates on employee profiles for "
                "this to work as expected.",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legalReferenceLink(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.gavel),
        title: const Text("Legal Reference — Oregon"),
        subtitle: const Text(
          "Minimum wage, breaks, overtime, final pay, sick time. "
          "Informational only.",
          style: TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LegalReferenceScreen()),
          );
        },
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    bool integer = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: integer
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
      dense: true,
    );
  }
}