import 'package:flutter_test/flutter_test.dart';
import 'package:knight_shift/core/services/labor_budget_service.dart';
import 'package:knight_shift/shared/models/labor_budget_settings_model.dart';
import 'package:knight_shift/shared/models/shift_model.dart';
import 'package:knight_shift/shared/models/overtime_settings_model.dart';

void main() {
  group('LaborBudgetService', () {
    final monday = DateTime(2026, 8, 3, 9, 0);
    final tuesday = DateTime(2026, 8, 4, 9, 0);

    ShiftModel makeShift(String id, DateTime start, DateTime end, String? userId) {
      return ShiftModel(
        id: id,
        companyId: 'company-1',
        userId: userId,
        startTime: start,
        endTime: end,
      );
    }

    group('exceedsBudget', () {
      test('disabled budget never exceeds', () {
        final budget = LaborBudgetSettings(enabled: false, amount: 100.0);
        expect(LaborBudgetService.exceedsBudget(projectedCost: 200.0, budget: budget), isFalse);
      });

      test('zero budget never exceeds', () {
        final budget = LaborBudgetSettings(enabled: true, amount: 0.0);
        expect(LaborBudgetService.exceedsBudget(projectedCost: 200.0, budget: budget), isFalse);
      });

      test('projected cost at budget limit does not exceed', () {
        final budget = LaborBudgetSettings(enabled: true, amount: 100.0);
        expect(LaborBudgetService.exceedsBudget(projectedCost: 100.0, budget: budget), isFalse);
      });

      test('projected cost above budget exceeds', () {
        final budget = LaborBudgetSettings(enabled: true, amount: 100.0);
        expect(LaborBudgetService.exceedsBudget(projectedCost: 101.0, budget: budget), isTrue);
      });
    });

    group('projectedWeeklyHours', () {
      test('sums only matching user shifts in week', () {
        final shifts = [
          makeShift('s1', monday, monday.add(const Duration(hours: 8)), 'user-1'),
          makeShift('s2', monday, monday.add(const Duration(hours: 8)), 'user-2'),
        ];

        final hours = LaborBudgetService.projectedWeeklyHours(
          shifts: shifts,
          newStart: tuesday,
          newEnd: tuesday.add(const Duration(hours: 4)),
          userId: 'user-1',
        );

        expect(hours, 12.0); // 8 + 4
      });

      test('ignores shifts outside the week', () {
        final outsideWeek = DateTime(2026, 7, 27, 9, 0); // previous week
        final shifts = [
          makeShift('s1', outsideWeek, outsideWeek.add(const Duration(hours: 8)), 'user-1'),
        ];

        final hours = LaborBudgetService.projectedWeeklyHours(
          shifts: shifts,
          newStart: monday,
          newEnd: monday.add(const Duration(hours: 4)),
          userId: 'user-1',
        );

        expect(hours, 4.0); // only the new shift
      });
    });

    group('crossesOvertimeThreshold', () {
      test('weekly disabled never crosses', () {
        final ot = const OvertimeSettings(
          dailyEnabled: false,
          dailyThresholdHours: 8.0,
          weeklyEnabled: false,
          weeklyThresholdHours: 40.0,
          payMode: 'hours_only',
          multiplier: 1.5,
        );
        expect(LaborBudgetService.crossesOvertimeThreshold(projectedHours: 50.0, overtime: ot), isFalse);
      });

      test('projected hours at threshold do not cross', () {
        final ot = OvertimeSettings(
          dailyEnabled: false,
          dailyThresholdHours: 8.0,
          weeklyEnabled: true,
          weeklyThresholdHours: 40.0,
          payMode: 'hours_only',
          multiplier: 1.5,
        );
        expect(LaborBudgetService.crossesOvertimeThreshold(projectedHours: 40.0, overtime: ot), isFalse);
      });

      test('projected hours above threshold cross', () {
        final ot = OvertimeSettings(
          dailyEnabled: false,
          dailyThresholdHours: 8.0,
          weeklyEnabled: true,
          weeklyThresholdHours: 40.0,
          payMode: 'hours_only',
          multiplier: 1.5,
        );
        expect(LaborBudgetService.crossesOvertimeThreshold(projectedHours: 41.0, overtime: ot), isTrue);
      });
    });
  });
}
