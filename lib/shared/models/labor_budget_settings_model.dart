// lib/shared/models/labor_budget_settings_model.dart

/// Per-company labor budget configuration, set by that company's own
/// manager/admin in Settings — never a hardcoded business rule.
/// Read from / written to columns on `companies`.
///
/// Advisory only: exceeding the budget surfaces a non-blocking
/// warning while scheduling, never blocks shift creation (same
/// fail-open philosophy as availability warnings).
class LaborBudgetSettings {
  final bool enabled;
  final double amount;

  const LaborBudgetSettings({
    required this.enabled,
    required this.amount,
  });

  static const defaults = LaborBudgetSettings(
    enabled: false,
    amount: 0,
  );

  factory LaborBudgetSettings.fromMap(Map<String, dynamic> map) {
    return LaborBudgetSettings(
      enabled: map['labor_budget_enabled'] as bool? ?? false,
      amount: (map['labor_budget_amount'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'labor_budget_enabled': enabled,
        'labor_budget_amount': amount,
      };

  LaborBudgetSettings copyWith({bool? enabled, double? amount}) {
    return LaborBudgetSettings(
      enabled: enabled ?? this.enabled,
      amount: amount ?? this.amount,
    );
  }
}