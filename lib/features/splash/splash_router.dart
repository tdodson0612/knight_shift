// lib/features/splash/splash_router.dart

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../time_clock/home_screen.dart';
import '../company/company_gate.dart';

class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await SessionService.restoreSession();

    if (!mounted) return;

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text("Loading workspace..."),
            ],
          ),
        ),
      );
    }

    final hasSession =
        SessionService.hasCompany && SessionService.activeUserId != null;

    return hasSession
        ? const HomeScreen()
        : const CompanyGate();
  }
}