// lib/shared/models/availability_model.dart

import 'package:flutter/material.dart' show TimeOfDay;

/// One recurring weekly availability window for a single day.
/// dayOfWeek uses the same convention as DateTime.weekday: 1=Mon..7=Sun.
class AvailabilityWindow {
  final String? id;
  final int dayOfWeek;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  AvailabilityWindow({
    this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });

  factory AvailabilityWindow.fromMap(Map<String, dynamic> map) {
    return AvailabilityWindow(
      id: map['id']?.toString(),
      dayOfWeek: map['day_of_week'] is int
          ? map['day_of_week']
          : int.parse(map['day_of_week'].toString()),
      startTime: _parseTime(map['start_time'].toString()),
      endTime: _parseTime(map['end_time'].toString()),
    );
  }

  Map<String, dynamic> toInsertMap({
    required String companyId,
    required String userId,
  }) {
    return {
      'company_id': companyId,
      'user_id': userId,
      'day_of_week': dayOfWeek,
      'start_time': _formatTime(startTime),
      'end_time': _formatTime(endTime),
    };
  }

  bool contains(DateTime dateTime) {
    if (dateTime.weekday != dayOfWeek) return false;
    final minutes = dateTime.hour * 60 + dateTime.minute;
    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;
    return minutes >= startMinutes && minutes < endMinutes;
  }

  static TimeOfDay _parseTime(String value) {
    // Postgres `time` comes back as "HH:MM:SS".
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return "$h:$m:00";
  }
}