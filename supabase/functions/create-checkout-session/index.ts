// supabase/functions/create-checkout-session/index.ts
//
// Called by the Flutter app (authenticated request) when a manager
// taps "Upgrade" on a specific tier. Creates (or reuses) a Stripe
// Customer for the company, then a Checkout Session, and returns
// the URL for the app to open in a browser.
//
// Deploy with JWT verification ON (default) — this must only be
// callable by an authenticated user, unlike the webhook function.

import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe@17";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const PRICE_BY_TIER: Record<string, string | undefined> = {
  starter: Deno.env.get("STRIPE_PRICE_STARTER"),
  professional: Deno.env.get("STRIPE_PRICE_PROFESSIONAL"),
  enterprise: Deno.env.get("STRIPE_PRICE_ENTERPRISE"),
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
      apiVersion: "2024-06-20",
    });

    const authClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization")! } } },
    );

    const { data: userData, error: userError } = await authClient.auth.getUser();
    if (userError || !userData?.user) {
      return new Response(JSON.stringify({ error: "Not authenticated" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const userId = userData.user.id;

    const { companyId, tier } = await req.json();

    if (!companyId || !tier || !PRICE_BY_TIER[tier]) {
      return new Response(
        JSON.stringify({ error: "companyId and a valid tier are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: membership } = await adminClient
      .from("company_members")
      .select("role")
      .eq("company_id", companyId)
      .eq("user_id", userId)
      .maybeSingle();

    if (!membership || !["manager", "admin"].includes(membership.role)) {
      return new Response(
        JSON.stringify({ error: "Only managers can manage billing" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: company } = await adminClient
      .from("companies")
      .select("id, name, stripe_customer_id")
      .eq("id", companyId)
      .single();

    let customerId = company?.stripe_customer_id as string | null;

    if (!customerId) {
      const customer = await stripe.customers.create({
        name: company?.name ?? undefined,
        metadata: { company_id: companyId },
      });
      customerId = customer.id;

      await adminClient
        .from("companies")
        .update({ stripe_customer_id: customerId })
        .eq("id", companyId);
    }

    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      mode: "subscription",
      line_items: [{ price: PRICE_BY_TIER[tier], quantity: 1 }],
      // Custom URL scheme, not a hosted page. The app opens Checkout
      // in the device's external browser (Safari / Chrome), and when
      // Stripe redirects here, the OS hands it straight back to the
      // app instead of loading a webpage — no Universal Links / App
      // Links domain verification needed for knightshift.app.
      // Scheme is registered in ios/Runner/Info.plist
      // (CFBundleURLTypes) and AndroidManifest.xml (intent-filter),
      // and handled in lib/core/services/deep_link_service.dart.
      success_url: "knightshift://billing-success",
      cancel_url: "knightshift://billing-cancelled",
      metadata: { company_id: companyId, tier },
      subscription_data: {
        metadata: { company_id: companyId, tier },
      },
    });

    return new Response(JSON.stringify({ url: session.url }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});