import { createHash } from "node:crypto";
import {
  FieldValue,
  Timestamp,
  type DocumentData,
  type DocumentReference,
  type QuerySnapshot,
  type Transaction,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError } from "firebase-functions/v2/https";
import { db } from "./admin.js";
import { PlayApiError, playVerifier, type SubscriptionPurchaseV2, type SubscriptionState } from "./play.js";

/** The only app whose purchases we accept (android applicationId). */
export const PACKAGE_NAME = "com.nammaempire.together";
export const GIFT_MESSAGE_MAX = 300;

export type ProductKind = "subscription" | "book" | "giftPremium" | "giftBook";
export type Plan = "monthly" | "yearly" | "gift";

interface ProductDef {
  kind: ProductKind;
  plan?: "monthly" | "yearly";
  months?: number;
}

/** Play Console product ids. */
export const PRODUCTS: Readonly<Record<string, ProductDef>> = {
  premium_monthly: { kind: "subscription", plan: "monthly" },
  premium_yearly: { kind: "subscription", plan: "yearly" },
  book_single: { kind: "book" },
  gift_premium_1m: { kind: "giftPremium", months: 1 },
  gift_premium_3m: { kind: "giftPremium", months: 3 },
  gift_premium_12m: { kind: "giftPremium", months: 12 },
  gift_book: { kind: "giftBook" },
};

export interface VerifyPurchaseData {
  coupleId: string;
  productId: string;
  purchaseToken: string;
  packageName: string;
  gift?: { message: string };
}

export interface VerifyPurchaseResult {
  status: "granted" | "alreadyGranted";
  premiumUntil?: string;
  bookCredits?: number;
  giftId?: string;
}

/** Real-time developer notification payload (the decoded Pub/Sub message). */
export interface DeveloperNotification {
  version?: string;
  packageName?: string;
  eventTimeMillis?: string;
  subscriptionNotification?: { version?: string; notificationType: number; purchaseToken: string; subscriptionId?: string };
  oneTimeProductNotification?: { version?: string; notificationType: number; purchaseToken: string; sku?: string };
  voidedPurchaseNotification?: { purchaseToken: string; orderId?: string; productType?: number; refundType?: number };
  testNotification?: { version?: string };
}

/** subscriptionNotification.notificationType values we name explicitly. */
export const SUB_NOTIFICATION = {
  RECOVERED: 1,
  RENEWED: 2,
  CANCELED: 3,
  PURCHASED: 4,
  ON_HOLD: 5,
  IN_GRACE_PERIOD: 6,
  RESTARTED: 7,
  REVOKED: 12,
  EXPIRED: 13,
} as const;

export function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

/** Adds calendar months in UTC, clamping to the month's last day (Jan 31 + 1 = Feb 28/29). */
export function addMonths(ms: number, months: number): number {
  const d = new Date(ms);
  const day = d.getUTCDate();
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + months);
  const lastDay = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
  d.setUTCDate(Math.min(day, lastDay));
  return d.getTime();
}

const ms = (v: unknown): number | null => (v instanceof Timestamp ? v.toMillis() : null);
const ts = (v: number | null): Timestamp | null => (v == null ? null : Timestamp.fromMillis(v));
const max = (...vals: Array<number | null | undefined>): number | null => {
  const xs = vals.filter((v): v is number => typeof v === "number");
  return xs.length ? Math.max(...xs) : null;
};

// ---------------------------------------------------------------------------
// verifyPurchase
// ---------------------------------------------------------------------------

