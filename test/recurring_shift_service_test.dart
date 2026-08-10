import 'package:flutter_test/flutter_test.dart';
import 'package:knight_shift/core/services/shift_service.dart';

void main() {
  group('ShiftService._datesForRecurrence', () {
    test('generates dates only on selected weekdays within inclusive range', () {
      final start = DateTime(2026, 8, 3); // Monday
      final end = DateTime(2026, 8, 9);   // Sunday
      final days = {1, 3, 5}; // Mon, Wed, Fri

      final dates = ShiftService.datesForRecurrence(start, end, days);

      expect(dates, hasLength(3));
      expect(dates[0], DateTime(2026, 8, 3));
      expect(dates[1], DateTime(2026, 8, 5));
      expect(dates[2], DateTime(2026, 8, 7));
    });

    test('includes boundary dates when they match selected days', () {
      final start = DateTime(2026, 8, 3); // Monday
      final end = DateTime(2026, 8, 3);   // same day
      final days = {1};

      final dates = ShiftService.datesForRecurrence(start, end, days);

      expect(dates, hasLength(1));
      expect(dates[0], DateTime(2026, 8, 3));
    });

    test('returns empty when no days match in range', () {
      final start = DateTime(2026, 8, 3); // Monday
      final end = DateTime(2026, 8, 4);   // Tuesday
      final days = {3, 5}; // Wed, Fri

      final dates = ShiftService.datesForRecurrence(start, end, days);

      expect(dates, isEmpty);
    });

    test('normalizes start date to midnight', () {
      final start = DateTime(2026, 8, 3, 15, 30); // Monday with time
      final end = DateTime(2026, 8, 5);            // Wednesday
      final days = {1, 3};

      final dates = ShiftService.datesForRecurrence(start, end, days);

      expect(dates, hasLength(2));
      for (final d in dates) {
        expect(d.hour, 0);
        expect(d.minute, 0);
        expect(d.second, 0);
        expect(d.millisecond, 0);
        expect(d.microsecond, 0);
      }
    });
  });
}
