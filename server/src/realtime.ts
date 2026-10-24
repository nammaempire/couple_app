/**
 * Live updates over WebSockets.
 *
 * Protocol (JSON messages):
 *   client → {t:"auth", token}                          (first, and again when the token refreshes)
 *   client → {t:"sub", id, doc:"path"} | {t:"sub", id, query:{...QuerySpec}}
 *   client → {t:"unsub", id}
 *   server → {t:"ready"}                                 (after a good auth)
 *   server → {t:"snap", id, doc}  | {t:"snap", id, docs:[...]}
 *   server → {t:"error", id?, code, message}
 *   server → {t:"authExpired"}                           (send a fresh token)
 *
 * Every commit NOTIFYs the changed document paths on the "doc_changes"
 * channel, so this works with more than one server instance.
 */
import pg from "pg";
import type { FastifyInstance } from "fastify";
import type { WebSocket } from "ws";
import { verifyToken, type VerifiedAuth } from "./auth.js";
import { config } from "./config.js";
import { ApiError } from "./errors.js";
import { getDoc, query, type Doc, type QuerySpec } from "./store.js";
import { resolveCollection, resolveDoc } from "./schema.js";

interface Sub {
  id: string;
  doc?: string;
  query?: QuerySpec;
  lastHash?: string;
  timer?: NodeJS.Timeout;
  /** Bumped per refresh; a slower, older refresh never overwrites a newer one. */
  seq: number;
}

interface Conn {
  ws: WebSocket;
  auth: VerifiedAuth | null;
  subs: Map<string, Sub>;
}

const conns = new Set<Conn>();

function send(conn: Conn, msg: unknown): void {
  if (conn.ws.readyState === conn.ws.OPEN) conn.ws.send(JSON.stringify(msg));
}

function authValid(conn: Conn): boolean {
  if (!conn.auth) return false;
  if (conn.auth.expiresAt < Date.now()) {
    conn.auth = null;
    send(conn, { t: "authExpired" });
    return false;
  }
  return true;
}

function hash(v: unknown): string {
  return JSON.stringify(v);
}

async function refresh(conn: Conn, sub: Sub): Promise<void> {
  if (!authValid(conn) || !conn.subs.has(sub.id)) return;
  const caller = { kind: "user" as const, auth: conn.auth };
  const seq = ++sub.seq;
  try {
    let payload: { doc: Doc } | { docs: Doc[] };
    if (sub.doc) payload = { doc: await getDoc(caller, sub.doc) };
    else payload = { docs: await query(caller, sub.query!) };
    if (seq !== sub.seq) return; // a newer refresh is on its way
    const h = hash(payload);
    if (h === sub.lastHash) return;
    sub.lastHash = h;
    if (conn.subs.has(sub.id)) send(conn, { t: "snap", id: sub.id, ...payload });
  } catch (e) {
    if (seq !== sub.seq) return;
    const err = e instanceof ApiError ? e : new ApiError("internal", "Could not load live data.");
    // Forget the last result, so access regained later is pushed again.
    sub.lastHash = undefined;
    send(conn, { t: "error", id: sub.id, code: err.code, message: err.message });
  }
}

/** Debounced refresh, so a burst of writes gives one snapshot. */
function schedule(conn: Conn, sub: Sub, delay = 30): void {
  if (sub.timer) return;
  sub.timer = setTimeout(() => {
    sub.timer = undefined;
    void refresh(conn, sub);
  }, delay);
}

function parentOf(path: string): string {
  return path.split("/").slice(0, -1).join("/");
}

/** Handles changed document paths from any server instance. */
export function onChanged(paths: string[]): void {
  const changed = new Set(paths);
  const parents = new Set(paths.map(parentOf));
  // A change to a couple or user doc can change what its members may read.
  const coupleRoots = new Set(paths.filter((p) => /^couples\/[^/]+$/.test(p)));
  const userRoots = new Set(paths.filter((p) => /^users\/[^/]+$/.test(p)).map((p) => p.split("/")[1]));
  for (const conn of conns) {
    const ownerChanged = conn.auth && userRoots.has(conn.auth.uid);
    for (const sub of conn.subs.values()) {
      try {
        const target = sub.doc ?? sub.query!.collection;
        const hit =
          (sub.doc && changed.has(sub.doc)) ||
          (sub.query && parents.has(sub.query.collection)) ||
          ownerChanged ||
          [...coupleRoots].some((root) => target === root || target.startsWith(root + "/"));
        if (hit) schedule(conn, sub);
      } catch {
        /* one bad subscription must not stop the others */
      }
    }
  }
}