/** Input validation. Returns the normalized data or throws invalid-argument. */
export function parseVerifyData(raw: unknown): VerifyPurchaseData & { product: ProductDef } {
  const d = (raw ?? {}) as Record<string, unknown>;
  const bad = (msg: string) => new HttpsError("invalid-argument", msg);
  const { coupleId, productId, purchaseToken, packageName, gift } = d;
  if (typeof coupleId !== "string" || !coupleId || coupleId.length > 128 || coupleId.includes("/")) {
    throw bad("coupleId must be a couple document id.");
  }
  if (typeof productId !== "string" || !Object.hasOwn(PRODUCTS, productId)) throw bad(`Unknown productId: ${String(productId)}`);
  if (typeof purchaseToken !== "string" || !purchaseToken || purchaseToken.length > 4096) throw bad("purchaseToken is required.");
  if (packageName !== PACKAGE_NAME) throw bad(`packageName must be ${PACKAGE_NAME}.`);
  const product = PRODUCTS[productId];
  const isGift = product.kind === "giftPremium" || product.kind === "giftBook";
  let giftOut: { message: string } | undefined;
  if (isGift) {
    const message = (gift as { message?: unknown } | null | undefined)?.message;
    if (typeof gift !== "object" || gift === null || typeof message !== "string") {
      throw bad("gift: {message} is required for gift products (the message may be empty).");
    }
    if (message.length > GIFT_MESSAGE_MAX) throw bad(`gift.message must be at most ${GIFT_MESSAGE_MAX} characters.`);
    giftOut = { message };
  }
  return { coupleId, productId, purchaseToken, packageName, gift: giftOut, product };
}

interface Verified {
  orderId: string | null;
  purchaseTimeMillis: number | null;
  /** Subscriptions only. */
  expiryMs?: number;
  subscriptionState?: SubscriptionState;
  needsAck: boolean;
}

function playError(e: unknown): HttpsError {
  if (e instanceof PlayApiError && e.isInvalidToken) {
    return new HttpsError("failed-precondition", "Google Play does not recognise this purchase.");
  }
  logger.error("Play API error", { error: String(e) });
  return new HttpsError("unavailable", "Could not reach Google Play. Try again shortly.");
}

function lineItemExpiry(sub: SubscriptionPurchaseV2, productId: string | undefined): number | null {
  const items = sub.lineItems ?? [];
  const item = items.find((i) => i.productId === productId) ?? (productId ? undefined : items[0]);
  const t = item?.expiryTime ? Date.parse(item.expiryTime) : NaN;
  return Number.isFinite(t) ? t : null;
}

