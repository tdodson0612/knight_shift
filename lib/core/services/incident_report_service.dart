// lib/core/services/incident_report_service.dart
//
// Owns coworker/workplace incident reporting: manager-configured
// settings (enabled + anonymous-allowed, stored on `companies`),
// submission, and manager review/resolution.
//
// ANONYMITY: when isAnonymous is true, submitted_by_user_id is NEVER
// written to the row — not just hidden from other users client-side,
// but not stored at all, enforced by a DB check constraint
// (incident_reports_anonymity_check). Nobody, including the manager,
// can identify the submitter from an anonymous row. That's the
// standard meaning of "anonymous" in whistleblower/reporting tooling
// — a weaker "hidden from the accused but visible to the manager"
// mode isn't offered.
//
// DUE PROCESS: a reported employee only ever sees a report if a
// manager explicitly sets sharedWithReported = true on that specific
// report — a per-incident manager decision, never automatic, never
// company-wide.

import 'supabase_service.dart';
import '../../shared/models/incident_report_model.dart';

class IncidentReportService {
  static final _db = SupabaseService.client;

  // ----------------------------
  // SETTINGS (per company)
  // ----------------------------
  static Future<IncidentReportSettings> getSettings(String companyId) async {
    final res = await _db
        .from('companies')
        .select('incident_reports_enabled, incident_reports_allow_anonymous')
        .eq('id', companyId)
        .single();

    return IncidentReportSettings.fromMap(res);
  }

  /// Manager-only in practice, enforced by the existing
  /// `companies_update` RLS policy (is_company_manager).
  static Future<void> updateSettings({
    required String companyId,
    required IncidentReportSettings settings,
  }) async {
    await _db.from('companies').update(settings.toMap()).eq('id', companyId);
  }

  // ----------------------------
  // SUBMIT
  // ----------------------------
  static Future<void> submitReport({
    required String companyId,
    required String description,
    String? reportedUserId,
    DateTime? incidentDate,
    required bool anonymous,
    required String submittedByUserId,
  }) async {
    await _db.from('incident_reports').insert({
      'company_id': companyId,
      'reported_user_id': reportedUserId,
      'submitted_by_user_id': anonymous ? null : submittedByUserId,
      'is_anonymous': anonymous,
      'description': description,
      'incident_date': incidentDate?.toIso8601String().split('T').first,
      'status': 'submitted',
    });
  }

  // ----------------------------
  // MANAGER REVIEW
  // ----------------------------

  /// All reports for the company. RLS already restricts this to
  /// managers — a non-manager calling it gets an empty list, not an
  /// error (the usual RLS failure mode in this app).
  static Future<List<IncidentReport>> getCompanyReports(
    String companyId,
  ) async {
    final res = await _db
        .from('incident_reports')
        .select()
        .eq('company_id', companyId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res)
        .map(IncidentReport.fromMap)
        .toList();
  }

  /// Reports the current user submitted themselves. Anonymous
  /// submissions never show up here, even for the person who
  /// submitted them — submitted_by_user_id was never recorded, so
  /// there's nothing to look up.
  static Future<List<IncidentReport>> getMySubmittedReports(
    String userId,
  ) async {
    final res = await _db
        .from('incident_reports')
        .select()
        .eq('submitted_by_user_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res)
        .map(IncidentReport.fromMap)
        .toList();
  }

  /// Reports about the current user that a manager has chosen to
  /// share with them. RLS already enforces shared_with_reported =
  /// true — filtered client-side too for clarity, not as the real
  /// guard.
  static Future<List<IncidentReport>> getReportsSharedWithMe(
    String userId,
  ) async {
    final res = await _db
        .from('incident_reports')
        .select()
        .eq('reported_user_id', userId)
        .eq('shared_with_reported', true)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res)
        .map(IncidentReport.fromMap)
        .toList();
  }

  static Future<void> updateStatus({
    required String reportId,
    required String status,
    String? managerNotes,
    bool? sharedWithReported,
    String? resolvedByUserId,
  }) async {
    final payload = <String, dynamic>{'status': status};

    if (managerNotes != null) payload['manager_notes'] = managerNotes;
    if (sharedWithReported != null) {
      payload['shared_with_reported'] = sharedWithReported;
    }

    if (status == 'resolved' || status == 'dismissed') {
      payload['resolved_at'] = DateTime.now().toIso8601String();
      if (resolvedByUserId != null) payload['resolved_by'] = resolvedByUserId;
    }

    await _db.from('incident_reports').update(payload).eq('id', reportId);
  }
}