/**
 * Helpers for the security-rules suites (ports of firestore-tests/test/*.js).
 *
 * Each test file gets its own fresh Postgres database (see helpers.ts) and
 * talks to the store directly with app-user callers, the way the emulator
 * tests use authenticatedContext(uid). Seeding uses the ADMIN caller, like
 * withSecurityRulesDisabled.
 *
 * Translation notes:
 *  - assertSucceeds -> ok(p); assertFails -> denied(p) (expects permission-denied).
 *  - serverTimestamp() -> ST, increment(n) -> inc(n), deleteField() -> DEL,
 *    Timestamp -> ts(...).
 *  - A query Firestore would reject as a whole ("rules are not filters") here
 *    returns only the documents the caller may read; such cases assert the
 *    unreadable documents are left out.
 */
import { after, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { createDb, dropDb } from "./helpers.js";

const store = await import("../src/store.js");
const { migrate } = await import("../src/migrate.js");
const { pool } = await import("../src/db.js");
const { COLLECTIONS, quoteIdent } = await import("../src/schema.js");
const { ApiError } = await import("../src/errors.js");

export type Data = Record<string, any>;
export type Caller = import("../src/store.js").Caller;
export type QuerySpec = import("../src/store.js").QuerySpec;
export type WriteSpec = import("../src/store.js").WriteSpec;

export { assert };

export const ST = { $sv: "serverTimestamp" } as const;
export const DEL = { $sv: "delete" } as const;
export const inc = (by: number) => ({ $sv: "increment", by });
export const ts = (d: Date | number | string) => ({ $ts: new Date(d).toISOString() });
/** Timestamp.fromMillis(Date.now() + ms) */
export const fromNow = (ms: number) => ts(Date.now() + ms);
export const DAY = 86_400_000;

/** Fresh database for this file; every table emptied before each test. */
export function useDb(seed?: () => Promise<void>): void {
  before(async () => {
    await createDb();
    await migrate();
  });
  after(async () => {
    await dropDb();
  });
  beforeEach(async () => {
    await pool.query(`TRUNCATE ${COLLECTIONS.map((d) => quoteIdent(d.table)).join(", ")}`);
    if (seed) await seed();
  });
}

export function autoId(): string {
  const abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  return [...randomBytes(20)].map((b) => abc[b % abc.length]).join("");
}

/** A client acting as one caller: the Firestore SDK calls the tests use. */
export class Client {
  constructor(readonly caller: Caller) {}

  async get(path: string) {
    return store.getDoc(this.caller, path);
  }
  /** getDoc(...).data() */
  async data(path: string): Promise<Data | null> {
    return (await this.get(path)).data;
  }
  query(spec: QuerySpec) {
    return store.query(this.caller, spec);
  }
  commit(writes: WriteSpec[], reads?: { path: string; version: number }[]) {
    return store.commit(this.caller, { writes, reads });
  }
  set(path: string, data: Data, opts: { merge?: boolean } = {}) {
    return this.commit([{ op: "set", path, data, merge: opts.merge }]);
  }
  update(path: string, data: Data) {
    return this.commit([{ op: "update", path, data }]);
  }
  delete(path: string) {
    return this.commit([{ op: "delete", path }]);
  }
  /** addDoc(collection(path), data); resolves to the new id. */
  async add(collection: string, data: Data): Promise<string> {
    const id = autoId();
    await this.commit([{ op: "create", path: `${collection}/${id}`, data }]);
    return id;
  }
  /** writeBatch(): collect writes, then commit(). */
  batch() {
    const writes: WriteSpec[] = [];
    const b = {
      set: (path: string, data: Data, opts: { merge?: boolean } = {}) => (writes.push({ op: "set", path, data, merge: opts.merge }), b),
      update: (path: string, data: Data) => (writes.push({ op: "update", path, data }), b),
      delete: (path: string) => (writes.push({ op: "delete", path }), b),
      commit: () => this.commit(writes),
    };
    return b;
  }
  /**
   * runTransaction: reads record versions; the commit aborts if any read doc
   * changed, and the function is retried (like the SDK, up to 5 attempts).
   */
  async runTransaction<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    for (let attempt = 1; ; attempt++) {
      const reads: { path: string; version: number }[] = [];
      const writes: WriteSpec[] = [];
      const tx: Tx = {
        get: async (path) => {
          const d = await this.get(path);
          reads.push({ path, version: d.version });
          return d.data;
        },
        set: (path, data, opts = {}) => void writes.push({ op: "set", path, data, merge: opts.merge }),
        update: (path, data) => void writes.push({ op: "update", path, data }),
        delete: (path) => void writes.push({ op: "delete", path }),
      };
      const out = await fn(tx);
      try {
        await this.commit(writes, reads);
        return out;
      } catch (e) {
        if (e instanceof ApiError && e.code === "aborted" && attempt < 5) continue;
        throw e;
      }
    }
  }
}

export interface Tx {
  get(path: string): Promise<Data | null>;
  set(path: string, data: Data, opts?: { merge?: boolean }): void;
  update(path: string, data: Data): void;
  delete(path: string): void;
}

const clients = new Map<string, Client>();
/** authenticatedContext(uid, claims) */
export function as(uid: string, token: Record<string, unknown> = {}): Client {
  const key = uid + JSON.stringify(token);
  let c = clients.get(key);
  if (!c) clients.set(key, (c = new Client({ kind: "user", auth: { uid, token } })));
  return c;
}

/** withSecurityRulesDisabled */
export const admin = new Client(store.ADMIN);

/** assertSucceeds */
export async function ok<T>(p: Promise<T>): Promise<T> {
  try {
    return await p;
  } catch (e) {
    const err = e as { code?: string; message?: string; details?: unknown };
    assert.fail(`expected success, got ${err.code ?? ""} ${err.message ?? e} ${err.details ? JSON.stringify(err.details) : ""}`);
  }
}

/** assertFails: the operation is refused by the rules. */
export async function denied(p: Promise<unknown>): Promise<void> {
  try {
    await p;
  } catch (e) {
    if (e instanceof ApiError && e.code === "permission-denied") return;
    throw e;
  }
  assert.fail("expected permission-denied, but it succeeded");
}

/** A query that Firestore would refuse: here it simply returns none of the docs. */
export async function hidden(p: Promise<unknown[]>): Promise<void> {
  const docs = await p;
  assert.equal(docs.length, 0, "expected the query to return no readable documents");
}
