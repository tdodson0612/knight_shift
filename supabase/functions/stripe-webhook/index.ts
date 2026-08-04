// supabase/functions/stripe-webhook/index.ts
//
// Called directly by Stripe, not by the app. Verifies the request
// really came from Stripe via signature check, then updates the
// company's subscription fields accordingly.
//
// Deploy with --no-verify-jwt — Stripe cannot send a Supabase JWT,
// so Supabase's normal auth check must be disabled here. Security
// instead comes entirely from the Stripe signature verification
// below — do not remove that check.

import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe@17";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-06-20",
});

const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

const PRICE_TO_TIER: Record<string, string> = {
  [Deno.env.get("STRIPE_PRICE_STARTER") ?? ""]: "starter",
  [Deno.env.get("STRIPE_PRICE_PROFESSIONAL") ?? ""]: "professional",
  [Deno.env.get("STRIPE_PRICE_ENTERPRISE") ?? ""]: "enterprise",
};

// Maps Stripe's subscription status vocabulary onto ours. Knight
// Shift's own 30-day trial is handled entirely inside the app (not
// via Stripe), so any Stripe subscription reaching us here is
// already past that; less common Stripe states are folded into the
// closest of our four values rather than inventing new ones.
function mapStripeStatus(stripeStatus: string): string {
  switch (stripeStatus) {
    case "active":
    case "trialing":
      return "active";
    case "past_due":
    case "unpaid":
    case "incomplete":
      return "past_due";
    case "canceled":
    case "incomplete_expired":
      return "canceled";
    default:
      return "past_due";
  }
}

async function updateCompanyFromSubscription(
  adminClient: ReturnType<typeof createClient>,
  companyId: string,
  subscription: Stripe.Subscription,
) {
  const priceId = subscription.items.data[0]?.price?.id ?? "";
  const tier = PRICE_TO_TIER[priceId] ?? "starter";
  const status = mapStripeStatus(subscription.status);
  const periodEnd = new Date(subscription.current_period_end * 1000).toISOString();

  await adminClient
    .from("companies")
    .update({
      subscription_status: status,
      subscription_tier: tier,
      stripe_subscription_id: subscription.id,
      current_period_end: periodEnd,
    })
    .eq("id", companyId);
}

Deno.serve(async (req) => {
  const signature = req.headers.get("stripe-signature");
  const body = await req.text();

  if (!signature) {
    return new Response("Missing signature", { status: 400 });
  }

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      body,
      signature,
      webhookSecret,
    );
  } catch (err) {
    return new Response(`Webhook signature verification failed: ${err}`, {
      status: 400,
    });
  }

  const adminClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    switch (event.type) {
      case "checkout.session.completed": {
        const session = event.data.object as Stripe.Checkout.Session;
        const companyId = session.metadata?.company_id;
        if (!companyId || !session.subscription) break;

        const subscription = await stripe.subscriptions.retrieve(
          session.subscription as string,
        );

        await updateCompanyFromSubscription(adminClient, companyId, subscription);
        break;
      }

      case "customer.subscription.updated": {
        const subscription = event.data.object as Stripe.Subscription;
        const companyId = subscription.metadata?.company_id;
        if (!companyId) break;

        await updateCompanyFromSubscription(adminClient, companyId, subscription);
        break;
      }

      case "customer.subscription.deleted": {
        const subscription = event.data.object as Stripe.Subscription;
        const companyId = subscription.metadata?.company_id;
        if (!companyId) break;

        await adminClient
          .from("companies")
          .update({ subscription_status: "canceled" })
          .eq("id", companyId);
        break;
      }

      default:
        break;
    }

    return new Response(JSON.stringify({ received: true }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});