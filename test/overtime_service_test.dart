import 'package:flutter_test/flutter_test.dart';
import 'package:knight_shift/core/services/overtime_service.dart';
import 'package:knight_shift/shared/models/overtime_settings_model.dart';

void main() {
  group('OvertimeService.splitHours', () {
    test('no thresholds enabled — all hours regular, no overtime pay', () {
      final settings = OvertimeSettings.defaults;
      final dailyHours = {
        DateTime(2026, 8, 3): 8.0,
        DateTime(2026, 8, 4): 8.0,
        DateTime(2026, 8, 5): 8.0,
      };

      final result = OvertimeService.splitHours(
        dailyHours: dailyHours,
        hourlyRate: 20.0,
        settings: settings,
      );

      expect(result.totalHours, 24.0);
      expect(result.regularHours, 24.0);
      expect(result.overtimeHours, 0.0);
      expect(result.regularPay, 480.0);
      expect(result.overtimePay, 0.0);
      expect(result.totalPay, 480.0);
    });

    test('daily overtime — hours over daily threshold', () {
      final settings = OvertimeSettings(
        dailyEnabled: true,
        dailyThresholdHours: 8.0,
        weeklyEnabled: false,
        weeklyThresholdHours: 40.0,
        payMode: 'calculate_pay',
        multiplier: 1.5,
      );

      final dailyHours = {
        DateTime(2026, 8, 3): 10.0, // 2 hours OT
        DateTime(2026, 8, 4): 8.0,
        DateTime(2026, 8, 5): 8.0,
      };

      final result = OvertimeService.splitHours(
        dailyHours: dailyHours,
        hourlyRate: 20.0,
        settings: settings,
      );

      expect(result.totalHours, 26.0);
      expect(result.regularHours, 24.0);
      expect(result.overtimeHours, 2.0);
      expect(result.regularPay, 480.0);
      expect(result.overtimePay, 60.0); // 2 * 20 * 1.5
      expect(result.totalPay, 540.0);
    });

    test('weekly overtime — hours over weekly threshold', () {
      final settings = OvertimeSettings(
        dailyEnabled: false,
        dailyThresholdHours: 8.0,
        weeklyEnabled: true,
        weeklyThresholdHours: 40.0,
        payMode: 'calculate_pay',
        multiplier: 1.5,
      );

      final dailyHours = {
        DateTime(2026, 8, 3): 10.0, // Monday
        DateTime(2026, 8, 4): 10.0, // Tuesday
        DateTime(2026, 8, 5): 10.0, // Wednesday
        DateTime(2026, 8, 6): 10.0, // Thursday
        DateTime(2026, 8, 7): 10.0, // Friday
      };

      final result = OvertimeService.splitHours(
        dailyHours: dailyHours,
        hourlyRate: 20.0,
        settings: settings,
      );

      expect(result.totalHours, 50.0);
      expect(result.regularHours, 40.0);
      expect(result.overtimeHours, 10.0);
      expect(result.regularPay, 800.0);
      expect(result.overtimePay, 300.0); // 10 * 20 * 1.5
      expect(result.totalPay, 1100.0);
    });

    test('combined daily + weekly overtime — overlap rule', () {
      final settings = OvertimeSettings(
        dailyEnabled: true,
        dailyThresholdHours: 8.0,
        weeklyEnabled: true,
        weeklyThresholdHours: 40.0,
        payMode: 'calculate_pay',
        multiplier: 1.5,
      );

      final dailyHours = {
        DateTime(2026, 8, 3): 10.0, // 2 daily OT
        DateTime(2026, 8, 4): 10.0, // 2 daily OT
        DateTime(2026, 8, 5): 10.0, // 2 daily OT
        DateTime(2026, 8, 6): 10.0, // 2 daily OT
        DateTime(2026, 8, 7): 10.0, // 2 daily OT
      };

      final result = OvertimeService.splitHours(
        dailyHours: dailyHours,
        hourlyRate: 20.0,
        settings: settings,
      );

      // Daily OT: 2+2+2+2+2 = 10
      // Weekly raw: 50, weekly OT: 10
      // Combined OT: 20, clamped to total (50)
      expect(result.totalHours, 50.0);
      expect(result.overtimeHours, 20.0);
      expect(result.regularHours, 30.0);
      expect(result.overtimePay, 600.0); // 20 * 20 * 1.5
      expect(result.totalPay, 1200.0);
    });

    test('hours_only mode — overtime tracked but pay is straight rate', () {
      final settings = OvertimeSettings(
        dailyEnabled: true,
        dailyThresholdHours: 8.0,
        weeklyEnabled: false,
        weeklyThresholdHours: 40.0,
        payMode: 'hours_only',
        multiplier: 1.5,
      );

      final dailyHours = {
        DateTime(2026, 8, 3): 10.0,
        DateTime(2026, 8, 4): 8.0,
      };

      final result = OvertimeService.splitHours(
        dailyHours: dailyHours,
        hourlyRate: 20.0,
        settings: settings,
      );

      expect(result.totalHours, 18.0);
      expect(result.regularHours, 16.0);
      expect(result.overtimeHours, 2.0);
      expect(result.regularPay, 360.0); // all at straight rate
      expect(result.overtimePay, 0.0);
      expect(result.totalPay, 360.0);
    });

    test('clamp guards negative regular hours when combined OT exceeds total', () {
      final settings = OvertimeSettings(
        dailyEnabled: true,
        dailyThresholdHours: 1.0,
        weeklyEnabled: true,
        weeklyThresholdHours: 1.0,
        payMode: 'calculate_pay',
        multiplier: 1.5,
      );

      final dailyHours = {
        DateTime(2026, 8, 3): 2.0,
      };

      final result = OvertimeService.splitHours(
        dailyHours: dailyHours,
        hourlyRate: 20.0,
        settings: settings,
      );

      expect(result.totalHours, 2.0);
      expect(result.regularHours, 0.0); // clamped
      expect(result.overtimeHours, 2.0);
      expect(result.regularPay, 0.0);
      expect(result.overtimePay, 60.0); // 2 * 20 * 1.5
    });
  });
}
