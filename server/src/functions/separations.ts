/**
 * Ending pairings: the scheduled job and the two callables (port of
 * functions/src/index.ts processSeparations / finalizeSeparation / leaveNow).
 */
import { pool } from "../db.js";
import { ApiError } from "../errors.js";
import type { AuthInfo } from "../rules/engine.js";
import { adminQuery } from "../store.js";
import { ts, tsMillis, type Data } from "../values.js";
import { endCouple, howFromSeparation, isDue, type EndResult } from "./endCouple.js";
import { logger } from "./log.js";

export const BATCH = 100;

/** Data the app sends to finalizeSeparation. */
export interface FinalizeSeparationData {
  coupleId: string;
}

/** Data the app sends to leaveNow. */
export interface LeaveNowData {
  coupleId: string;
  confirm: "LEAVE";
}

export interface CallResult {
  status: EndResult["status"];
  how: EndResult["how"] | null;
}

export function requireUid(auth: AuthInfo | null | undefined): string {
  const uid = auth?.uid;
  if (!uid) throw new ApiError("unauthenticated", "Sign in first.");
  return uid;
}

function requireCoupleId(data: unknown): string {
  const cid = (data as { coupleId?: unknown } | null)?.coupleId;
  if (typeof cid !== "string" || cid.length === 0 || cid.length > 128 || cid.includes("/")) {
    throw new ApiError("invalid-argument", "coupleId must be a couple document id.");
  }
  return cid;
}

function requireMember(couple: Data, uid: string): void {
  const members = couple.memberIds;
  if (!Array.isArray(members) || !members.includes(uid)) {
    throw new ApiError("permission-denied", "You are not a member of this couple.");
  }
}

function toCallResult(r: EndResult): CallResult {
  return { status: r.status, how: r.how ?? null };
}

class NotDue extends Error {}

export type SeparationTally = Record<"ended" | "alreadyEnded" | "inProgress" | "notDue" | "failed", number> & { due: number };

/** One scheduler tick: end every couple whose separation.effectiveAt has passed (up to BATCH). */
export async function processSeparations(): Promise<SeparationTally> {
  const due = await adminQuery(pool, {
    collection: "couples",
    where: [["separation.effectiveAt", "<=", ts(Date.now())]],
    orderBy: [["separation.effectiveAt", "asc"]],
    limit: BATCH,
  });
  const tally: SeparationTally = { due: due.length, ended: 0, alreadyEnded: 0, inProgress: 0, notDue: 0, failed: 0 };
  for (const doc of due) {
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
  logger.info("processSeparations: run complete", { ...tally });
  return tally;
}

/**
 * Callable. The app calls it when it opens after the separation date, so the
 * user doesn't wait for the next scheduler tick.
 * Data: { coupleId }. Returns { status: 'ended' | 'alreadyEnded' | 'inProgress', how }.
 */
export async function finalizeSeparation(auth: AuthInfo | null, data: unknown): Promise<CallResult> {
  const uid = requireUid(auth);
  const cid = requireCoupleId(data);
  const r = await endCouple(cid, howFromSeparation, {
    guard: (c) => {
      requireMember(c, uid);
      const sep = c.separation as Data | null | undefined;
      if (!sep?.effectiveAt) {
        throw new ApiError("failed-precondition", "No separation has been requested for this couple.");
      }
      if (!isDue(c)) {
        const at = tsMillis(sep.effectiveAt);
        throw new ApiError("failed-precondition", "Not yet: the separation is not effective until its date.", {
          effectiveAt: at === null ? null : new Date(at).toISOString(),
        });
      }
    },
  });
  return toCallResult(r);
}

/**
 * Callable. Ends the pairing immediately (how = 'leftNow'), with or without a
 * pending separation. The app gates this behind the app lock / biometrics;
 * the server cannot verify that.
 * Data: { coupleId, confirm: 'LEAVE' }.
 */
export async function leaveNow(auth: AuthInfo | null, data: unknown): Promise<CallResult> {
  const uid = requireUid(auth);
  const cid = requireCoupleId(data);
  if ((data as { confirm?: unknown }).confirm !== "LEAVE") {
    throw new ApiError("invalid-argument", "confirm must be 'LEAVE'.");
  }
  const r = await endCouple(cid, "leftNow", { guard: (c) => requireMember(c, uid) });
  return toCallResult(r);
}
