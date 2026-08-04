// lib/core/services/payroll_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/payroll_model.dart';
import '../../shared/models/overtime_settings_model.dart';
import 'subscription_service.dart';

class PayrollService {
  static final _db = Supabase.instance.client;

  /// CREATE PAYROLL RUN (PARENT CONTAINER) — gated: payroll
  /// generation disabled when the company's trial has ended and no
  /// active subscription exists. Viewing existing payroll history is
  /// never gated.
  static Future<String> createPayrollRun({
    required String companyId,
    required DateTime start,
    required DateTime end,
    required String createdBy,
  }) async {
    if (await SubscriptionService.isLocked(companyId)) {
      throw Exception(
        "Payroll generation is disabled — your trial has ended. Upgrade to continue.",
      );
    }

    final run = await _db
        .from('payroll_runs')
        .insert({
          'company_id': companyId,
          'start_date': start.toIso8601String(),
          'end_date': end.toIso8601String(),
          'status': 'draft',
          'created_by': createdBy,
        })
        .select()
        .single();

    return run['id'].toString();
  }

  /// ADD PAYROLL ENTRIES (CALCULATED ROWS PER EMPLOYEE) — no
  /// overtime split, straight rate throughout. Use this when the
  /// company has no overtime thresholds enabled.
  static Future<void> addEntries({
    required String payrollRunId,
    required List<Map<String, dynamic>> entries,
  }) async {
    final payload = entries.map((e) {
      final hours = (e['hours'] ?? 0).toDouble();
      final rate = (e['rate'] ?? 0).toDouble();

      return {
        'payroll_run_id': payrollRunId,
        'user_id': e['userId'],
        'total_hours': hours,
        'hourly_rate': rate,
        'total_pay': hours * rate,
      };
    }).toList();

    await _db.from('payroll_entries').insert(payload);
  }

  /// ADD PAYROLL ENTRIES WITH OVERTIME BREAKDOWN — use when the
  /// company has daily and/or weekly overtime thresholds enabled
  /// (see OvertimeService). Populates regular_hours/overtime_hours/
  /// overtime_pay alongside the original total_hours/total_pay
  /// columns, so anything still reading only those original columns
  /// (e.g. older reports) keeps working unchanged.
  static Future<void> addEntriesWithOvertime({
    required String payrollRunId,
    required Map<String, OvertimeBreakdown> breakdownByUser,
    required Map<String, double> hourlyRateByUser,
  }) async {
    final payload = breakdownByUser.entries.map((e) {
      final b = e.value;
      final rate = hourlyRateByUser[e.key] ?? 0.0;

      return {
        'payroll_run_id': payrollRunId,
        'user_id': e.key,
        'total_hours': b.totalHours,
        'hourly_rate': rate,
        'total_pay': b.totalPay,
        'regular_hours': b.regularHours,
        'overtime_hours': b.overtimeHours,
        'overtime_pay': b.overtimePay,
      };
    }).toList();

    await _db.from('payroll_entries').insert(payload);
  }

  /// APPROVE PAYROLL (SOFT STATE CHANGE)
  static Future<void> approvePayroll(String payrollRunId) async {
    await _db
        .from('payroll_runs')
        .update({'status': 'approved'})
        .eq('id', payrollRunId);
  }

  /// LOCK PAYROLL (IMMUTABLE STATE)
  static Future<void> lockPayroll(String payrollRunId) async {
    await _db
        .from('payroll_runs')
        .update({'status': 'locked'})
        .eq('id', payrollRunId);
  }

  /// LIST PAYROLL RUNS FOR A COMPANY (most recent first) — never gated
  static Future<List<PayrollRun>> getPayrollRuns(String companyId) async {
    final res = await _db
        .from('payroll_runs')
        .select()
        .eq('company_id', companyId)
        .order('start_date', ascending: false);

    return List<Map<String, dynamic>>.from(res)
        .map(PayrollRun.fromMap)
        .toList();
  }

  /// LIST PER-EMPLOYEE ENTRIES FOR A SPECIFIC PAYROLL RUN — never gated
  static Future<List<PayrollSummary>> getPayrollEntries(
    String payrollRunId,
  ) async {
    final res = await _db
        .from('payroll_entries')
        .select()
        .eq('payroll_run_id', payrollRunId);

    return List<Map<String, dynamic>>.from(res)
        .map(PayrollSummary.fromMap)
        .toList();
  }
}