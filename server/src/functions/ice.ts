/**
 * Connection servers for WebRTC calls.
 *
 * STUN (free, Google) lets most phones connect directly. A TURN relay is
 * needed for the 10–20% of networks that block direct connections; set
 * TURN_URLS and TURN_SECRET (coturn "use-auth-secret") to turn it on.
 * Each call gets short-lived TURN credentials, so nothing secret ships in
 * the app.
 */
import { createHmac } from "node:crypto";
import { config } from "../config.js";
import type { AuthInfo } from "../rules/engine.js";

export interface IceServer {
  urls: string[];
  username?: string;
  credential?: string;
}

const STUN: IceServer = {
  urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"],
};

export function iceServersFor(uid: string, now = Date.now()): IceServer[] {
  const servers: IceServer[] = [STUN];
  const urls = config.turn.urls;
  if (urls.length && config.turn.secret) {
    // coturn REST API credentials: username "<expiry>:<uid>", password HMAC-SHA1.
    const expiry = Math.floor(now / 1000) + config.turn.ttlSeconds;
    const username = `${expiry}:${uid}`;
    const credential = createHmac("sha1", config.turn.secret).update(username).digest("base64");
    servers.push({ urls, username, credential });
  }
  return servers;
}

/** Callable: { iceServers: [...] } for the signed-in user. */
export async function iceServers(auth: AuthInfo): Promise<{ iceServers: IceServer[] }> {
  return { iceServers: iceServersFor(auth.uid) };
}
