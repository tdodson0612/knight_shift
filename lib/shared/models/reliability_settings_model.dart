// lib/shared/models/reliability_settings_model.dart

/// Per-company reliability tracking configuration, set by that
/// company's own manager/admin in Settings.
class ReliabilitySettings {
  final bool enabled;
  final int graceMinutes;
  final bool trackLate;
  final bool trackEarlyLeave;
  final bool trackNoShow;

  /// 'flat'     -> every infraction (of any tracked type) costs the
  ///               same [flatPoints].
  /// 'weighted' -> each infraction type has its own point cost.
  final String weightMode;
  final double flatPoints;
  final double weightLate;
  final double weightEarlyLeave;
  final double weightNoShow;

  const ReliabilitySettings({
    required this.enabled,
    required this.graceMinutes,
    required this.trackLate,
    required this.trackEarlyLeave,
    required this.trackNoShow,
    required this.weightMode,
    required this.flatPoints,
    required this.weightLate,
    required this.weightEarlyLeave,
    required this.weightNoShow,
  });

  static const defaults = ReliabilitySettings(
    enabled: false,
    graceMinutes: 5,
    trackLate: true,
    trackEarlyLeave: true,
    trackNoShow: true,
    weightMode: 'flat',
    flatPoints: 10,
    weightLate: 5,
    weightEarlyLeave: 5,
    weightNoShow: 15,
  );

  bool get isWeighted => weightMode == 'weighted';

  factory ReliabilitySettings.fromMap(Map<String, dynamic> map) {
    return ReliabilitySettings(
      enabled: map['reliability_enabled'] as bool? ?? false,
      graceMinutes: (map['reliability_grace_minutes'] ?? 5) is int
          ? map['reliability_grace_minutes'] as int
          : (map['reliability_grace_minutes'] as num).toInt(),
      trackLate: map['reliability_track_late'] as bool? ?? true,
      trackEarlyLeave: map['reliability_track_early_leave'] as bool? ?? true,
      trackNoShow: map['reliability_track_no_show'] as bool? ?? true,
      weightMode: map['reliability_weight_mode']?.toString() ?? 'flat',
      flatPoints: (map['reliability_flat_points'] ?? 10).toDouble(),
      weightLate: (map['reliability_weight_late'] ?? 5).toDouble(),
      weightEarlyLeave:
          (map['reliability_weight_early_leave'] ?? 5).toDouble(),
      weightNoShow: (map['reliability_weight_no_show'] ?? 15).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'reliability_enabled': enabled,
      'reliability_grace_minutes': graceMinutes,
      'reliability_track_late': trackLate,
      'reliability_track_early_leave': trackEarlyLeave,
      'reliability_track_no_show': trackNoShow,
      'reliability_weight_mode': weightMode,
      'reliability_flat_points': flatPoints,
      'reliability_weight_late': weightLate,
      'reliability_weight_early_leave': weightEarlyLeave,
      'reliability_weight_no_show': weightNoShow,
    };
  }

  ReliabilitySettings copyWith({
    bool? enabled,
    int? graceMinutes,
    bool? trackLate,
    bool? trackEarlyLeave,
    bool? trackNoShow,
    String? weightMode,
    double? flatPoints,
    double? weightLate,
    double? weightEarlyLeave,
    double? weightNoShow,
  }) {
    return ReliabilitySettings(
      enabled: enabled ?? this.enabled,
      graceMinutes: graceMinutes ?? this.graceMinutes,
      trackLate: trackLate ?? this.trackLate,
      trackEarlyLeave: trackEarlyLeave ?? this.trackEarlyLeave,
      trackNoShow: trackNoShow ?? this.trackNoShow,
      weightMode: weightMode ?? this.weightMode,
      flatPoints: flatPoints ?? this.flatPoints,
      weightLate: weightLate ?? this.weightLate,
      weightEarlyLeave: weightEarlyLeave ?? this.weightEarlyLeave,
      weightNoShow: weightNoShow ?? this.weightNoShow,
    );
  }
}

/// Computed reliability result for one user over one period. Not
/// stored anywhere — recomputed on demand from shifts + time_entries,
/// same reconciliation-not-mutation philosophy as payroll.
class ReliabilityStats {
  final int lateCount;
  final int earlyLeaveCount;
  final int noShowCount;
  final int shiftsEvaluated;

  /// 0-100, already clamped.
  final double score;

  const ReliabilityStats({
    required this.lateCount,
    required this.earlyLeaveCount,
    required this.noShowCount,
    required this.shiftsEvaluated,
    required this.score,
  });

  int get totalInfractions => lateCount + earlyLeaveCount + noShowCount;
}