// lib/features/billing/billing_screen.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/session_service.dart';
import '../../core/services/subscription_service.dart';
import '../../core/services/deep_link_service.dart';
import '../../shared/models/subscription_model.dart';

class BillingScreen extends StatefulWidget {
  /// Set when this screen was opened in response to the Stripe
  /// Checkout / Billing Portal redirect deep link (see
  /// DeepLinkService). Null for a normal manual open from the
  /// dashboard.
  final CheckoutDeepLinkResult? checkoutResult;

  const BillingScreen({super.key, this.checkoutResult});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  bool loading = true;
  bool checkingOut = false;
  bool openingPortal = false;
  CompanySubscription? subscription;

  CheckoutDeepLinkResult? _banner;

  @override
  void initState() {
    super.initState();
    _banner = widget.checkoutResult;
    _load();

    // The Stripe webhook updates subscription_status asynchronously,
    // so on a "success" redirect it can occasionally still be
    // in-flight by the time we reload here. One short follow-up
    // reload catches that race without adding real polling.
    if (widget.checkoutResult == CheckoutDeepLinkResult.success) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) {
      setState(() => loading = false);
      return;
    }

    try {
      subscription = await SubscriptionService.getSubscription(companyId);
    } catch (_) {
      subscription = null;
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open the page")),
      );
    }
  }

  Future<void> _upgradeTo(String tier) async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) return;

    setState(() => checkingOut = true);

    try {
      final url = await SubscriptionService.startCheckout(
        companyId: companyId,
        targetTier: tier,
      );
      await _openUrl(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => checkingOut = false);
    }
  }

  Future<void> _manageBilling() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) return;

    setState(() => openingPortal = true);

    try {
      final url = await SubscriptionService.getBillingPortalUrl(companyId);
      await _openUrl(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => openingPortal = false);
    }
  }

  String _statusLabel(CompanySubscription s) {
    if (s.isActive) return "Active";
    if (s.isTrialing) {
      return s.isTrialExpired ? "Trial Expired" : "Trial — ${s.daysLeftInTrial} days left";
    }
    if (s.isPastDue) return "Past Due";
    if (s.isCanceled) return "Canceled";
    return s.status;
  }

  Color _statusColor(CompanySubscription s) {
    if (s.isActive) return Colors.green;
    if (s.isTrialing) return s.isTrialExpired ? Colors.red : Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Billing")),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : subscription == null
              ? const Center(child: Text("Unable to load billing information"))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_banner != null) _checkoutBanner(_banner!),
                    _statusCard(subscription!),
                    const SizedBox(height: 24),
                    const Text(
                      "Plans",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _tierCard(
                      tierKey: "starter",
                      name: "Starter",
                      price: "\$15/mo",
                      tagline: "For small businesses just getting started",
                      features: const [
                        "Scheduling & shift requests",
                        "Time clock",
                        "Basic payroll generation",
                        "Labor & payroll reports",
                      ],
                      isCurrent: subscription!.tier == 'starter',
                    ),
                    _tierCard(
                      tierKey: "professional",
                      name: "Professional",
                      price: "\$50/mo",
                      tagline: "For growing businesses that need deeper insight",
                      features: const [
                        "Everything in Starter",
                        "Team Insights & manager analytics",
                        "Overtime forecasting",
                        "Schedule conflict prediction",
                        "Payroll export to accounting software",
                      ],
                      isCurrent: subscription!.tier == 'professional',
                    ),
                    _tierCard(
                      tierKey: "enterprise",
                      name: "Enterprise",
                      price: "\$100/mo",
                      tagline: "For large or multi-location organizations",
                      features: const [
                        "Everything in Professional",
                        "AI schedule optimization",
                        "Labor cost & compliance monitoring",
                        "Multi-location support",
                        "Custom roles & permissions",
                        "Audit logs & API access",
                      ],
                      isCurrent: subscription!.tier == 'enterprise',
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: openingPortal ? null : _manageBilling,
                      child: Text(openingPortal ? "Opening..." : "Manage Billing"),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Update your payment method, view invoices, or "
                      "cancel your subscription.",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
    );
  }

  Widget _checkoutBanner(CheckoutDeepLinkResult result) {
    final isSuccess = result == CheckoutDeepLinkResult.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isSuccess ? Colors.green : Colors.grey).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isSuccess ? Colors.green : Colors.grey).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle : Icons.info_outline,
            color: isSuccess ? Colors.green : Colors.grey[700],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isSuccess
                  ? "Payment received — thanks! If your plan below doesn't "
                      "look updated yet, pull to refresh in a few seconds."
                  : "Checkout was cancelled — no changes were made.",
              style: TextStyle(
                color: isSuccess ? Colors.green[800] : Colors.grey[700],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _banner = null),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(CompanySubscription s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: _statusColor(s)),
                const SizedBox(width: 8),
                Text(
                  _statusLabel(s),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text("Current plan: ${s.tier[0].toUpperCase()}${s.tier.substring(1)}"),
            if (s.isTrialing && s.trialEnd != null)
              Text("Trial ends: ${_formatDate(s.trialEnd!)}"),
            if (s.currentPeriodEnd != null)
              Text("Renews: ${_formatDate(s.currentPeriodEnd!)}"),
            if (s.isLocked) ...[
              const SizedBox(height: 12),
              const Text(
                "Schedule editing, payroll generation, and employee invites "
                "are currently disabled. Your existing data remains fully "
                "visible — upgrade below to restore full access.",
                style: TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tierCard({
    required String tierKey,
    required String name,
    required String price,
    required String tagline,
    required List<String> features,
    required bool isCurrent,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isCurrent
            ? const BorderSide(color: Colors.blue, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text(price, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: const Text("Current", style: TextStyle(fontSize: 11)),
                    backgroundColor: Colors.blue.withValues(alpha: 0.15),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
            Text(tagline, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            for (final f in features)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.check, size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(child: Text(f, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (!isCurrent)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: checkingOut ? null : () => _upgradeTo(tierKey),
                  child: Text(checkingOut ? "Opening Checkout..." : "Upgrade to $name"),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => "${d.month}/${d.day}/${d.year}";
}