async function verifyWithPlay(productId: string, product: ProductDef, token: string): Promise<Verified> {
  const play = playVerifier();
  if (product.kind === "subscription") {
    let sub: SubscriptionPurchaseV2;
    try {
      sub = await play.getSubscription(PACKAGE_NAME, token);
    } catch (e) {
      throw playError(e);
    }
    const state = sub.subscriptionState;
    if (state !== "SUBSCRIPTION_STATE_ACTIVE" && state !== "SUBSCRIPTION_STATE_IN_GRACE_PERIOD") {
      throw new HttpsError("failed-precondition", `Subscription is not active (${state ?? "unknown"}).`, { state });
    }
    if (!sub.lineItems?.some((i) => i.productId === productId)) {
      throw new HttpsError("failed-precondition", "This purchase token is for a different product.");
    }
    const expiryMs = lineItemExpiry(sub, productId);
    if (expiryMs == null) throw new HttpsError("failed-precondition", "Subscription has no expiry time.");
    const item = sub.lineItems.find((i) => i.productId === productId);
    const start = sub.startTime ? Date.parse(sub.startTime) : NaN;
    return {
      orderId: item?.latestSuccessfulOrderId ?? sub.latestOrderId ?? null,
      purchaseTimeMillis: Number.isFinite(start) ? start : null,
      expiryMs,
      subscriptionState: state,
      needsAck: sub.acknowledgementState !== "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    };
  }
  let p;
  try {
    p = await play.getProduct(PACKAGE_NAME, productId, token);
  } catch (e) {
    throw playError(e);
  }
  if (p.productId && p.productId !== productId) {
    throw new HttpsError("failed-precondition", "This purchase token is for a different product.");
  }
  if (p.purchaseState !== 0) {
    const why = p.purchaseState === 2 ? "pending" : p.purchaseState === 1 ? "cancelled" : "not valid";
    throw new HttpsError("failed-precondition", `Purchase is ${why}.`, { purchaseState: p.purchaseState ?? null });
  }
  const t = Number(p.purchaseTimeMillis);
  return {
    orderId: p.orderId ?? null,
    purchaseTimeMillis: Number.isFinite(t) ? t : null,
    needsAck: p.acknowledgementState !== 1,
  };
}

async function acknowledge(productId: string, product: ProductDef, token: string): Promise<void> {
  try {
    if (product.kind === "subscription") await playVerifier().acknowledgeSubscription(PACKAGE_NAME, productId, token);
    else await playVerifier().acknowledgeProduct(PACKAGE_NAME, productId, token);
  } catch (e) {
    // Not fatal: the grant is stored, and the next verifyPurchase call for this
    // token retries the acknowledgement. Unacknowledged purchases are refunded
    // by Play after 3 days, which then arrives as a voided notification.
    logger.warn("acknowledge failed", { productId, error: String(e) });
  }
}

function assertMember(couple: DocumentData | undefined, uid: string): asserts couple is DocumentData {
  if (!couple || !Array.isArray(couple.memberIds) || !couple.memberIds.includes(uid)) {
    throw new HttpsError("permission-denied", "You are not a member of this couple.");
  }
}

/** Premium as stored on couples/{cid}.premium, in millis. */
interface PremiumMs {
  until: number | null;
  subscriptionUntil: number | null;
  giftUntil: number | null;
  plan: Plan | null;
  source: "subscription" | "gift" | null;
}

function readPremium(couple: DocumentData): PremiumMs {
  const p = (couple.premium ?? {}) as DocumentData;
  return {
    until: ms(p.until),
    subscriptionUntil: ms(p.subscriptionUntil),
    giftUntil: ms(p.giftUntil),
    plan: (p.plan as Plan) ?? null,
    source: p.source ?? null,
  };
}

function writePremium(p: PremiumMs) {
  return {
    until: ts(p.until),
    subscriptionUntil: ts(p.subscriptionUntil),
    giftUntil: ts(p.giftUntil),
    plan: p.plan,
    source: p.source,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** Latest expiry across the couple's subscription purchases, with `override` applied to one of them. */
function subscriptionMax(
  subs: QuerySnapshot,
  override?: { id: string; expiryMs: number; productId: string },
): { until: number | null; productId: string | null } {
  let best: { until: number | null; productId: string | null } = { until: null, productId: null };
  const consider = (until: number | null, productId: string | null) => {
    if (until != null && (best.until == null || until > best.until)) best = { until, productId };
  };
  for (const d of subs.docs) {
    if (override && d.id === override.id) continue;
    if (d.get("status") === "voided") continue;
    consider(ms(d.get("expiryTime")), d.get("productId") ?? null);
  }
  if (override) consider(override.expiryMs, override.productId);
  return best;
}

const subsQuery = (cid: string) =>
  db().collection("purchases").where("coupleId", "==", cid).where("kind", "==", "subscription");

/** Recomputes premium from subscription + gift time. Used by RTDN syncs (may shorten). */
function composeSynced(prev: PremiumMs, sub: { until: number | null; productId: string | null }, now: number): PremiumMs {
  const until = max(sub.until, prev.giftUntil) ?? now;
  let plan = prev.plan;
  let source = prev.source;
  if (sub.until != null && sub.until > now) {
    plan = PRODUCTS[sub.productId ?? ""]?.plan ?? prev.plan;
    source = "subscription";
  } else if (prev.giftUntil != null && prev.giftUntil > now) {
    plan = "gift";
    source = "gift";
  }
  return { until, subscriptionUntil: sub.until, giftUntil: prev.giftUntil, plan, source };
}

function resultFor(kind: ProductKind, couple: DocumentData | undefined, status: VerifyPurchaseResult["status"], giftId?: string | null) {
  const r: VerifyPurchaseResult = { status };
  if (kind === "subscription" || kind === "giftPremium") {
    const u = ms(couple?.premium?.until);
    if (u != null) r.premiumUntil = new Date(u).toISOString();
  }
  if (kind === "book" || kind === "giftBook") r.bookCredits = typeof couple?.bookCredits === "number" ? couple.bookCredits : 0;
  if (giftId) r.giftId = giftId;
  return r;
}

/** The callable's body (exported for tests and index.ts). */
export async function verifyPurchase(uid: string, raw: unknown): Promise<VerifyPurchaseResult> {
  const data = parseVerifyData(raw);
  const { coupleId: cid, productId, purchaseToken: token, product } = data;
  const firestore = db();
  const coupleRef = firestore.collection("couples").doc(cid);
  const purchaseRef = firestore.collection("purchases").doc(hashToken(token));

  // Cheap checks before calling Play.
  const [coupleSnap, purchaseSnap] = await firestore.getAll(coupleRef, purchaseRef);
  assertMember(coupleSnap.data(), uid);
  if (purchaseSnap.exists) {
    if (purchaseSnap.get("coupleId") !== cid) {
      throw new HttpsError("permission-denied", "This purchase belongs to another couple.");
    }
    return alreadyGranted(purchaseSnap.data() ?? {}, product, productId, token, cid);
  }

  const v = await verifyWithPlay(productId, product, token);
  const now = Date.now();

  const outcome = await firestore.runTransaction(async (tx) => {
    const p = await tx.get(purchaseRef);
    if (p.exists) {
      if (p.get("coupleId") !== cid) throw new HttpsError("permission-denied", "This purchase belongs to another couple.");
      return { already: true as const, purchase: p.data() ?? {} };
    }
    const cSnap = await tx.get(coupleRef);
    const couple = cSnap.data();
    assertMember(couple, uid);
    if (couple.ending) throw new HttpsError("failed-precondition", "This couple is ending.");
    const subs = product.kind === "subscription" ? await tx.get(subsQuery(cid)) : null;

    const prev = readPremium(couple);
    const coupleUpdate: Record<string, unknown> = {};
    let giftId: string | null = null;
    let newCredits: number | undefined;
    let newUntil: number | null = prev.until;

    switch (product.kind) {
      case "subscription": {
        const sub = subscriptionMax(subs!, { id: purchaseRef.id, expiryMs: v.expiryMs!, productId });
        // A purchase never shortens premium.
        newUntil = max(prev.until, sub.until, prev.giftUntil);
        coupleUpdate.premium = writePremium({
          until: newUntil,
          subscriptionUntil: sub.until,
          giftUntil: prev.giftUntil,
          plan: product.plan!,
          source: "subscription",
        });
        break;
      }
      case "giftPremium": {
        newUntil = addMonths(Math.max(now, prev.until ?? 0), product.months!);
        const active = prev.until != null && prev.until > now && prev.plan != null;
        coupleUpdate.premium = writePremium({
          until: newUntil,
          subscriptionUntil: prev.subscriptionUntil,
          giftUntil: newUntil,
          plan: active ? prev.plan : "gift",
          source: active ? prev.source : "gift",
        });
        break;
      }
      case "book":
      case "giftBook": {
        newCredits = (typeof couple.bookCredits === "number" ? couple.bookCredits : 0) + 1;
        coupleUpdate.bookCredits = newCredits;
        break;
      }
    }

    if (product.kind === "giftPremium" || product.kind === "giftBook") {
      const partner = (couple.memberIds as string[]).find((m) => m !== uid);
      if (!partner) throw new HttpsError("failed-precondition", "There is no partner to send a gift to.");
      const giftRef = coupleRef.collection("gifts").doc();
      giftId = giftRef.id;
      tx.create(giftRef, {
        fromUid: uid,
        toUid: partner,
        kind: product.kind === "giftPremium" ? "premium" : "book",
        months: product.kind === "giftPremium" ? product.months! : null,
        message: data.gift!.message,
        createdAt: FieldValue.serverTimestamp(),
        openedAt: null,
      });
    }

    tx.update(coupleRef, coupleUpdate);
    tx.create(purchaseRef, {
      coupleId: cid,
      uid,
      productId,
      packageName: PACKAGE_NAME,
      orderId: v.orderId,
      kind: product.kind,
      status: "granted",
      grantedAt: FieldValue.serverTimestamp(),
      purchaseTimeMillis: v.purchaseTimeMillis,
      giftId,
      ...(product.kind === "subscription"
        ? { expiryTime: Timestamp.fromMillis(v.expiryMs!), subscriptionState: v.subscriptionState ?? null }
        : {}),
    });

    const r: VerifyPurchaseResult = { status: "granted" };
    if (newUntil != null && (product.kind === "subscription" || product.kind === "giftPremium")) {
      r.premiumUntil = new Date(newUntil).toISOString();
    }
    if (newCredits !== undefined) r.bookCredits = newCredits;
    if (giftId) r.giftId = giftId;
    return { already: false as const, result: r };
  });

  if (outcome.already) return alreadyGranted(outcome.purchase, product, productId, token, cid);
  if (v.needsAck) await acknowledge(productId, product, token);
  logger.info("verifyPurchase: granted", { cid, uid, productId, orderId: v.orderId, result: outcome.result });
  return outcome.result;
}

/**
 * Token seen before for this couple: don't grant again. Best effort, retry the
 * acknowledgement and, for subscriptions, refresh the expiry (restore flow).
 */
async function alreadyGranted(
  purchase: DocumentData,
  product: ProductDef,
  productId: string,
  token: string,
  cid: string,
): Promise<VerifyPurchaseResult> {
  try {
    if (product.kind === "subscription") {
      const sub = await playVerifier().getSubscription(PACKAGE_NAME, token);
      await applySubscriptionState(token, sub);
      if (sub.acknowledgementState === "ACKNOWLEDGEMENT_STATE_PENDING" && sub.subscriptionState === "SUBSCRIPTION_STATE_ACTIVE") {
        await acknowledge(productId, product, token);
      }
    } else {
      const p = await playVerifier().getProduct(PACKAGE_NAME, productId, token);
      if (p.purchaseState === 0 && p.acknowledgementState === 0) await acknowledge(productId, product, token);
    }
  } catch (e) {
    logger.warn("alreadyGranted: refresh skipped", { cid, productId, error: String(e) });
  }
  const couple = (await db().collection("couples").doc(cid).get()).data();
  return resultFor(product.kind, couple, "alreadyGranted", purchase.giftId);
}

// ---------------------------------------------------------------------------
// Real-time developer notifications
// ---------------------------------------------------------------------------

const ENTITLED: ReadonlySet<SubscriptionState | undefined> = new Set<SubscriptionState | undefined>([
  "SUBSCRIPTION_STATE_ACTIVE",
  "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
  "SUBSCRIPTION_STATE_CANCELED", // auto-renew off, but paid up to expiry
]);

export type SyncOutcome = "updated" | "unknownToken" | "coupleGone" | "noExpiry";

/**
 * Stores the subscription's current state on its purchases doc and recomputes
 * the couple's premium = max(subscriptionUntil, giftUntil). Revoked, expired,
 * on-hold and paused subscriptions count only up to now.
 */
export async function applySubscriptionState(
  token: string,
  sub: SubscriptionPurchaseV2,
  opts: { revoked?: boolean } = {},
): Promise<SyncOutcome> {
  const firestore = db();
  const purchaseRef = firestore.collection("purchases").doc(hashToken(token));
  return firestore.runTransaction(async (tx: Transaction) => {
    const p = await tx.get(purchaseRef);
    if (!p.exists) return "unknownToken";
    const cid = p.get("coupleId") as string;
    const coupleRef: DocumentReference = firestore.collection("couples").doc(cid);
    const cSnap = await tx.get(coupleRef);
    if (!cSnap.exists || cSnap.get("ending")) return "coupleGone";
    const subs = await tx.get(subsQuery(cid));

    const now = Date.now();
    const productId = p.get("productId") as string;
    const expiry = lineItemExpiry(sub, productId);
    if (expiry == null) return "noExpiry";
    const entitled = !opts.revoked && ENTITLED.has(sub.subscriptionState);
    const effective = entitled ? expiry : Math.min(expiry, now);

    tx.update(purchaseRef, {
      expiryTime: Timestamp.fromMillis(effective),
      subscriptionState: sub.subscriptionState ?? null,
      ...(opts.revoked ? { status: "voided", voidedAt: FieldValue.serverTimestamp() } : {}),
      syncedAt: FieldValue.serverTimestamp(),
    });
    // The override replaces this token's stale value read in `subs`.
    const best = subscriptionMax(subs, { id: purchaseRef.id, expiryMs: effective, productId });
    const prev = readPremium(cSnap.data() ?? {});
    tx.update(coupleRef, { premium: writePremium(composeSynced(prev, best, now)) });
    return "updated";
  });
}

/** Thrown for failures worth a Pub/Sub retry. */
export class TransientError extends Error {}

/** Handles one decoded RTDN. Returns a short label (logged; asserted in tests). */
export async function handlePlayNotification(n: DeveloperNotification): Promise<string> {
  if (n.packageName && n.packageName !== PACKAGE_NAME) return "otherPackage";
  if (n.testNotification) return "test";

  if (n.subscriptionNotification) {
    const { purchaseToken: token, notificationType } = n.subscriptionNotification;
    const exists = (await db().collection("purchases").doc(hashToken(token)).get()).exists;
    // Not verified by the app yet: verifyPurchase will grant it.
    if (!exists) return "unknownToken";
    let sub: SubscriptionPurchaseV2;
    try {
      sub = await playVerifier().getSubscription(PACKAGE_NAME, token);
    } catch (e) {
      if (e instanceof PlayApiError && e.isTransient) throw new TransientError(e.message);
      logger.error("RTDN: subscription lookup failed", { notificationType, error: String(e) });
      return "lookupFailed";
    }
    return applySubscriptionState(token, sub, { revoked: notificationType === SUB_NOTIFICATION.REVOKED });
  }

  if (n.voidedPurchaseNotification) return handleVoided(n.voidedPurchaseNotification);

  if (n.oneTimeProductNotification) return "oneTimeIgnored"; // granted via verifyPurchase
  return "ignored";
}

/**
 * A refund or chargeback. Book credits: remove one if the couple still has
 * any (best effort: credits aren't tied to individual purchases). Gifted
 * premium time is not clawed back; the purchase is only marked voided.
 * Subscriptions are treated as revoked.
 */
async function handleVoided(v: NonNullable<DeveloperNotification["voidedPurchaseNotification"]>): Promise<string> {
  const firestore = db();
  const purchaseRef = firestore.collection("purchases").doc(hashToken(v.purchaseToken));
  const snap = await purchaseRef.get();
  if (!snap.exists) return "unknownToken";
  if (snap.get("status") === "voided") return "alreadyVoided";

  if (snap.get("kind") === "subscription") {
    let sub: SubscriptionPurchaseV2;
    try {
      sub = await playVerifier().getSubscription(PACKAGE_NAME, v.purchaseToken);
    } catch {
      sub = { subscriptionState: "SUBSCRIPTION_STATE_EXPIRED", lineItems: [{ productId: snap.get("productId"), expiryTime: new Date().toISOString() }] };
    }
    return applySubscriptionState(v.purchaseToken, sub, { revoked: true });
  }

  return firestore.runTransaction(async (tx) => {
    const p = await tx.get(purchaseRef);
    if (!p.exists || p.get("status") === "voided") return "alreadyVoided";
    const kind = p.get("kind") as ProductKind;
    const coupleRef = firestore.collection("couples").doc(p.get("coupleId") as string);
    const c = await tx.get(coupleRef);
    let creditRemoved = false;
    if ((kind === "book" || kind === "giftBook") && c.exists && !c.get("ending")) {
      const credits = c.get("bookCredits");
      if (typeof credits === "number" && credits > 0) {
        tx.update(coupleRef, { bookCredits: credits - 1 });
        creditRemoved = true;
      }
    }
    tx.update(purchaseRef, {
      status: "voided",
      voidedAt: FieldValue.serverTimestamp(),
      refundType: v.refundType ?? null,
      creditRemoved,
    });
    return creditRemoved ? "voidedCreditRemoved" : "voided";
  });
}
