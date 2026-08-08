// send-push-notification Edge Function
//
// Delivers a real push notification (FCM/APNs) for a `notifications`
// row. Called by the `trg_notify_push_delivery` DB trigger after a
// notification is inserted.
//
// EXTERNAL PREREQUISITES (see docs/push-notifications-setup.md):
//   1. A Firebase project with Cloud Messaging enabled.
//   2. A Firebase service account JSON, base64-encoded, in the
//      `FIREBASE_SERVICE_ACCOUNT` secret.
//   3. (iOS) An APNs key uploaded to Firebase, and the app built
//      with push capability (paid Apple Developer account).
//
// This function reads the recipient's device tokens from
// `user_device_tokens` (service-role bypasses RLS) and sends one
// FCM message per token. It is idempotent and fails open — a push
// delivery error never affects the in-app notification.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const firebaseServiceAccountB64 = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");

const supabase = createClient(supabaseUrl, serviceRoleKey);

interface NotificationRow {
  id: string;
  user_id: string;
  title: string;
  body: string | null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Only the DB trigger (via service role) should call this.
  const auth = req.headers.get("Authorization") ?? "";
  if (auth !== `Bearer ${serviceRoleKey}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  if (!firebaseServiceAccountB64) {
    console.error("FIREBASE_SERVICE_ACCOUNT secret not configured — skipping push.");
    return new Response("FIREBASE_SERVICE_ACCOUNT not configured", { status: 200 });
  }

  let payload: NotificationRow;
  try {
    payload = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  if (!payload.id || !payload.user_id) {
    return new Response("Missing notification_id or user_id", { status: 400 });
  }

  // Fetch the recipient's device tokens.
  const { data: tokens, error: tokenError } = await supabase
    .from("user_device_tokens")
    .select("token, platform")
    .eq("user_id", payload.user_id);

  if (tokenError) {
    console.error("Error fetching device tokens:", tokenError.message);
    return new Response("Token fetch error", { status: 500 });
  }

  if (!tokens || tokens.length === 0) {
    // No registered device — nothing to push. In-app notification still works.
    return new Response("No device tokens", { status: 200 });
  }

  // Build the FCM message. `data` carries the notification id so the
  // app can deep-link to the right record when tapped.
  const message = {
    notification: {
      title: payload.title,
      body: payload.body ?? "",
    },
    data: {
      notification_id: payload.id,
      type: "notification",
    },
  };

  // Send one message per token. FCM v1 API.
  const accessToken = await getAccessToken();
  if (!accessToken) {
    console.error("Could not obtain FCM access token.");
    return new Response("FCM auth error", { status: 500 });
  }

  let sent = 0;
  let failed = 0;

  for (const t of tokens) {
    const fcmMessage = {
      ...message,
      token: t.token,
    };

    const res = await fetch(
      "https://fcm.googleapis.com/v1/projects/" + projectId() + "/messages:send",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({ message: fcmMessage }),
      },
    );

    if (res.ok) {
      sent++;
    } else {
      failed++;
      const body = await res.text();
      console.error(`FCM send failed for token ${t.token}: ${res.status} ${body}`);
    }
  }

  return new Response(JSON.stringify({ sent, failed }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

// --- FCM OAuth2 helpers ---

let cachedToken: { value: string; expiresAt: number } | null = null;

async function getAccessToken(): Promise<string | null> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) {
    return cachedToken.value;
  }

  const sa = JSON.parse(atob(firebaseServiceAccountB64!));
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encodedHeader = btoa(JSON.stringify(header));
  const encodedClaims = btoa(JSON.stringify(claims));
  const signingInput = `${encodedHeader}.${encodedClaims}`;

  const key = await importKey(sa.private_key);
  const signature = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    key,
    new TextEncoder().encode(signingInput),
  );
  const encodedSignature = btoa(String.fromCharCode(...new Uint8Array(signature)));

  const jwt = `${signingInput}.${encodedSignature}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!res.ok) {
    console.error("OAuth token error:", await res.text());
    return null;
  }

  const data = await res.json();
  cachedToken = { value: data.access_token, expiresAt: Date.now() + data.expires_in * 1000 };
  return data.access_token;
}

function projectId(): string {
  const sa = JSON.parse(atob(firebaseServiceAccountB64!));
  return sa.project_id;
}

async function importKey(pem: string): Promise<CryptoKey> {
  const pemContents = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(pemContents);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

  return crypto.subtle.importKey(
    "pkcs8",
    bytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}