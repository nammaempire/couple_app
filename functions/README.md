# Cloud Functions

Two areas: ending a pairing (below), and [Google Play billing](#google-play-billing).

## Ending a pairing

These are 2nd gen functions, written in TypeScript and running on Node 22, in region **`asia-south1`**. When a couple separates, they delete everything the couple shared and unpair both people. Each person's account and `users/{uid}` profile stay, so they can pair again. Auth accounts are never deleted.

| Function | Type | What it does |
|---|---|---|
| `processSeparations` | Scheduled, every 15 min | Ends every couple whose `separation.effectiveAt <= now`, up to 100 per run. `how` is `agreed` if `status == 'agreed'`, otherwise `oneSided`. |
| `finalizeSeparation` | Callable `{coupleId}` | The app calls it when it opens after the separation date. The caller must be a member and the date must have passed. Returns `{status, how}`. |
| `leaveNow` | Callable `{coupleId, confirm: 'LEAVE'}` | A member ends the pairing immediately (`how = 'leftNow'`), whether or not a separation exists. The app gates this behind the app lock or biometrics. |

All three call `endCouple(cid, how)` in `src/endCouple.ts`. It runs these steps in order:

1. **Claim:** writes a lease `ending: {how, startedAt, leaseExpiresAt, attempts}` on the couple doc.
2. **Storage:** deletes everything under `couples/{cid}/` (including `books/`), plus each member's `users/{uid}/backgrounds/`. It keeps `users/{uid}/profile/`.
3. **Subcollections:** deletes every subcollection of the couple doc recursively, including unknown ones.
4. **Invites and pair requests:** deletes `invites` and `pairRequests` docs where `coupleId == cid`.
5. **Users:** for each member, sets `coupleId: null`, deletes `chatLookMode`, `chatLook`, `chatClearedAt` and `mutePartner`, and sets `pairingEndedAt` and `pairingEndedHow`. It only does this if the user doc still points at this couple.
6. **Root doc:** deletes the couple doc last (a recursive delete, so it also catches late writes). A missing couple doc therefore means the job is finished.

Every step is idempotent. If another run holds a live lease, a second caller gets `inProgress`; once the lease expires (10 min, which is longer than any function timeout), the next run takes over and keeps the original `how`.

Callable results: `status` is `ended`, `alreadyEnded` or `inProgress`; `how` is a string or `null`. Errors use these codes: `unauthenticated`, `invalid-argument` (bad `coupleId`, or `confirm` isn't `'LEAVE'`), `permission-denied` (caller isn't a member), and `failed-precondition` (no separation, or "Not yet"; `details.effectiveAt` is an ISO date).

## Google Play billing

| Function | Type | What it does |
|---|---|---|
| `verifyPurchase` | Callable | Verifies a Play purchase with the Android Publisher API (v3) and grants it to the couple, exactly once per purchase token. Then acknowledges it. |
| `playBillingNotifications` | Pub/Sub `play-billing` | Real-time developer notifications. On subscription events it re-fetches the subscription and recomputes premium. On voided purchases it removes an unused book credit (best effort) and marks the purchase voided. |

**Products**

| Product id | Type | Grants |
|---|---|---|
| `premium_monthly`, `premium_yearly` | Subscription | Premium |
| `book_single` | One-time consumable | 1 book credit |
| `gift_premium_1m`, `gift_premium_3m`, `gift_premium_12m` | One-time consumable | 1, 3 or 12 months of premium, plus a gift doc |
| `gift_book` | One-time consumable | 1 book credit, plus a gift doc |

**Callable `verifyPurchase`** (region `asia-south1`)

```
in:  {coupleId, productId, purchaseToken, packageName: 'com.nammaempire.together', gift?: {message ≤ 300}}
out: {status: 'granted' | 'alreadyGranted', premiumUntil?: ISO, bookCredits?: int, giftId?: string}
```

`gift` is required for `gift_*` products. The message may be empty.

Errors:
- `unauthenticated`
- `invalid-argument`: unknown product, missing gift, message too long, or wrong package.
- `permission-denied`: the caller isn't a member, or the token belongs to another couple.
- `failed-precondition`: Play says the purchase is pending, cancelled, unknown, not active, or for a different product; or the couple is ending.
- `unavailable`: Play API error. The client should retry later.

**Premium.** `couples/{cid}.premium` holds `{until, subscriptionUntil, giftUntil, plan, source, updatedAt}`, and `until` is what the app checks:
- **Subscription purchase:** `until = max(old until, subscriptionUntil, giftUntil)`, so a purchase never shortens premium.
- **Gift:** `until = giftUntil = max(now, until) + N months`.
- **RTDN:** recomputes `until = max(subscriptionUntil, giftUntil)`. A revoked, expired, on-hold or paused subscription counts only up to now, so gifted time survives.
- **`subscriptionUntil`:** the latest expiry across the couple's subscription purchase docs, so an old token expiring after an upgrade doesn't cut premium.

**Restore.** Calling `verifyPurchase` again with a known token returns `alreadyGranted` without granting twice. It also retries a failed acknowledgement and, for subscriptions, refreshes the expiry from Play. The app can call it on startup for its active subscription token as a backstop for a missed RTDN.

**Consuming is done by the client.** The server only *acknowledges* (`products.acknowledge` / `subscriptions.acknowledge`). After `verifyPurchase` returns `granted` or `alreadyGranted`, the app must call `completePurchase` / consume (`in_app_purchase`, `consumable: true` / `InAppPurchaseAndroidPlatformAddition.consumePurchase`) for `book_single` and `gift_*`, so they can be bought again. Re-sending an already consumed token is harmless: it returns `alreadyGranted`.

**Records.** `purchases/{sha256(token)}` docs are server-only and kept after a couple ends, for audit. RTDNs for an ended couple are ignored.

### Play setup (once, before deploying)

1. In **Play Console → Setup → API access**, link the Play app to the Google Cloud project `together-48033`.
2. In **Play Console → Users and permissions**, invite the functions' runtime service account (2nd gen default: `PROJECT_NUMBER-compute@developer.gserviceaccount.com`, here `351005784085-compute@developer.gserviceaccount.com`). Give it app access with **View financial data** and **Manage orders and subscriptions**. Permissions can take up to 24h to apply.
3. Create the products with the exact ids above. Subscriptions: `premium_monthly` and `premium_yearly`, each with a base plan. In-app products: `book_single`, `gift_premium_1m`, `gift_premium_3m`, `gift_premium_12m` and `gift_book`.
4. Set up Real-time developer notifications:
   ```sh
   gcloud pubsub topics create play-billing --project together-48033
   gcloud pubsub topics add-iam-policy-binding play-billing --project together-48033 \
     --member=serviceAccount:google-play-developer-notifications@system.gserviceaccount.com \
     --role=roles/pubsub.publisher
   ```
   Then in **Play Console → Monetize → Monetization setup**, set the topic to `projects/together-48033/topics/play-billing`, choose to receive subscriptions and voided purchases, and click **Send test notification**. It's logged as outcome `test`.
5. Deploy: `firebase deploy --only functions`. The deploy creates the Eventarc trigger and Pub/Sub subscription for `playBillingNotifications`.

To test locally against real Play, set `GOOGLE_APPLICATION_CREDENTIALS` to a key for a service account with the same Play permissions. The tests use a fake `PlayVerifier` instead.

## Build and test

```sh
cd functions
npm install
npm run build          # tsc -> lib/
FIREBASE_BIN=/path/to/firebase npm test   # from functions/: build, then emulators:exec --only firestore,storage
```

The tests in `test/` use mocha and run against the Firestore and Storage emulators. They call `fn.run(request)` with fake auth contexts.

## Deploy (after enabling Blaze)

```sh
firebase deploy --only functions --project together-48033
```

`firebase.json` runs `npm run build` as predeploy, so the build happens first. The scheduler needs **Cloud Scheduler**, which is only available on Blaze; the deploy enables the API and creates the job. The first deploy may also ask to enable Cloud Build, Artifact Registry and Eventarc, and to set an Artifact Registry cleanup policy. Say yes to all of them.

## Cost at this scale (tiny)

- **Cloud Scheduler:** 3 jobs per billing account are free, and this uses 1.
- **Invocations:** about 2,900 scheduled runs a month, plus occasional callable calls. The free tier is 2M invocations a month.
- **Firestore:** each tick runs one query, which costs at least 1 read even with no results, so about 2,900 reads a month. The free tier is 50k reads a day. A separation costs roughly one delete per document the couple had.
- **Storage:** list and delete operations only.
- **Billing:** each purchase or notification is one invocation, a few Firestore reads and writes, and one or two Play API calls. The Play API is free, and Pub/Sub's first 10 GiB a month is free.
- **Artifact Registry:** a few cents a month for the container images, or less with the cleanup policy.
