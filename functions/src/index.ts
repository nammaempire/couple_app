import { Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall, type CallableRequest } from "firebase-functions/v2/https";
import { onMessagePublished } from "firebase-functions/v2/pubsub";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { db } from "./admin.js";
import {
  handlePlayNotification,
  verifyPurchase as verifyPurchaseImpl,
  type DeveloperNotification,
  type VerifyPurchaseData,
  type VerifyPurchaseResult,
} from "./billing.js";
import { endCouple, howFromSeparation, isDue, type EndResult } from "./endCouple.js";

export { endCouple } from "./endCouple.js";
export type { VerifyPurchaseData, VerifyPurchaseResult } from "./billing.js";

const REGION = "asia-south1";
const BATCH = 100;

/** Data the app sends to finalizeSeparation. */
export interface FinalizeSeparationData {
  coupleId: string;
}

/** Data the app sends to leaveNow. */
export interface LeaveNowData {
  coupleId: string;
  confirm: "LEAVE";
}

function requireUid(req: CallableRequest<unknown>): string {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  return uid;
}

function requireCoupleId(data: unknown): string {
  const cid = (data as { coupleId?: unknown } | null)?.coupleId;
  if (typeof cid !== "string" || cid.length === 0 || cid.length > 128 || cid.includes("/")) {
    throw new HttpsError("invalid-argument", "coupleId must be a couple document id.");
  }
  return cid;
}

function requireMember(couple: FirebaseFirestore.DocumentData, uid: string): void {
  const members = couple.memberIds;
  if (!Array.isArray(members) || !members.includes(uid)) {
    throw new HttpsError("permission-denied", "You are not a member of this couple.");
  }
}

/**
 * Every 15 minutes: end every couple whose separation.effectiveAt has passed.
 */
export const processSeparations = onSchedule(
  {
    schedule: "every 15 minutes",
    region: REGION,
    timeZone: "Asia/Kolkata",
    timeoutSeconds: 540,
    memory: "512MiB",
    retryCount: 0, // the next tick retries anything left over
  },
  async () => {
    const now = Timestamp.now();
    const due = await db()
      .collection("couples")
      .where("separation.effectiveAt", "<=", now)
      .orderBy("separation.effectiveAt")
      .limit(BATCH)
      .get();
    const tally: Record<string, number> = { ended: 0, alreadyEnded: 0, inProgress: 0, notDue: 0, failed: 0 };
    for (const doc of due.docs) {
      try {
        const r = await endCouple(doc.id, howFromSeparation, {
          // Re-checked inside the claim transaction in case the separation
          // was cancelled since the query ran.
          guard: (c) => {
            if (!isDue(c)) throw new NotDue();
          },
        });
        tally[r.status]++;
      } catch (e) {
        if (e instanceof NotDue) {
          tally.notDue++;
        } else {
          tally.failed++;
          logger.error("processSeparations: endCouple failed", { cid: doc.id, error: String(e) });
        }
      }
    }
    logger.info("processSeparations: run complete", { due: due.size, ...tally });
  },
);

class NotDue extends Error {}

/**
 * Callable. The app calls it when it opens after the separation date, so the
 * user doesn't wait for the next scheduler tick.
 * Data: { coupleId }. Returns { status: 'ended' | 'alreadyEnded' | 'inProgress', how? }.
 */
export const finalizeSeparation = onCall<FinalizeSeparationData, Promise<CallResult>>(
  { region: REGION, timeoutSeconds: 300, memory: "512MiB" },
  async (req) => {
    const uid = requireUid(req);
    const cid = requireCoupleId(req.data);
    const r = await endCouple(cid, howFromSeparation, {
      guard: (c) => {
        requireMember(c, uid);
        if (!c.separation?.effectiveAt) {
          throw new HttpsError("failed-precondition", "No separation has been requested for this couple.");
        }
        if (!isDue(c)) {
          throw new HttpsError("failed-precondition", "Not yet: the separation is not effective until its date.", {
            effectiveAt: (c.separation.effectiveAt as Timestamp).toDate().toISOString(),
          });
        }
      },
    });
    return toCallResult(r);
  },
);

/**
 * Callable. Ends the pairing immediately (how = 'leftNow'), with or without a
 * pending separation. The app gates this behind the app lock / biometrics;
 * the server cannot verify that.
 * Data: { coupleId, confirm: 'LEAVE' }.
 */
export const leaveNow = onCall<LeaveNowData, Promise<CallResult>>(
  { region: REGION, timeoutSeconds: 300, memory: "512MiB" },
  async (req) => {
    const uid = requireUid(req);
    const cid = requireCoupleId(req.data);
    if ((req.data as { confirm?: unknown }).confirm !== "LEAVE") {
      throw new HttpsError("invalid-argument", "confirm must be 'LEAVE'.");
    }
    const r = await endCouple(cid, "leftNow", { guard: (c) => requireMember(c, uid) });
    return toCallResult(r);
  },
);

export interface CallResult {
  status: EndResult["status"];
  how: EndResult["how"] | null;
}

function toCallResult(r: EndResult): CallResult {
  return { status: r.status, how: r.how ?? null };
}

/**
 * Callable. Verifies a Google Play purchase and grants it to the couple, once.
 * Data: { coupleId, productId, purchaseToken, packageName, gift?: { message } }.
 * Returns { status: 'granted' | 'alreadyGranted', premiumUntil?, bookCredits?, giftId? }.
 */
export const verifyPurchase = onCall<VerifyPurchaseData, Promise<VerifyPurchaseResult>>(
  { region: REGION, timeoutSeconds: 60 },
  async (req) => verifyPurchaseImpl(requireUid(req), req.data),
);

/** Pub/Sub messages older than this are dropped instead of retried forever. */
const RTDN_MAX_AGE_MS = 24 * 60 * 60 * 1000;

/**
 * Google Play Real-time developer notifications on topic `play-billing`.
 * Re-fetches subscriptions to keep premium in sync; handles voided purchases.
 */
export const playBillingNotifications = onMessagePublished(
  { topic: "play-billing", region: REGION, retry: true, timeoutSeconds: 60 },
  async (event) => {
    const age = Date.now() - Date.parse(event.time);
    let payload: DeveloperNotification;
    try {
      payload = event.data.message.json as DeveloperNotification;
    } catch {
      logger.error("RTDN: message is not JSON", { messageId: event.data.message.messageId });
      return;
    }
    try {
      const outcome = await handlePlayNotification(payload);
      logger.info("RTDN handled", {
        outcome,
        type: payload.subscriptionNotification?.notificationType ?? (payload.voidedPurchaseNotification ? "voided" : "other"),
      });
    } catch (e) {
      // Thrown errors are transient (Play 429/5xx, Firestore contention):
      // let Pub/Sub retry, but only for a day. Permanent problems are
      // returned as outcomes by handlePlayNotification instead.
      if (age < RTDN_MAX_AGE_MS) throw e;
      logger.error("RTDN failed, dropping", { error: String(e), ageMs: age });
    }
  },
);
