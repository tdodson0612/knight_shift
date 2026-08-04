// lib/core/services/deep_link_service.dart
//
// Owns all custom-URL-scheme deep link handling for this app.
// This is currently the ONLY consumer of deep links: the two Stripe
// redirects (Checkout success/cancel, Billing Portal return).
//
// Scheme is "knightshift" — registered in ios/Runner/Info.plist
// (CFBundleURLTypes) and android/app/src/main/AndroidManifest.xml
// (intent-filter on MainActivity). If a second deep-link use case
// shows up later, extend this service rather than adding a second
// link listener somewhere else (Rule: one domain, one service).

import 'dart:async';

import 'package:app_links/app_links.dart';

enum CheckoutDeepLinkResult { success, cancelled }

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final _appLinks = AppLinks();
  final _controller = StreamController<CheckoutDeepLinkResult>.broadcast();

  Stream<CheckoutDeepLinkResult> get events => _controller.stream;

  StreamSubscription<Uri>? _sub;
  bool _initialized = false;

  /// Call once, early, from main.dart. Safe to call multiple times —
  /// no-ops after the first.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Cold start: app was launched BY tapping the deep link.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {
      // No initial link, or platform channel not ready yet — ignore.
    }

    // Warm start: app was already running (backgrounded) when the
    // deep link arrived.
    _sub = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  void _handle(Uri uri) {
    if (uri.scheme != 'knightshift') return;

    switch (uri.host) {
      case 'billing-success':
      case 'billing-portal-return':
        _controller.add(CheckoutDeepLinkResult.success);
        break;
      case 'billing-cancelled':
        _controller.add(CheckoutDeepLinkResult.cancelled);
        break;
      default:
        // Unknown host under our scheme — ignore rather than guess.
        break;
    }
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
    _initialized = false;
  }
}