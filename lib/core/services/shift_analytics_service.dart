// lib/core/services/shift_analytics_service.dart

import '../../shared/models/shift_model.dart';

class ShiftAnalyticsService {
  static Map<String, double> calculateHoursByUser(
    List<ShiftModel> shifts,
  ) {
    final Map<String, double> result = {};

    for (final s in shifts) {
      if (s.userId == null) continue; // open shift — no assignee yet
      final hours = s.duration.inMinutes / 60.0;
      result[s.userId!] = (result[s.userId!] ?? 0) + hours;
    }

    return result;
  }

  /// Groups total hours by the Monday of each shift's week.
  static Map<String, double> calculateHoursByWeek(
    List<ShiftModel> shifts,
  ) {
    final Map<String, double> result = {};

    for (final s in shifts) {
      if (s.userId == null) continue;
      final weekStart = _startOfWeek(s.startTime);
      final key = _dateKey(weekStart);
      final hours = s.duration.inMinutes / 60.0;
      result[key] = (result[key] ?? 0) + hours;
    }

    return result;
  }

  /// Groups total hours by calendar month.
  static Map<String, double> calculateHoursByMonth(
    List<ShiftModel> shifts,
  ) {
    final Map<String, double> result = {};

    for (final s in shifts) {
      if (s.userId == null) continue;
      final key =
          "${s.startTime.year}-${s.startTime.month.toString().padLeft(2, '0')}";
      final hours = s.duration.inMinutes / 60.0;
      result[key] = (result[key] ?? 0) + hours;
    }

    return result;
  }

  static double totalHours(List<ShiftModel> shifts) {
    double total = 0;
    for (final s in shifts) {
      if (s.userId == null) continue;
      total += s.duration.inMinutes / 60.0;
    }
    return total;
  }

  static DateTime _startOfWeek(DateTime date) {
    final daysFromMonday = date.weekday - DateTime.monday;
    final monday = date.subtract(Duration(days: daysFromMonday));
    return DateTime(monday.year, monday.month, monday.day);
  }

  static String _dateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }
}