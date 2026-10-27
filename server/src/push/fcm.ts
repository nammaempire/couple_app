/**
 * Push delivery through Firebase Cloud Messaging (Google's service that wakes
 * Android phones). Only the "buzz" goes through FCM; the data stays here.
 *
 * Needs FIREBASE_SERVICE_ACCOUNT_JSON (a service-account key of the Firebase
 * project, on one line). Without it, pushes are skipped and logged once.
 */
import { cert, getApps, initializeApp, type App } from "firebase-admin/app";
import { getMessaging, type Message } from "firebase-admin/messaging";
import { config } from "../config.js";

export interface PushSender {
  /** Sends one message per token; returns tokens FCM says are dead. */
  send(tokens: string[], message: Omit<Message, "token" | "topic" | "condition">): Promise<string[]>;
}

let warned = false;
let app: App | null = null;

function pushApp(): App | null {
  if (app) return app;
  if (!config.firebaseServiceAccountJson) {
    if (!warned) {
      warned = true;
      console.warn("Push notifications are off: FIREBASE_SERVICE_ACCOUNT_JSON is not set.");
    }
    return null;
  }
  const existing = getApps().find((a) => a.name === "push");
  app = existing ?? initializeApp(
    { credential: cert(JSON.parse(config.firebaseServiceAccountJson)), projectId: config.firebaseProjectId },
    "push",
  );
  return app;
}

const DEAD = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

class FcmSender implements PushSender {
  async send(tokens: string[], message: Omit<Message, "token" | "topic" | "condition">): Promise<string[]> {
    const a = pushApp();
    if (!a || tokens.length === 0) return [];
    const res = await getMessaging(a).sendEach(tokens.map((token) => ({ ...message, token }) as Message));
    const dead: string[] = [];
    res.responses.forEach((r, i) => {
      if (!r.success && r.error && DEAD.has(r.error.code)) dead.push(tokens[i]);
      else if (!r.success) console.error("Push failed:", r.error?.code, r.error?.message);
    });
    return dead;
  }
}

let sender: PushSender = new FcmSender();
export function setPushSender(s: PushSender): void {
  sender = s;
}
export function pushSender(): PushSender {
  return sender;
}
