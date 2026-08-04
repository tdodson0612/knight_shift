// lib/core/services/notification_service.dart

import 'supabase_service.dart';
import 'employee_service.dart';
import '../../shared/models/notification_model.dart';

class NotificationService {
  static final _db = SupabaseService.client;

  static Future<List<NotificationModel>> getMyNotifications({
    required String companyId,
    required String userId,
  }) async {
    final res = await _db
        .from('notifications')
        .select()
        .eq('company_id', companyId)
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res)
        .map(NotificationModel.fromMap)
        .toList();
  }

  static Future<int> getUnreadCount({
    required String companyId,
    required String userId,
  }) async {
    final res = await _db
        .from('notifications')
        .select('id')
        .eq('company_id', companyId)
        .eq('user_id', userId)
        .isFilter('read_at', null);

    return List.from(res).length;
  }

  static Future<void> markAsRead(String notificationId) async {
    await _db
        .from('notifications')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('id', notificationId);
  }

  static Future<void> markAllAsRead({
    required String companyId,
    required String userId,
  }) async {
    await _db
        .from('notifications')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('company_id', companyId)
        .eq('user_id', userId)
        .isFilter('read_at', null);
  }

  // ----------------------------
  // CREATION — called by ShiftService / TimeOffService after a
  // relevant state change. Never called directly from UI.
  //
  // relatedId/relatedType let a notification point back at the
  // record it's about (e.g. a shift), so the notification UI can
  // offer a direct action (like one-tap swap accept) instead of just
  // being a text alert. Both optional — most notification types
  // don't need this.
  // ----------------------------

  static Future<void> notifyUser({
    required String companyId,
    required String userId,
    required String type,
    required String title,
    String? body,
    String? relatedId,
    String? relatedType,
  }) async {
    await _db.from('notifications').insert({
      'company_id': companyId,
      'user_id': userId,
      'type': type,
      'title': title,
      'body': body,
      if (relatedId != null) 'related_id': relatedId,
      if (relatedType != null) 'related_type': relatedType,
    });
  }

  /// Notifies every manager in the company. [excludeUserId] skips a
  /// specific user (e.g. don't notify a manager of their own action).
  ///
  /// FIX: previously only matched role == 'manager', silently
  /// excluding 'admin' — every other authorization check in this app
  /// (RoleService.isManager()) treats manager and admin as
  /// equivalent. Admins were never receiving these notifications.
  static Future<void> notifyManagers({
    required String companyId,
    required String type,
    required String title,
    String? body,
    String? excludeUserId,
    String? relatedId,
    String? relatedType,
  }) async {
    final employees = await EmployeeService.getCompanyEmployees(companyId);
    final managers = employees.where((e) {
      final role = e.role.toLowerCase();
      return (role == 'manager' || role == 'admin') &&
          e.userId != excludeUserId;
    });

    if (managers.isEmpty) return;

    final payload = managers
        .map((m) => {
              'company_id': companyId,
              'user_id': m.userId,
              'type': type,
              'title': title,
              'body': body,
              if (relatedId != null) 'related_id': relatedId,
              if (relatedType != null) 'related_type': relatedType,
            })
        .toList();

    await _db.from('notifications').insert(payload);
  }
}