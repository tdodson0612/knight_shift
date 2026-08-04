// supabase/functions/create-portal-session/index.ts
//
// Called by the Flutter app when a manager taps "Manage Billing."
// Verifies the caller is a manager of the company, then creates a
// Stripe Billing Portal session and returns its URL.
//
// Deploy with JWT verification ON (default).

import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe@17";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
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

    const { companyId } = await req.json();

    if (!companyId) {
      return new Response(JSON.stringify({ error: "companyId is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
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
      .select("stripe_customer_id")
      .eq("id", companyId)
      .single();

    const customerId = company?.stripe_customer_id as string | null;

    if (!customerId) {
      return new Response(
        JSON.stringify({
          error:
            "No billing account yet — subscribe to a plan first, then Manage Billing will be available.",
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const session = await stripe.billingPortal.sessions.create({
      customer: customerId,
      // Custom URL scheme — see create-checkout-session/index.ts for
      // why (no Universal Links / App Links domain verification set
      // up for knightshift.app). The app treats this the same as a
      // checkout success (see DeepLinkService).
      return_url: "knightshift://billing-portal-return",
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