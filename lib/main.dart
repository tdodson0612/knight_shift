// lib/main.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'core/services/supabase_service.dart';
import 'core/services/deep_link_service.dart';
import 'features/billing/billing_screen.dart';
import 'features/splash/splash_router.dart';

/// Global navigator key so the deep-link listener (which has no
/// BuildContext of its own — it's triggered by an OS-level event,
/// not a widget) can push a screen from wherever the user happens
/// to be in the app when the Stripe redirect comes back.
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseService.init();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<CheckoutDeepLinkResult>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    DeepLinkService.instance.init();
    _deepLinkSub = DeepLinkService.instance.events.listen(_handleDeepLink);
  }

  void _handleDeepLink(CheckoutDeepLinkResult result) {
    void push() {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => BillingScreen(checkoutResult: result),
        ),
      );
    }

    // On a cold start the deep link can resolve before the first
    // frame — navigatorKey.currentState isn't attached yet. Defer
    // one frame in that case instead of silently dropping it.
    if (navigatorKey.currentState != null) {
      push();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => push());
    }
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    DeepLinkService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Knight Shift',
      theme: ThemeData(
        useMaterial3: true,
      ),
      // 🔥 SINGLE ENTRY POINT (NO ROOT ROUTER ANYMORE)
      home: const SplashRouter(),
    );
  }
}