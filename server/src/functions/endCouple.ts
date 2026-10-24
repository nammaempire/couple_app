/**
 * Ending a pairing (port of functions/src/endCouple.ts to Postgres + bucket).
 *
 * Steps, in order:
 *  1. Claim: a transaction locks the couple row and writes an `ending` lease
 *     {how, startedAt, leaseExpiresAt, attempts}. A live lease → 'inProgress'.
 *  2. Storage: deletes `couples/{cid}/` and each still-paired member's
 *     `users/{uid}/backgrounds/` (profile photos are kept).
 *  3–6. One transaction: deletes `invites` and `pairRequests` with
 *     coupleId == cid, unpairs each member still pointing at this couple, and
 *     deletes the couple doc with every subcollection (deleteRecursive). The
 *     couple doc therefore disappears together with the rest: "couple doc
 *     missing" still means "fully done".
 *
 * Every step is idempotent; a run that dies is taken over after the lease
 * expires and keeps the first run's `how`.
 */
import { pool, tx, type Client } from "../db.js";
import { getBucket } from "../files.js";
import { COLLECTIONS, quoteIdent as q } from "../schema.js";
import { adminGet, adminQuery, adminWrite, deleteRecursive } from "../store.js";
import { ts, tsMillis, type Data } from "../values.js";
import { logger } from "./log.js";

export type EndHow = "agreed" | "oneSided" | "leftNow";

export type EndStatus =
  /** This run finished the cleanup. */
  | "ended"
  /** The couple doc no longer exists: an earlier run already finished. */
  | "alreadyEnded"
  /** Another run holds a live lease on this couple; it will finish the job. */
  | "inProgress";

export interface EndCounts {
  storageFiles: number;
  backgroundFiles: number;
  subcollectionDocs: Record<string, number>;
  invites: number;
  pairRequests: number;
  usersUpdated: number;
  usersMissing: number;
  usersSkipped: number;
}

export interface EndResult {
  status: EndStatus;
  how?: EndHow;
  counts?: EndCounts;
}

export interface EndOptions {
  /**
   * Runs inside the claim transaction against the fresh couple doc. Throw
   * (e.g. an ApiError) to refuse; nothing is changed in that case.
   */
  guard?: (couple: Data) => void;
  /** Lease length. A run that crashes is taken over once the lease expires. */
  leaseMs?: number;
}

/** Fields on users/{uid} that belong to the relationship, not the person. */
export const RELATIONSHIP_USER_FIELDS = ["chatLookMode", "chatLook", "chatClearedAt", "mutePartner"] as const;

/** Longer than any request/job runs, so leases never overlap. */
export const DEFAULT_LEASE_MS = 10 * 60 * 1000;

type HowArg = EndHow | ((couple: Data) => EndHow);

/** 'agreed' when both agreed, otherwise 'oneSided' (requested and ignored, or declined). */
export function howFromSeparation(couple: Data): EndHow {
  const sep = couple?.separation as Data | null | undefined;
  return sep?.status === "agreed" ? "agreed" : "oneSided";
}

/** True when `separation.effectiveAt` exists and is not in the future. */
export function isDue(couple: Data, now: number = Date.now()): boolean {
  const sep = couple?.separation as Data | null | undefined;
  const at = tsMillis(sep?.effectiveAt);
  return at !== null && at <= now;
}

interface Ending {
  how?: EndHow;
  startedAt?: unknown;
  leaseExpiresAt?: unknown;
  attempts?: number;
}

/** Subcollection name → tables holding it (and anything nested under it). */
const SUBCOLLECTION_TABLES: Array<{ name: string; table: string; col: string }> = COLLECTIONS.filter((d) =>
  d.pattern.startsWith("couples/{coupleId}/"),
).map((d) => ({ name: d.pattern.split("/")[2], table: d.table, col: d.parentCols[0] }));

