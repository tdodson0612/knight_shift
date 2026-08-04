// lib/shared/models/subscription_model.dart

/// Company-level subscription state. One subscription per company —
/// every employee inherits it. Never per-user.
class CompanySubscription {
  final String companyId;
  final String status; // trialing | active | past_due | canceled
  final String tier; // starter | professional | enterprise
  final DateTime? trialEnd;
  final DateTime? currentPeriodEnd;

  CompanySubscription({
    required this.companyId,
    required this.status,
    required this.tier,
    this.trialEnd,
    this.currentPeriodEnd,
  });

  factory CompanySubscription.fromMap(Map<String, dynamic> map) {
    return CompanySubscription(
      companyId: map['id']?.toString() ?? '',
      status: map['subscription_status']?.toString() ?? 'trialing',
      tier: map['subscription_tier']?.toString() ?? 'starter',
      trialEnd: map['trial_end'] != null
          ? DateTime.tryParse(map['trial_end'].toString())
          : null,
      currentPeriodEnd: map['current_period_end'] != null
          ? DateTime.tryParse(map['current_period_end'].toString())
          : null,
    );
  }

  bool get isTrialing => status == 'trialing';
  bool get isActive => status == 'active';
  bool get isPastDue => status == 'past_due';
  bool get isCanceled => status == 'canceled';

  bool get isTrialExpired {
    if (!isTrialing) return false;
    if (trialEnd == null) return false;
    return DateTime.now().isAfter(trialEnd!);
  }

  /// Whether premium-gated actions (schedule editing, payroll
  /// generation, sending invites) should be blocked. Read/view
  /// access to existing data is NEVER gated — only these specific
  /// write actions.
  bool get isLocked {
    if (isActive) return false;
    if (isTrialing) return isTrialExpired;
    // past_due / canceled — locked.
    return true;
  }

  int get daysLeftInTrial {
    if (!isTrialing || trialEnd == null) return 0;
    final diff = trialEnd!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }
}