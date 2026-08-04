// lib/core/services/supabase_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static Future<void> init() async {
    await Supabase.initialize(
      url: 'https://ithbdavewhomckokmjzy.supabase.co',
      publishableKey: 'sb_publishable_ePFs47LtiRjvIp2xg0wHwA__EtpyH8V',
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}