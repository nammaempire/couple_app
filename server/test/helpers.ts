/**
 * Test setup: a fresh Postgres database per test file, test-mode auth
 * ("Bearer test:<uid>"), and an in-memory bucket.
 *
 * Needs a reachable Postgres; set TEST_DATABASE_ADMIN_URL (default
 * postgres://postgres@127.0.0.1:5432/postgres).
 */
import pg from "pg";

const adminUrl = process.env.TEST_DATABASE_ADMIN_URL ?? "postgres://postgres@127.0.0.1:5432/postgres";
const dbName = `us_test_${process.pid}_${Math.floor(Math.random() * 1e6)}`;
const u = new URL(adminUrl);
u.pathname = `/${dbName}`;

process.env.DATABASE_URL = u.toString();
process.env.AUTH_TEST_MODE = "true";
process.env.NODE_ENV = "test";
process.env.PUBLIC_URL = "http://test.local";
process.env.S3_BUCKET = "";
process.env.RUN_SCHEDULER = "false";

export async function createDb(): Promise<void> {
  const c = new pg.Client({ connectionString: adminUrl });
  await c.connect();
  await c.query(`CREATE DATABASE ${dbName}`);
  await c.end();
}

export async function dropDb(): Promise<void> {
  const { pool } = await import("../src/db.js");
  await pool.end().catch(() => {});
  const c = new pg.Client({ connectionString: adminUrl });
  await c.connect();
  await c.query(`DROP DATABASE IF EXISTS ${dbName} WITH (FORCE)`);
  await c.end();
}

export function token(uid: string, claims: Record<string, unknown> = {}): string {
  const extra = Object.keys(claims).length ? ":" + Buffer.from(JSON.stringify(claims)).toString("base64url") : "";
  return `test:${uid}${extra}`;
}

export function authz(uid: string, claims: Record<string, unknown> = {}) {
  return { authorization: `Bearer ${token(uid, claims)}` };
}

/** Starts the app on a random port. */
export async function startApp() {
  await createDb();
  const { migrate } = await import("../src/migrate.js");
  await migrate();
  const { buildApp } = await import("../src/app.js");
  const app = await buildApp();
  await app.listen({ port: 0, host: "127.0.0.1" });
  const addr = app.server.address();
  const port = typeof addr === "object" && addr ? addr.port : 0;
  return {
    app,
    base: `http://127.0.0.1:${port}`,
    ws: `ws://127.0.0.1:${port}/v1/realtime`,
    async close() {
      await app.close();
      await dropDb();
    },
  };
}

export async function call(base: string, path: string, body: unknown, uid?: string, method = "POST") {
  const res = await fetch(base + path, {
    method,
    headers: { "content-type": "application/json", ...(uid ? authz(uid) : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = (await res.json()) as any;
  return { status: res.status, json };
}