let listener: pg.Client | null = null;
let stopped = false;

async function startListener(): Promise<void> {
  if (stopped) return;
  const client = new pg.Client({
    connectionString: config.databaseUrl,
    ssl: config.databaseSsl ? { rejectUnauthorized: false } : undefined,
  });
  client.on("notification", (msg) => {
    if (msg.channel !== "doc_changes" || !msg.payload) return;
    try {
      onChanged(JSON.parse(msg.payload) as string[]);
    } catch {
      /* ignore malformed */
    }
  });
  client.on("error", () => {
    if (listener === client) listener = null;
    client.end().catch(() => {});
    if (!stopped) setTimeout(() => void startListener().catch(() => {}), 2000);
  });
  await client.connect();
  await client.query("LISTEN doc_changes");
  listener = client;
  // After a reconnect, notifications may have been missed: refresh everything.
  for (const conn of conns) for (const sub of conn.subs.values()) schedule(conn, sub);
}

export async function stopRealtime(): Promise<void> {
  stopped = true;
  const l = listener;
  listener = null;
  if (l) {
    // Keep a no-op error listener: a late "connection terminated" must not crash.
    l.removeAllListeners("error");
    l.on("error", () => {});
    await l.end().catch(() => {});
  }
  for (const conn of conns) conn.ws.close();
}

export async function registerRealtime(app: FastifyInstance): Promise<void> {
  stopped = false;
  await startListener();
  app.addHook("onClose", async () => stopRealtime());

  app.get("/v1/realtime", { websocket: true }, (socket: WebSocket) => {
    const conn: Conn = { ws: socket, auth: null, subs: new Map() };
    conns.add(conn);
    let alive = true;
    const ping = setInterval(() => {
      if (!alive) return socket.terminate();
      alive = false;
      socket.ping();
    }, 25_000);
    socket.on("pong", () => (alive = true));
    // A connection that never signs in is closed.
    const authDeadline = setTimeout(() => {
      if (!conn.auth) socket.close(4401, "Sign in first.");
    }, 15_000);

    socket.on("message", (raw) => {
      handle(raw).catch(() => send(conn, { t: "error", code: "internal", message: "Something went wrong." }));
    });

    const handle = async (raw: unknown) => {
      let msg: { t?: unknown; id?: unknown; token?: unknown; doc?: unknown; query?: unknown };
      try {
        const parsed: unknown = JSON.parse(String(raw));
        if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) throw new Error();
        msg = parsed as typeof msg;
      } catch {
        return send(conn, { t: "error", code: "invalid-argument", message: "Bad message." });
      }
      if (msg.t === "auth") {
        try {
          conn.auth = await verifyToken(typeof msg.token === "string" ? msg.token : null);
          send(conn, { t: "ready" });
          for (const sub of conn.subs.values()) {
            sub.lastHash = undefined;
            schedule(conn, sub, 0);
          }
        } catch (e) {
          const err = e instanceof ApiError ? e : new ApiError("unauthenticated", "Sign in first.");
          send(conn, { t: "error", code: err.code, message: err.message });
        }
        return;
      }
      if (msg.t === "sub" && typeof msg.id === "string" && msg.id.length <= 64) {
        if (conn.subs.size >= 200) return send(conn, { t: "error", id: msg.id, code: "resource-exhausted", message: "Too many listeners." });
        let sub: Sub;
        try {
          if (typeof msg.doc === "string") {
            sub = { id: msg.id, doc: resolveDoc(msg.doc).path, seq: 0 };
          } else if (typeof msg.query === "object" && msg.query !== null && typeof (msg.query as QuerySpec).collection === "string") {
            const q = msg.query as QuerySpec;
            sub = { id: msg.id, query: { ...q, collection: resolveCollection(q.collection).path }, seq: 0 };
          } else {
            throw new Error();
          }
        } catch {
          return send(conn, { t: "error", id: msg.id, code: "invalid-argument", message: "A valid doc path or query is needed." });
        }
        const old = conn.subs.get(msg.id);
        if (old?.timer) clearTimeout(old.timer);
        conn.subs.set(msg.id, sub);
        if (conn.auth) void refresh(conn, sub);
        return;
      }
      if (msg.t === "unsub" && typeof msg.id === "string") {
        const sub = conn.subs.get(msg.id);
        if (sub?.timer) clearTimeout(sub.timer);
        conn.subs.delete(msg.id);
      }
    };

    socket.on("close", () => {
      clearInterval(ping);
      clearTimeout(authDeadline);
      for (const sub of conn.subs.values()) if (sub.timer) clearTimeout(sub.timer);
      conns.delete(conn);
    });
  });
}
