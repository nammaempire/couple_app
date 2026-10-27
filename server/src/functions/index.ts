/**
 * Server functions the app calls: POST /v1/fn/<name> with {data} → {result}.
 * (Same request/response shape as Firebase callable functions.)
 */
import type { AuthInfo } from "../rules/engine.js";
import { verifyPurchase as verifyPurchaseImpl } from "./billing.js";
import { iceServers } from "./ice.js";
import { finalizeSeparation, leaveNow, requireUid } from "./separations.js";

export type Callable = (auth: AuthInfo, data: unknown) => Promise<unknown>;

export const callables: Record<string, Callable> = {
  finalizeSeparation,
  leaveNow,
  /**
   * Verifies a Google Play purchase and grants it to the couple, once.
   * Data: { coupleId, productId, purchaseToken, packageName, gift?: { message } }.
   * Returns { status: 'granted' | 'alreadyGranted', premiumUntil?, bookCredits?, giftId? }.
   */
  verifyPurchase: async (auth, data) => verifyPurchaseImpl(requireUid(auth), data),
  /** Connection servers (STUN, and TURN when configured) for a WebRTC call. */
  iceServers: async (auth) => iceServers(auth),
};

export { endCouple } from "./endCouple.js";
export { processSeparations } from "./separations.js";
export type { VerifyPurchaseData, VerifyPurchaseResult } from "./billing.js";