export async function endCouple(cid: string, how: HowArg, opts: EndOptions = {}): Promise<EndResult> {
  const couplePath = `couples/${cid}`;
  const leaseMs = opts.leaseMs ?? DEFAULT_LEASE_MS;

  // 1. Claim.
  const claim = await tx(async (c) => {
    const snap = await adminGet(c, couplePath, true);
    if (!snap.exists) return { status: "alreadyEnded" as const };
    const data = snap.data ?? {};
    opts.guard?.(data);

    const now = Date.now();
    const ending = (data.ending ?? undefined) as Ending | undefined;
    const lease = tsMillis(ending?.leaseExpiresAt);
    if (lease !== null && lease > now) {
      return { status: "inProgress" as const, how: ending?.how };
    }
    // A takeover keeps the first run's `how`.
    const finalHow: EndHow = ending?.how ?? (typeof how === "function" ? how(data) : how);
    await adminWrite(c, {
      op: "update",
      path: couplePath,
      data: {
        ending: {
          how: finalHow,
          startedAt: (ending ? ((ending.startedAt as Data | undefined) ?? ts(now)) : ts(now)) as Data,
          leaseExpiresAt: ts(now + leaseMs),
          attempts: (typeof ending?.attempts === "number" ? ending.attempts : 0) + 1,
        },
      },
    });
    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.filter((u): u is string => typeof u === "string" && u.length > 0)
      : [];
    return { status: "claimed" as const, how: finalHow, memberIds };
  });

  if (claim.status !== "claimed") {
    logger.info("endCouple: nothing to do", { cid, status: claim.status });
    return { status: claim.status, how: claim.status === "inProgress" ? claim.how : undefined };
  }

  const { how: finalHow, memberIds } = claim;
  const counts: EndCounts = {
    storageFiles: 0,
    backgroundFiles: 0,
    subcollectionDocs: {},
    invites: 0,
    pairRequests: 0,
    usersUpdated: 0,
    usersMissing: 0,
    usersSkipped: 0,
  };
  logger.info("endCouple: start", { cid, how: finalHow, memberIds });

  // Personal files are only removed for users still paired to this couple
  // (or whose doc is gone), never after they re-paired.
  const users = await Promise.all(memberIds.map((uid) => adminGet(pool, `users/${uid}`)));
  const stillPaired = (i: number) => !users[i].exists || users[i].data?.coupleId === cid;

  // 2. Storage: the shared prefix, then each member's personal backgrounds.
  const bucket = getBucket();
  counts.storageFiles = await bucket.deletePrefix(`couples/${cid}/`);
  for (let i = 0; i < memberIds.length; i++) {
    if (stillPaired(i)) counts.backgroundFiles += await bucket.deletePrefix(`users/${memberIds[i]}/backgrounds/`);
  }

  // 3–6. Documents, atomically.
  await tx(async (c) => {
    // Serialize with writers of the couple doc; a parallel takeover that got
    // here first leaves nothing to do.
    const root = await adminGet(c, couplePath, true);
    if (!root.exists) return;

    const sub = await countSubcollections(c, cid);

    // 4. Invites and pair requests pointing at this couple.
    counts.invites = await deleteWhere(c, "invites", cid);
    counts.pairRequests = await deleteWhere(c, "pairRequests", cid);

    // 5. Unpair each member (only if still pointing at this couple, so a
    //    re-run never resets pairingEndedAt or clobbers a new pairing).
    for (const uid of memberIds) {
      const path = `users/${uid}`;
      const u = await adminGet(c, path, true);
      if (!u.exists) {
        counts.usersMissing++;
        continue;
      }
      if (u.data?.coupleId !== cid) {
        counts.usersSkipped++;
        continue;
      }
      const update: Data = {
        coupleId: null,
        pairingEndedAt: { $sv: "serverTimestamp" },
        pairingEndedHow: finalHow,
      };
      for (const f of RELATIONSHIP_USER_FIELDS) update[f] = { $sv: "delete" };
      await adminWrite(c, { op: "update", path, data: update });
      counts.usersUpdated++;
    }

    // 3 + 6. Every subcollection (nested too, even under missing parents)
    //        and the root doc.
    const removed = await deleteRecursive(c, couplePath);
    counts.subcollectionDocs = sub;
    const counted = Object.values(sub).reduce((a, b) => a + b, 0);
    const late = removed - 1 - counted;
    if (late > 0) counts.subcollectionDocs["(late writes)"] = late;
  });

  // 7. Storage again: members could still upload while steps 3–6 ran. Now
  // the couple doc is gone, the storage rules refuse new uploads, so this
  // sweep leaves nothing behind.
  counts.storageFiles += await bucket.deletePrefix(`couples/${cid}/`);

  logger.info("endCouple: done", { cid, how: finalHow, counts });
  return { status: "ended", how: finalHow, counts };
}

async function countSubcollections(c: Client, cid: string): Promise<Record<string, number>> {
  const out: Record<string, number> = {};
  for (const t of SUBCOLLECTION_TABLES) {
    const r = await c.query<{ n: number }>(`SELECT count(*)::int AS n FROM ${q(t.table)} WHERE ${q(t.col)} = $1`, [cid]);
    const n = r.rows[0]?.n ?? 0;
    if (n > 0) out[t.name] = (out[t.name] ?? 0) + n;
  }
  return out;
}

async function deleteWhere(c: Client, collection: string, cid: string): Promise<number> {
  const docs = await adminQuery(c, { collection, where: [["coupleId", "==", cid]], limit: 1000 });
  for (const d of docs) await adminWrite(c, { op: "delete", path: d.path });
  // More than one page is not expected; loop to be safe.
  if (docs.length === 1000) return docs.length + (await deleteWhere(c, collection, cid));
  return docs.length;
}
