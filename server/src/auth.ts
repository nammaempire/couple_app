import { initializeApp, getApps } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { config } from "./config.js";
import { ApiError } from "./errors.js";
import type { AuthInfo } from "./rules/engine.js";

/**
 * Sign-in stays on Firebase Auth (phone, email and Google). The app sends its
 * Firebase ID token; we check it with Firebase's public keys. No service
 * account is needed for this.
 */
function firebase() {
  if (getApps().length === 0) initializeApp({ projectId: config.firebaseProjectId });
  return getAuth();
}

export interface VerifiedAuth extends AuthInfo {
  /** Token expiry, ms since epoch. */
  expiresAt: number;
}

export async function verifyToken(token: string | undefined | null): Promise<VerifiedAuth> {
  if (!token) throw new ApiError("unauthenticated", "Sign in first.");
  if (config.authTestMode && token.startsWith("test:")) {
    // test:<uid>  or  test:<uid>:<base64url JSON claims>
    const [, uid, claims] = token.split(":");
    if (!uid) throw new ApiError("unauthenticated", "Bad test token.");
    const extra = claims ? (JSON.parse(Buffer.from(claims, "base64url").toString("utf8")) as Record<string, unknown>) : {};
    return { uid, token: { uid, ...extra }, expiresAt: Date.now() + 3600_000 };
  }
  try {
    const decoded = await firebase().verifyIdToken(token);
    return { uid: decoded.uid, token: decoded as unknown as Record<string, unknown>, expiresAt: decoded.exp * 1000 };
  } catch {
    throw new ApiError("unauthenticated", "Your sign-in has expired. Please sign in again.");
  }
}

export function bearer(header: string | undefined): string | null {
  if (!header) return null;
  const m = /^Bearer\s+(.+)$/i.exec(header);
  return m ? m[1].trim() : null;
}
