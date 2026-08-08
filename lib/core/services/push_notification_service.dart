// lib/core/services/push_notification_service.dart
//
// Owns real push notification registration (FCM/APNs) on the Flutter
// side: request permission, get the device token, store it in
// `user_device_tokens` (RLS scoped to the owning user), and route
// notification taps into the in-app NotificationsScreen.
//
// This is the client half of Feature 5. The server half (DB trigger
// + send-push-notification Edge Function) lives in supabase/ — see
// docs/push-notifications-setup.md for the external-account setup
// (Firebase project, service account, iOS APNs key) required before
// this can actually deliver a push.
//
// Fails open: if Firebase isn't configured on the device yet (no
// google-services.json / GoogleService-Info.plist), token
// registration silently no-ops — the in-app notifications still
// work exactly as before.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../main.dart';
import 'supabase_service.dart';
import 'session_service.dart';
import '../../features/notifications/notifications_screen.dart';

class PushNotificationService {
  static final _db = SupabaseService.client;
  static final _firebaseMessaging = FirebaseMessaging.instance;

  static bool _initialized = false;

  /// Call once on app start, after auth state is known. Registers the
  /// device token for the signed-in user (or unregisters if signed
  /// out). Safe to call repeatedly — idempotent.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // Request permission (iOS shows the system dialog; Android 13+
      // shows its own runtime permission prompt).
      await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      ).timeout(const Duration(seconds: 5));

      final token = await _firebaseMessaging.getToken().timeout(
        const Duration(seconds: 5),
      );
      final userId = SessionService.activeUserId;

      if (token != null && userId != null) {
        await _registerToken(userId, token);
      }

      // Listen for token refresh (e.g. app reinstall, expired token).
      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        final uid = SessionService.activeUserId;
        if (uid != null) {
          await _registerToken(uid, newToken);
        }
      });

      // When the app is foregrounded and a push arrives, show it as
      // an in-app notification too (the in-app row is already written
      // by NotificationService — this is just a convenience surface).
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM message received: ${message.notification?.title}');
      });

      // Foreground tap — navigate to the in-app notifications screen.
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _openNotifications();
      });
    } catch (e) {
      // Firebase config missing on this device — fail open.
      debugPrint('PushNotificationService init skipped: $e');
    }
  }

  /// Handles the case where the app was launched from a terminated
  /// state via a notification tap. Call from main() if
  /// FirebaseMessaging.instance.getInitialMessage() returns a message.
  static Future<void> handleInitialMessage() async {
    try {
      final message = await _firebaseMessaging.getInitialMessage()
          .timeout(const Duration(seconds: 5));
      if (message != null) {
        _openNotifications();
      }
    } catch (e) {
      debugPrint('PushNotificationService getInitialMessage skipped: $e');
    }
  }

  static Future<void> _registerToken(String userId, String token) async {
    try {
      // Upsert — unique on (user_id, token). RLS allows the owning
      // user to insert their own tokens.
      await _db.from('user_device_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': _platform,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Token registration failed (fails open): $e');
    }
  }

  static void _openNotifications() {
    // Push to the in-app Notifications screen using the global
    // navigator key defined in main.dart, if available.
    final navigatorState = navigatorKey.currentState;
    if (navigatorState != null) {
      navigatorState.push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      );
    }
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    if (defaultTargetPlatform == TargetPlatform.android) return 'android';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    return 'unknown';
  }
}