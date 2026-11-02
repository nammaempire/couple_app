/**
 * Deleting an account ("Delete my account" in the app; required by Google
 * Play and Apple).
 *
 * Steps, each safe to repeat if a run dies part-way:
 *  1. The pairing ends at once, as with "leave now": everything the couple
 *     shared (chat, memories, plans, vault, files…) is deleted for both, and
 *     the partner sees that the pairing ended. A couple of one (still waiting
 *     for a partner) is deleted too.
 *  2. The person's own records: their profile with its devices, security
 *     notices and push tokens; the phone-number lookup that points at them;
 *     pair requests they sent or received; invites they made.
 *  3. Their files (profile photo, chat backgrounds).
 *  4. Their Firebase sign-in, when the server has the Firebase service
 *     account (otherwise the app deletes it itself, right after).
 *
 * Kept: records of Google Play purchases (`purchases/…`), which hold no
 * personal details beyond the couple and buyer ids and are needed for
 * refunds and tax. The privacy policy says so.
 *
 * The call must come from a sign-in confirmed in the last few minutes
 * (password, Google or SMS again), so a borrowed unlocked phone can't do it.
 */
import { getAuth } from "firebase-admin/auth";
import { config } from "../config.js";
import { pool, tx } from "../db.js";
import { ApiError } from "../errors.js";
import { getBucket } from "../files.js";
import { pushApp } from "../push/fcm.js";
import type { AuthInfo } from "../rules/engine.js";
import { adminGet, adminQuery, adminWrite, deleteRecursive } from "../store.js";
import { endCouple } from "./endCouple.js";
import { logger } from "./log.js";
import { requireUid } from "./separations.js";

/** How recent the sign-in must be (Firebase's `auth_time`). */
export const RECENT_SIGN_IN_MS = 10 * 60 * 1000;

export interface DeleteAccountResult {
  status: "deleted";
  /** True when this server also deleted the Firebase sign-in. */
  signInDeleted: boolean;
}

export interface DeleteAccountCounts {
  coupleEnded: boolean;
  phoneIndex: number;
  pairRequests: number;
  invites: number;
  userDocs: number;
  files: number;
}

/** Deletes the Firebase sign-in; false when the server can't (no service account). */
export type SignInDeleter = (uid: string) => Promise<boolean>;

const firebaseDeleter: SignInDeleter = async (uid) => {
  const app = pushApp();
  if (!app) return false;
  try {
    await getAuth(app).deleteUser(uid);
  } catch (e) {
    if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
  }
  return true;
};

let signInDeleter: SignInDeleter = firebaseDeleter;

/** Tests swap in a fake. */
export function setSignInDeleter(d: SignInDeleter | null): void {
  signInDeleter = d ?? firebaseDeleter;
}

function requireRecentSignIn(auth: AuthInfo): void {
  const t = Number((auth.token as Record<string, unknown> | undefined)?.auth_time);
  if (!Number.isFinite(t) || Date.now() - t * 1000 > RECENT_SIGN_IN_MS) {
    throw new ApiError(
      "failed-precondition",
      "requires-recent-login: confirm it's you again, then delete the account.",
    );
  }
}

export async function deleteAccount(auth: AuthInfo | null, data: unknown): Promise<DeleteAccountResult> {
  const uid = requireUid(auth);
  if ((data as { confirm?: unknown } | null)?.confirm !== "DELETE") {
    throw new ApiError("invalid-argument", 'Send {confirm: "DELETE"}.');
  }
  requireRecentSignIn(auth!);

  const counts: DeleteAccountCounts = { coupleEnded: false, phoneIndex: 0, pairRequests: 0, invites: 0, userDocs: 0, files: 0 };
  logger.info("deleteAccount: start", { uid });

  // 1. The pairing (or the couple of one waiting for a partner).
  const user = await adminGet(pool, `users/${uid}`);
  const cid = user.data?.coupleId;
  if (typeof cid === "string" && cid.length > 0) {
    const couple = await adminGet(pool, `couples/${cid}`);
    const members = couple.data?.memberIds;
    if (couple.exists && Array.isArray(members) && members.includes(uid)) {
      const r = await endCouple(cid, "leftNow", {
        guard: (c) => {
          if (!Array.isArray(c.memberIds) || !c.memberIds.includes(uid)) {
            throw new ApiError("aborted", "The pairing changed. Try again.");
          }
        },
      });
      if (r.status === "inProgress") {
        throw new ApiError("aborted", "Your pairing is already being ended. Try again in a few minutes.");
      }
      counts.coupleEnded = true;
    }
  }

  // 2. Their own records, in one transaction.
  await tx(async (c) => {
    const del = async (collection: string, field: string): Promise<number> => {
      let n = 0;
      for (;;) {
        const docs = await adminQuery(c, { collection, where: [[field, "==", uid]], limit: 500 });
        for (const d of docs) await adminWrite(c, { op: "delete", path: d.path });
        n += docs.length;
        if (docs.length < 500) return n;
      }
    };
    counts.phoneIndex = await del("phoneIndex", "uid");
    counts.pairRequests = (await del("pairRequests", "fromUid")) + (await del("pairRequests", "toUid"));
    counts.invites = await del("invites", "createdBy");
    counts.userDocs = await deleteRecursive(c, `users/${uid}`);
  });

  // 3. Files.
  counts.files = await getBucket().deletePrefix(`users/${uid}/`);

  // 4. The sign-in.
  let signInDeleted = false;
  try {
    signInDeleted = await signInDeleter(uid);
  } catch (e) {
    // The data is gone; the app deletes the sign-in itself if this failed.
    logger.error("deleteAccount: could not delete the sign-in", { uid, error: String(e) });
  }

  logger.info("deleteAccount: done", { uid, counts, signInDeleted, project: config.firebaseProjectId });
  return { status: "deleted", signInDeleted };
}
