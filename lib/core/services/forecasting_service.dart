// lib/core/services/forecasting_service.dart
//
// Pure computation — a historical labor heatmap (day-of-week x
// hour-of-day) built entirely from shifts already loaded elsewhere.
// Deliberately NOT AI/ML demand forecasting — just "here's roughly
// when you've needed people historically," a lighter-weight
// alternative to what enterprise tools charge for.

import '../../shared/models/shift_model.dart';

class ForecastingService {
  /// hours[dayOfWeek 1=Mon..7=Sun][hourOfDay 0-23] = total hours
  /// worked in that slot, across every shift passed in. A shift
  /// spanning multiple hours splits its duration proportionally
  /// across each hour it overlaps.
  static Map<int, Map<int, double>> hoursByDayAndHour(
    List<ShiftModel> shifts,
  ) {
    final Map<int, Map<int, double>> result = {
      for (var d = 1; d <= 7; d++) d: {for (var h = 0; h < 24; h++) h: 0.0},
    };

    for (final s in shifts) {
      if (s.userId == null) continue; // unfilled shifts aren't "worked" yet
      var cursor = s.startTime;
      while (cursor.isBefore(s.endTime)) {
        final hourEnd =
            DateTime(cursor.year, cursor.month, cursor.day, cursor.hour + 1);
        final segmentEnd = hourEnd.isBefore(s.endTime) ? hourEnd : s.endTime;
        final minutes = segmentEnd.difference(cursor).inMinutes;
        result[cursor.weekday]![cursor.hour] =
            (result[cursor.weekday]![cursor.hour] ?? 0) + minutes / 60.0;
        cursor = segmentEnd;
      }
    }

    return result;
  }

  static double maxValue(Map<int, Map<int, double>> data) {
    var max = 0.0;
    for (final row in data.values) {
      for (final v in row.values) {
        if (v > max) max = v;
      }
    }
    return max;
  }
}