// lib/shared/models/incident_report_model.dart

class IncidentReportSettings {
  final bool enabled;
  final bool allowAnonymous;

  const IncidentReportSettings({
    required this.enabled,
    required this.allowAnonymous,
  });

  static const defaults = IncidentReportSettings(
    enabled: false,
    allowAnonymous: false,
  );

  factory IncidentReportSettings.fromMap(Map<String, dynamic> map) {
    return IncidentReportSettings(
      enabled: map['incident_reports_enabled'] as bool? ?? false,
      allowAnonymous:
          map['incident_reports_allow_anonymous'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'incident_reports_enabled': enabled,
        'incident_reports_allow_anonymous': allowAnonymous,
      };

  IncidentReportSettings copyWith({bool? enabled, bool? allowAnonymous}) {
    return IncidentReportSettings(
      enabled: enabled ?? this.enabled,
      allowAnonymous: allowAnonymous ?? this.allowAnonymous,
    );
  }
}

/// submittedByUserId is null whenever isAnonymous is true — enforced
/// at the DB level (incident_reports_anonymity_check), not just by
/// this model.
class IncidentReport {
  final String id;
  final String companyId;
  final String? reportedUserId;
  final String? submittedByUserId;
  final bool isAnonymous;
  final String description;
  final DateTime? incidentDate;
  final String status; // submitted | under_review | resolved | dismissed
  final String? managerNotes;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final bool sharedWithReported;
  final DateTime createdAt;

  const IncidentReport({
    required this.id,
    required this.companyId,
    this.reportedUserId,
    this.submittedByUserId,
    required this.isAnonymous,
    required this.description,
    this.incidentDate,
    required this.status,
    this.managerNotes,
    this.resolvedBy,
    this.resolvedAt,
    required this.sharedWithReported,
    required this.createdAt,
  });

  bool get isResolved => status == 'resolved' || status == 'dismissed';

  factory IncidentReport.fromMap(Map<String, dynamic> map) {
    return IncidentReport(
      id: map['id']?.toString() ?? '',
      companyId: map['company_id']?.toString() ?? '',
      reportedUserId: map['reported_user_id']?.toString(),
      submittedByUserId: map['submitted_by_user_id']?.toString(),
      isAnonymous: map['is_anonymous'] as bool? ?? false,
      description: map['description']?.toString() ?? '',
      incidentDate: map['incident_date'] == null
          ? null
          : DateTime.tryParse(map['incident_date'].toString()),
      status: map['status']?.toString() ?? 'submitted',
      managerNotes: map['manager_notes']?.toString(),
      resolvedBy: map['resolved_by']?.toString(),
      resolvedAt: map['resolved_at'] == null
          ? null
          : DateTime.tryParse(map['resolved_at'].toString()),
      sharedWithReported: map['shared_with_reported'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}