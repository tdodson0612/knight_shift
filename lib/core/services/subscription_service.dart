// lib/core/services/subscription_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';
import '../../shared/models/subscription_model.dart';

class SubscriptionService {
  static final _db = SupabaseService.client;

  static Future<CompanySubscription> getSubscription(
    String companyId,
  ) async {
    final res = await _db
        .from('companies')
        .select('id, subscription_status, subscription_tier, trial_end, current_period_end')
        .eq('id', companyId)
        .single();

    return CompanySubscription.fromMap(res);
  }

  static Future<bool> isLocked(String companyId) async {
    final sub = await getSubscription(companyId);
    return sub.isLocked;
  }

  // ----------------------------
  // STRIPE CHECKOUT
  // ----------------------------
  static Future<String> startCheckout({
    required String companyId,
    required String targetTier,
  }) async {
    final res = await Supabase.instance.client.functions.invoke(
      'create-checkout-session',
      body: {
        'companyId': companyId,
        'tier': targetTier,
      },
    );

    if (res.status != 200) {
      final message = (res.data is Map && res.data['error'] != null)
          ? res.data['error'].toString()
          : 'Checkout could not be started (status ${res.status})';
      throw Exception(message);
    }

    final url = res.data['url'] as String?;
    if (url == null) {
      throw Exception('Checkout session did not return a URL');
    }

    return url;
  }

  // ----------------------------
  // STRIPE CUSTOMER PORTAL — real, calls the deployed Edge Function.
  // Requires the company to already have a Stripe customer (i.e.
  // been through Checkout at least once) — the function returns a
  // clear error if not, surfaced here unchanged.
  //
  // Cancellation is handled inside the Portal itself (Stripe's
  // default configuration allows it), so no separate app-side
  // cancel action is needed.
  // ----------------------------
  static Future<String> getBillingPortalUrl(String companyId) async {
    final res = await Supabase.instance.client.functions.invoke(
      'create-portal-session',
      body: {'companyId': companyId},
    );

    if (res.status != 200) {
      final message = (res.data is Map && res.data['error'] != null)
          ? res.data['error'].toString()
          : 'Billing portal could not be opened (status ${res.status})';
      throw Exception(message);
    }

    final url = res.data['url'] as String?;
    if (url == null) {
      throw Exception('Billing portal session did not return a URL');
    }

    return url;
  }
}