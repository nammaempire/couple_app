import Fastify, { type FastifyInstance } from "fastify";
import websocket from "@fastify/websocket";
import { bearer, verifyToken } from "./auth.js";
import { ApiError } from "./errors.js";
import { registerFiles } from "./files.js";
import { callables } from "./functions/index.js";
import { registerWebhooks } from "./functions/webhooks.js";
import { registerRealtime } from "./realtime.js";
import { commit, count, getDocs, onUserCommit, query, type CommitSpec, type QuerySpec } from "./store.js";
import { pushAfterCommit } from "./push/triggers.js";
import { pool } from "./db.js";

export async function buildApp(opts: { logger?: boolean } = {}): Promise<FastifyInstance> {
  const app = Fastify({
    logger: opts.logger ?? false,
    bodyLimit: 4 * 1024 * 1024,
    trustProxy: true,
  });

  app.setErrorHandler((err, req, reply) => {
    if (err instanceof ApiError) return reply.status(err.status).send(err.toJSON());
    const status = (err as { statusCode?: number }).statusCode;
    if (status && status >= 400 && status < 500) {
      return reply.status(status).send(new ApiError("invalid-argument", err.message).toJSON());
    }
    req.log.error(err);
    return reply.status(500).send(new ApiError("internal", "Something went wrong on the server.").toJSON());
  });

  await app.register(websocket, { options: { maxPayload: 1024 * 1024 } });

  app.get("/health", async () => {
    await pool.query("SELECT 1");
    return { ok: true };
  });

  const caller = async (authorization: string | undefined) => ({
    kind: "user" as const,
    auth: await verifyToken(bearer(authorization)),
  });

  app.post("/v1/db/get", async (req) => {
    const { paths } = (req.body ?? {}) as { paths?: string[] };
    if (!Array.isArray(paths)) throw new ApiError("invalid-argument", "paths must be a list.");
    return { docs: await getDocs(await caller(req.headers.authorization), paths) };
  });

  app.post("/v1/db/query", async (req) => {
    return { docs: await query(await caller(req.headers.authorization), req.body as QuerySpec) };
  });

  app.post("/v1/db/count", async (req) => {
    return { count: await count(await caller(req.headers.authorization), req.body as QuerySpec) };
  });

  app.post("/v1/db/commit", async (req) => {
    return commit(await caller(req.headers.authorization), req.body as CommitSpec);
  });

  app.post("/v1/fn/:name", async (req) => {
    const name = (req.params as { name: string }).name;
    const fn = Object.prototype.hasOwnProperty.call(callables, name) ? callables[name] : undefined;
    if (!fn) throw new ApiError("not-found", "No such function.");
    const auth = await verifyToken(bearer(req.headers.authorization));
    const result = await fn(auth, (req.body as { data?: unknown } | null)?.data ?? null);
    return { result: result ?? null };
  });

  // Push notifications for the partner (love taps, messages, calls, …).
  const stopPush = onUserCommit((actor, changes) => {
    void pushAfterCommit(actor, changes);
  });
  app.addHook("onClose", async () => stopPush());

  await registerFiles(app);
  await registerWebhooks(app);
  await registerRealtime(app);
  return app;
}
