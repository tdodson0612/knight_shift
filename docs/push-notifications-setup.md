# Push Notifications Setup Guide

Knight Shift's real push notifications require external accounts that
cannot be provisioned by writing code alone. This guide steps through
every prerequisite, in order.

## Overview

- Flutter app registers a device token on login (via `firebase_messaging`).
- Token is stored in the `user_device_tokens` table (RLS scoped to the
  owning user).
- When a `notifications` row is inserted, a DB trigger
  (`trg_notify_push_delivery`) calls the `send-push-notification`
  Edge Function via `pg_net`.
- The Edge Function fetches the recipient's device tokens and sends
  one FCM message per token via Firebase Cloud Messaging (FCM v1).

Fails open: if any external piece is not configured, the in-app
notification still works — only the actual OS push is skipped.

---

## Prerequisites (one-time, external)

### 1. Firebase project (Google account)

1. Go to https://console.firebase.google.com/
2. **Add project** (name it e.g. "Knight Shift").
3. **Do not** enable Google Analytics (not needed).
4. Once created, click the gear → **Project settings** → tab
   **Cloud Messaging**.

### 2. Service account JSON + Edge Function secret

1. In the Firebase console: **Project settings** → **Service accounts**.
2. Click **Generate new private key** → save the JSON.
3. Base64-encode it: `base64 -i firebase-service-account.json`
4. In Supabase dashboard:
   - **Project Settings → Edge Functions → Secrets**.
   - Add secret: name `FIREBASE_SERVICE_ACCOUNT`, value = the
     base64 string.

### 3. (iOS only) APNs key — requires a PAID Apple Developer account

1. https://developer.apple.com/account/ → **Certificates, Identifiers
   & Profiles**.
2. **Keys** → **Create a key**. Enable **Apple Push Notification
   service (APNs)**.
3. Download the `.p8` file and note the Key ID and Team ID.
4. Back in Firebase: **Project settings → Cloud Messaging** →
   **iOS app configuration** → upload the `.p8`, enter Key ID / Team ID.

Without this, iOS builds will compile but **will not receive pushes**.

### 4. (iOS) Enable Push capability in the Xcode project

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select the Runner target → **Signing & Capabilities**.
3. Add **Push Notifications** capability.
4. Add **Background Modes** capability, check **Remote notifications**.

This requires Xcode and a signing team, and cannot be done from a
plist edit alone.

### 5. (Android) Firebase config file

1. In Firebase console → **Project settings** → **Your apps** →
   **Add app** → Android.
2. Package name: `com.wiseapps.knightshift` (from
   `android/app/build.gradle.kts`).
3. Download `google-services.json` and place it at
   `android/app/google-services.json`.
4. In `android/build.gradle.kts` (project level), add to plugins:
   ```kotlin
   id("com.google.gms.google-services") version "4.4.2" apply false
   ```
5. In `android/app/build.gradle.kts` (app level), add to plugins:
   ```kotlin
   id("com.google.gms.google-services")
   ```

### 6. (iOS) Firebase config file

1. Firebase console → **Add app** → iOS.
2. Bundle ID: `com.wiseapps.knightshift` (from
   `ios/Runner.xcodeproj`).
3. Download `GoogleService-Info.plist` and place it at
   `ios/Runner/GoogleService-Info.plist` (add to the Runner target).

### 7. Service role key for the DB trigger GUC

1. Supabase dashboard → **Project Settings → API**.
2. Copy the `service_role` key (secret — never ship it in the app).
3. Run in the Supabase SQL editor:
   ```sql
   alter database postgres set app.settings.service_role_key = 'PASTE_KEY_HERE';
   ```
   (Or: Database → Settings → expose it as a custom GUC.)

---

## Deploy the Edge Function

```bash
supabase functions deploy send-push-notification
```

Set the secret (if not already via dashboard):

```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT="<base64-json>"
```

## Apply the migration

```bash
supabase db push
```

---

## Client-side (already coded)

- `lib/core/services/push_notification_service.dart` — FCM init,
  token registration into `user_device_tokens`, and notification-tap
  handling into the in-app `NotificationsScreen`.
- Registered once on app start when the user is signed in. Tokens are
  upserted (unique on `user_id + token`).

## Verification checklist

- [ ] Push arrives on Android (Firebase + google-services.json)
- [ ] Push arrives on iOS (APNs key + Xcode capability)
- [ ] Cold-start tap deep-links to NotificationsScreen
- [ ] Two devices on the same account both receive the push