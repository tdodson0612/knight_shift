// lib/core/services/time_off_service.dart

import 'supabase_service.dart';
import '../../shared/models/time_off_model.dart';
import 'notification_service.dart';

class TimeOffService {
  static final _db = SupabaseService.client;

  static Future<List<TimeOffRequest>> getCompanyTimeOff(
    String companyId,
  ) async {
    final res = await _db
        .from('time_off_requests')
        .select()
        .eq('company_id', companyId)
        .order('start_date', ascending: false);

    return List<Map<String, dynamic>>.from(res)
        .map(TimeOffRequest.fromMap)
        .toList();
  }

  static Future<List<TimeOffRequest>> getUserTimeOff(
    String companyId,
    String userId,
  ) async {
    final res = await _db
        .from('time_off_requests')
        .select()
        .eq('company_id', companyId)
        .eq('user_id', userId)
        .order('start_date', ascending: false);

    return List<Map<String, dynamic>>.from(res)
        .map(TimeOffRequest.fromMap)
        .toList();
  }

  static Future<void> requestTimeOff({
    required String companyId,
    required String userId,
    required DateTime start,
    required DateTime end,
    String? reason,
  }) async {
    if (end.isBefore(start)) {
      throw Exception("End date must be after start date");
    }

    await _db.from('time_off_requests').insert({
      'company_id': companyId,
      'user_id': userId,
      'start_date': _dateOnly(start),
      'end_date': _dateOnly(end),
      'reason': reason,
      'status': 'pending',
      'status_changed_at': DateTime.now().toIso8601String(),
      'status_changed_by': userId,
    });

    await NotificationService.notifyManagers(
      companyId: companyId,
      type: 'time_off_request',
      title: 'New time off request',
      body:
          'A time off request was submitted for ${_formatDate(start)} → ${_formatDate(end)}.',
      excludeUserId: userId,
    );
  }

  static Future<void> approveTimeOff({
    required String requestId,
    required String managerId,
    String? note,
  }) async {
    final request = await _fetchRequest(requestId);

    await _db.from('time_off_requests').update({
      'status': 'approved',
      'status_changed_at': DateTime.now().toIso8601String(),
      'status_changed_by': managerId,
      'manager_note': note,
    }).eq('id', requestId);

    if (request != null) {
      await NotificationService.notifyUser(
        companyId: request.companyId,
        userId: request.userId,
        type: 'time_off_approved',
        title: 'Time off approved',
        body:
            'Your time off request for ${_formatDate(request.startDate)} → ${_formatDate(request.endDate)} was approved.'
            '${note != null && note.isNotEmpty ? ' Note: $note' : ''}',
      );
    }
  }

  static Future<void> rejectTimeOff({
    required String requestId,
    required String managerId,
    String? note,
  }) async {
    final request = await _fetchRequest(requestId);

    await _db.from('time_off_requests').update({
      'status': 'rejected',
      'status_changed_at': DateTime.now().toIso8601String(),
      'status_changed_by': managerId,
      'manager_note': note,
    }).eq('id', requestId);

    if (request != null) {
      await NotificationService.notifyUser(
        companyId: request.companyId,
        userId: request.userId,
        type: 'time_off_rejected',
        title: 'Time off rejected',
        body:
            'Your time off request for ${_formatDate(request.startDate)} → ${_formatDate(request.endDate)} was rejected.'
            '${note != null && note.isNotEmpty ? ' Note: $note' : ''}',
      );
    }
  }

  static Future<TimeOffRequest?> _fetchRequest(String requestId) async {
    final res = await _db
        .from('time_off_requests')
        .select()
        .eq('id', requestId)
        .maybeSingle();

    if (res == null) return null;
    return TimeOffRequest.fromMap(res);
  }

  static String _dateOnly(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  static String _formatDate(DateTime d) => "${d.month}/${d.day}/${d.year}";
}