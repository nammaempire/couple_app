/**
 * Incoming webhooks.
 *
 *   POST /webhooks/play-rtdn   Google Play real-time developer notifications,
 *                              delivered by a Pub/Sub *push* subscription.
 *
 * Pub/Sub sends {message: {data: base64 JSON, messageId, publishTime}, subscription}
 * with `Authorization: Bearer <Google-signed OIDC token>`. We check the token's
 * audience (RTDN_AUDIENCE) and that it was issued to the push service account
 * (RTDN_SERVICE_ACCOUNT_EMAIL, email_verified).
 *
 * Replies: 2xx when handled or permanently unprocessable (Pub/Sub acks), 5xx on
 * transient failures (Pub/Sub retries with backoff). Messages older than 24h
 * are dropped instead of retried forever.
 */
import type { FastifyInstance } from "fastify";
import { OAuth2Client } from "google-auth-library";
import { bearer } from "../auth.js";
import { config } from "../config.js";
import { handlePlayNotification, type DeveloperNotification } from "./billing.js";
import { logger } from "./log.js";

/** Pub/Sub messages older than this are dropped instead of retried forever. */
export const RTDN_MAX_AGE_MS = 24 * 60 * 60 * 1000;

interface PushBody {
  message?: { data?: string; messageId?: string; message_id?: string; publishTime?: string; publish_time?: string };
  subscription?: string;
}

type PushCheck = (authorization: string | undefined) => Promise<"ok" | "unauthorized" | "notConfigured">;

const oauth = new OAuth2Client();

async function verifyPush(authorization: string | undefined): Promise<"ok" | "unauthorized" | "notConfigured"> {
  if (!config.rtdnAudience || !config.rtdnServiceAccountEmail) return "notConfigured";
  const token = bearer(authorization);
  if (!token) return "unauthorized";
  try {
    const ticket = await oauth.verifyIdToken({ idToken: token, audience: config.rtdnAudience });
    const p = ticket.getPayload();
    if (!p || p.email !== config.rtdnServiceAccountEmail || p.email_verified !== true) return "unauthorized";
    return "ok";
  } catch {
    return "unauthorized";
  }
}

let testCheck: PushCheck | undefined;

/** Tests only (AUTH_TEST_MODE): replace the OIDC check. Pass undefined to restore. */
export function setRtdnPushCheckForTests(fn: PushCheck | undefined): void {
  if (fn && !config.authTestMode) throw new Error("setRtdnPushCheckForTests needs AUTH_TEST_MODE.");
  testCheck = fn;
}

export async function registerWebhooks(app: FastifyInstance): Promise<void> {
  app.post("/webhooks/play-rtdn", async (req, reply) => {
    const check = testCheck && config.authTestMode ? testCheck : verifyPush;
    const auth = await check(req.headers.authorization);
    if (auth === "notConfigured") {
      logger.error("RTDN: rejected, RTDN_AUDIENCE / RTDN_SERVICE_ACCOUNT_EMAIL are not set");
      return reply.status(503).send({ error: { code: "unavailable", message: "RTDN is not configured." } });
    }
    if (auth !== "ok") {
      logger.warn("RTDN: rejected push with a bad or missing token");
      return reply.status(401).send({ error: { code: "unauthenticated", message: "Bad push token." } });
    }

    const body = (req.body ?? {}) as PushBody;
    const msg = body.message ?? {};
    const messageId = msg.messageId ?? msg.message_id;
    const published = Date.parse(msg.publishTime ?? msg.publish_time ?? "");
    const age = Number.isFinite(published) ? Date.now() - published : 0;

    let payload: DeveloperNotification;
    try {
      if (typeof msg.data !== "string") throw new Error("no data");
      payload = JSON.parse(Buffer.from(msg.data, "base64").toString("utf8")) as DeveloperNotification;
      if (typeof payload !== "object" || payload === null) throw new Error("not an object");
    } catch {
      logger.error("RTDN: message is not JSON", { messageId });
      return reply.status(200).send({ ok: true, outcome: "badMessage" });
    }

    try {
      const outcome = await handlePlayNotification(payload);
      logger.info("RTDN handled", {
        messageId,
        outcome,
        type: payload.subscriptionNotification?.notificationType ?? (payload.voidedPurchaseNotification ? "voided" : "other"),
      });
      return reply.status(200).send({ ok: true, outcome });
    } catch (e) {
      // Thrown errors are transient (Play 429/5xx, database trouble): let
      // Pub/Sub retry, but only for a day. Permanent problems come back as
      // outcomes from handlePlayNotification instead.
      if (age < RTDN_MAX_AGE_MS) {
        logger.warn("RTDN failed, will retry", { messageId, error: String(e), ageMs: age });
        return reply.status(503).send({ error: { code: "unavailable", message: "Try again later." } });
      }
      logger.error("RTDN failed, dropping", { messageId, error: String(e), ageMs: age });
      return reply.status(200).send({ ok: true, outcome: "dropped" });
    }
  });
}
