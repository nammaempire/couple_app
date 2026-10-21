import { FieldValue, Timestamp, type DocumentData } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { bucket, db } from "./admin.js";

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
   * (e.g. an HttpsError) to refuse; nothing is changed in that case.
   */
  guard?: (couple: DocumentData) => void;
  /** Lease length. A run that crashes is taken over once the lease expires. */
  leaseMs?: number;
}

/** Fields on users/{uid} that belong to the relationship, not the person. */
export const RELATIONSHIP_USER_FIELDS = [
  "chatLookMode",
  "chatLook",
  "chatClearedAt",
  "mutePartner",
] as const;

/** Longer than any function timeout below (max 540 s), so leases never overlap. */
export const DEFAULT_LEASE_MS = 10 * 60 * 1000;

type HowArg = EndHow | ((couple: DocumentData) => EndHow);

/**
 * The `how` for a couple whose separation came due: 'agreed' when both agreed,
 * otherwise 'oneSided' (requested and ignored, or declined).
 */
export function howFromSeparation(couple: DocumentData): EndHow {
  return couple?.separation?.status === "agreed" ? "agreed" : "oneSided";
}

/** True when `separation.effectiveAt` exists and is not in the future. */
export function isDue(couple: DocumentData, now: Timestamp = Timestamp.now()): boolean {
  const at = couple?.separation?.effectiveAt;
  return at instanceof Timestamp && at.toMillis() <= now.toMillis();
}

/**
 * Ends a pairing: deletes everything the couple shared and unpairs both
 * members, keeping each person's own account and profile.
 *
 * Race safety: a transaction first claims the couple by writing an `ending`
 * lease on the root doc ({how, startedAt, leaseExpiresAt, attempts}). A
 * second caller (scheduler vs. callable, or two devices) that finds a live
 * lease returns 'inProgress' without touching anything. If a run dies
 * mid-way, the lease expires and the next run takes over, keeping the
 * original `how`. Every step below is also idempotent, so a resumed run
 * simply finds less to delete.
 *
 * Order: storage, subcollections, invites + pairRequests, users, root doc.
 * The root doc goes last, so "root doc missing" means "fully done".
 */
export async function endCouple(
  cid: string,
  how: HowArg,
  opts: EndOptions = {},
): Promise<EndResult> {
  const firestore = db();
  const coupleRef = firestore.collection("couples").doc(cid);
  const leaseMs = opts.leaseMs ?? DEFAULT_LEASE_MS;

  // 1. Claim.
  const claim = await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(coupleRef);
    if (!snap.exists) return { status: "alreadyEnded" as const };
    const data = snap.data() ?? {};
    opts.guard?.(data);

    const now = Timestamp.now();
    const ending = data.ending as
      | { how?: EndHow; leaseExpiresAt?: Timestamp; attempts?: number }
      | undefined;
    if (ending?.leaseExpiresAt instanceof Timestamp && ending.leaseExpiresAt.toMillis() > now.toMillis()) {
      return { status: "inProgress" as const, how: ending.how };
    }
    // A takeover keeps the first run's `how`.
    const finalHow: EndHow = ending?.how ?? (typeof how === "function" ? how(data) : how);
    tx.update(coupleRef, {
      ending: {
        how: finalHow,
        startedAt: ending ? (data.ending.startedAt ?? FieldValue.serverTimestamp()) : FieldValue.serverTimestamp(),
        leaseExpiresAt: Timestamp.fromMillis(now.toMillis() + leaseMs),
        attempts: (ending?.attempts ?? 0) + 1,
      },
    });
    const memberIds = Array.isArray(data.memberIds)
      ? (data.memberIds as unknown[]).filter((u): u is string => typeof u === "string" && u.length > 0)
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

  // Read members up front: personal files are only removed for users still
  // paired to this couple (or whose doc is gone), never after they re-paired.
  const userRefs = memberIds.map((uid) => firestore.collection("users").doc(uid));
  const userSnaps = userRefs.length ? await firestore.getAll(...userRefs) : [];
  const stillPaired = (i: number) => {
    const s = userSnaps[i];
    return !s.exists || s.get("coupleId") === cid;
  };

  // 2. Storage: the shared prefix, then each member's personal backgrounds.
  counts.storageFiles = await deletePrefix(`couples/${cid}/`);
  for (let i = 0; i < memberIds.length; i++) {
    if (stillPaired(i)) counts.backgroundFiles += await deletePrefix(`users/${memberIds[i]}/backgrounds/`);
  }

  // 3. Every subcollection, known or not, recursively (games/x/secret/...).
  for (const sub of await coupleRef.listCollections()) {
    counts.subcollectionDocs[sub.id] = await recursiveDeleteCounted(sub);
  }

  // 4. Invites and pair requests pointing at this couple.
  counts.invites = await deleteWhere("invites", cid);
  counts.pairRequests = await deleteWhere("pairRequests", cid);

  // 5. Unpair each member (only if still pointing at this couple, so a
  //    re-run never resets pairingEndedAt or clobbers a new pairing).
  for (const ref of userRefs) {
    const result = await firestore.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      if (!s.exists) return "missing" as const;
      if (s.get("coupleId") !== cid) return "skipped" as const;
      const update: Record<string, unknown> = {
        coupleId: null,
        pairingEndedAt: FieldValue.serverTimestamp(),
        pairingEndedHow: finalHow,
      };
      for (const f of RELATIONSHIP_USER_FIELDS) update[f] = FieldValue.delete();
      tx.update(ref, update);
      return "updated" as const;
    });
    if (result === "updated") counts.usersUpdated++;
    else if (result === "missing") counts.usersMissing++;
    else counts.usersSkipped++;
  }

  // 6. Root doc last. recursiveDelete also sweeps anything written into a
  //    subcollection while we were working.
  const late = await recursiveDeleteCounted(coupleRef);
  if (late > 1) counts.subcollectionDocs["(late writes)"] = late - 1;

  logger.info("endCouple: done", { cid, how: finalHow, counts });
  return { status: "ended", how: finalHow, counts };
}

async function deletePrefix(prefix: string): Promise<number> {
  const b = bucket();
  const [files] = await b.getFiles({ prefix });
  if (files.length === 0) return 0;
  await b.deleteFiles({ prefix, force: true });
  return files.length;
}

async function recursiveDeleteCounted(
  ref: FirebaseFirestore.DocumentReference | FirebaseFirestore.CollectionReference,
): Promise<number> {
  const firestore = db();
  const writer = firestore.bulkWriter();
  let n = 0;
  writer.onWriteResult(() => {
    n++;
  });
  await firestore.recursiveDelete(ref, writer);
  await writer.close();
  return n;
}

async function deleteWhere(collection: string, cid: string): Promise<number> {
  const firestore = db();
  const snap = await firestore.collection(collection).where("coupleId", "==", cid).get();
  if (snap.empty) return 0;
  const writer = firestore.bulkWriter();
  for (const d of snap.docs) void writer.delete(d.ref);
  await writer.close();
  return snap.size;
}
