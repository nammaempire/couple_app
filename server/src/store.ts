/**
 * The document store: reads, queries and atomic commits over the per-collection
 * Postgres tables, with security rules applied for app requests.
 */
import { markChanged, pool, tx, type Client } from "./db.js";
import { ApiError } from "./errors.js";
import { evaluate, type AuthInfo, type DocLike, type Op, type Rule, type RuleContext } from "./rules/engine.js";
import { firestoreRules } from "./rules/firestore.js";
import {
  COLLECTIONS,
  PathError,
  docPathFor,
  quoteIdent as q,
  resolveCollection,
  resolveDoc,
  type CollectionDef,
  type ResolvedDoc,
} from "./schema.js";
import {
  ValueError,
  applyMerge,
  applySet,
  applyUpdate,
  isPlainObject,
  sanitize,
  splitFieldPath,
  type Data,
  type Json,
} from "./values.js";

export interface Doc {
  path: string;
  id: string;
  exists: boolean;
  data: Data | null;
  /** 0 when the document doesn't exist. */
  version: number;
  createTime: string | null;
  updateTime: string | null;
}

export type WhereOp = "==" | "!=" | "<" | "<=" | ">" | ">=" | "in" | "not-in" | "array-contains" | "array-contains-any";

export interface QuerySpec {
  collection: string;
  where?: [string, WhereOp, Json][];
  orderBy?: [string, "asc" | "desc"][];
  limit?: number;
}

export interface WriteSpec {
  op: "set" | "update" | "delete" | "create";
  path: string;
  data?: Data;
  merge?: boolean;
}

export interface CommitSpec {
  writes: WriteSpec[];
  /** Transaction reads: each document's version when read (0 = missing). */
  reads?: { path: string; version: number }[];
}

export interface CommitResult {
  commitTime: string;
  writes: { path: string; version: number; exists: boolean }[];
}

/** Who is asking: an app user (rules apply) or the server itself (no rules). */
export type Caller = { kind: "user"; auth: AuthInfo | null } | { kind: "admin" };

export const ADMIN: Caller = { kind: "admin" };

let rules: Rule[] = firestoreRules;
/** Tests can swap the rule set. */
export function setRules(r: Rule[]): void {
  rules = r;
}

const MAX_QUERY_LIMIT = 1000;
const MAX_WRITES = 500;

function wrap<T>(fn: () => Promise<T>): Promise<T> {
  return fn().catch((e: unknown) => {
    if (e instanceof ApiError) throw e;
    if (e instanceof PathError || e instanceof ValueError) throw new ApiError("invalid-argument", e.message);
    throw e;
  });
}

function keyCols(d: CollectionDef): string[] {
  return [...d.parentCols, "id"];
}

function rowToDoc(r: ResolvedDoc, row: RowShape | undefined): Doc {
  if (!row) return { path: r.path, id: r.id, exists: false, data: null, version: 0, createTime: null, updateTime: null };
  return {
    path: r.path,
    id: r.id,
    exists: true,
    data: row.data,
    version: Number(row.version),
    createTime: row.create_time,
    updateTime: row.update_time,
  };
}

interface RowShape {
  data: Data;
  version: number;
  create_time: string;
  update_time: string;
  [k: string]: unknown;
}

async function loadRow(
  c: Client | typeof pool,
  r: ResolvedDoc,
  lock: boolean | "share" = false,
): Promise<RowShape | undefined> {
  const cols = keyCols(r.def);
  const where = cols.map((col, i) => `${q(col)} = $${i + 1}`).join(" AND ");
  const suffix = lock === "share" ? " FOR SHARE" : lock ? " FOR UPDATE" : "";
  const res = await c.query<RowShape>(
    `SELECT data, version, create_time, update_time FROM ${q(r.def.table)} WHERE ${where}${suffix}`,
    [...r.parentIds, r.id],
  );
  return res.rows[0];
}

// ---- Rules context -----------------------------------------------------------

interface Ctx {
  caller: Caller;
  time: string;
  /** Pre-request state cache. */
  before: Map<string, DocLike | null>;
  /** Pending after-state for documents written in this commit. */
  after: Map<string, DocLike | null>;
  client: Client | typeof pool;
}

async function readBefore(ctx: Ctx, path: string): Promise<DocLike | null> {
  const r = resolveDoc(path);
  if (ctx.before.has(r.path)) return ctx.before.get(r.path)!;
  // Inside a commit, documents the rules read are share-locked, so a
  // concurrent change (e.g. a member leaving) can't slip past the check.
  const row = await loadRow(ctx.client, r, ctx.client === pool ? false : "share");
  const d = row ? { id: r.id, data: row.data } : null;
  ctx.before.set(r.path, d);
  return d;
}

async function readAfter(ctx: Ctx, path: string): Promise<DocLike | null> {
  const r = resolveDoc(path);
  if (ctx.after.has(r.path)) return ctx.after.get(r.path)!;
  return readBefore(ctx, r.path);
}

async function allowed(ctx: Ctx, op: Op, path: string, resource: DocLike | null, incoming: DocLike | null): Promise<boolean> {
  if (ctx.caller.kind === "admin") return true;
  const base: Omit<RuleContext, "params"> = {
    auth: ctx.caller.auth,
    time: ctx.time,
    path,
    resource,
    request: { resource: incoming },
    get: (p) => readBefore(ctx, p),
    exists: async (p) => (await readBefore(ctx, p)) !== null,
    getAfter: (p) => readAfter(ctx, p),
    existsAfter: async (p) => (await readAfter(ctx, p)) !== null,
  };
  return evaluate(rules, op, base);
}

function newCtx(caller: Caller, client: Client | typeof pool = pool): Ctx {
  return { caller, time: new Date().toISOString(), before: new Map(), after: new Map(), client };
}

// ---- Reads -----------------------------------------------------------------------

export function getDoc(caller: Caller, path: string): Promise<Doc> {
  return wrap(async () => {
    const r = resolveDoc(path);
    const row = await loadRow(pool, r);
    const doc = rowToDoc(r, row);
    const ctx = newCtx(caller);
    ctx.before.set(r.path, row ? { id: r.id, data: row.data } : null);
    // A get of a missing doc is checked with resource == null, like Firestore.
    if (!(await allowed(ctx, "get", r.path, row ? { id: r.id, data: row.data } : null, null))) {
      throw new ApiError("permission-denied", "Missing or insufficient permissions.");
    }
    return doc;
  });
}

export async function getDocs(caller: Caller, paths: string[]): Promise<Doc[]> {
  if (paths.length > 100) throw new ApiError("invalid-argument", "At most 100 documents per request.");
  return Promise.all(paths.map((p) => getDoc(caller, p)));
}

function fieldPathParam(field: string): string[] {
  if (field === "__name__" || field === "id") return [];
  return splitFieldPath(field);
}

function buildQuery(spec: QuerySpec, withLimit: boolean): { sql: string; params: unknown[]; def: CollectionDef; parentIds: string[] } {
  const col = resolveCollection(spec.collection);
  const d = col.def;
  const params: unknown[] = [];
  const p = (v: unknown) => {
    params.push(v);
    return `$${params.length}`;
  };
  const conds: string[] = d.parentCols.map((c, i) => `${q(c)} = ${p(col.parentIds[i])}`);

  if (!Array.isArray(spec.where ?? []) || (spec.where ?? []).length > 10) {
    throw new ApiError("invalid-argument", "At most 10 where clauses.");
  }
  if (!Array.isArray(spec.orderBy ?? []) || (spec.orderBy ?? []).length > 4) {
    throw new ApiError("invalid-argument", "At most 4 orderBy clauses.");
  }
  for (const w of spec.where ?? []) {
    if (!Array.isArray(w) || w.length !== 3 || typeof w[0] !== "string") throw new ApiError("invalid-argument", "Bad where clause.");
    const [field, op, rawValue] = w;
    const value = sanitize(rawValue, false);
    const isId = field === "__name__" || field === "id";
    const lhs = isId ? `to_jsonb(id)` : `(data #> ${p(fieldPathParam(field))}::text[])`;
    switch (op) {
      case "==":
        conds.push(`${lhs} = ${p(JSON.stringify(value))}::jsonb`);
        break;
      case "!=":
        conds.push(`${lhs} IS NOT NULL AND ${lhs} <> ${p(JSON.stringify(value))}::jsonb`);
        break;
      case "<":
      case "<=":
      case ">":
      case ">=": {
        const v = p(JSON.stringify(value));
        conds.push(`${lhs} ${op} ${v}::jsonb AND jsonb_typeof(${lhs}) = jsonb_typeof(${v}::jsonb)`);
        break;
      }
      case "in":
      case "not-in": {
        if (!Array.isArray(value) || value.length === 0 || value.length > 30) {
          throw new ApiError("invalid-argument", `${op} needs 1–30 values.`);
        }
        const arr = p(value.map((x) => JSON.stringify(x)));
        conds.push(op === "in" ? `${lhs} = ANY(${arr}::jsonb[])` : `${lhs} IS NOT NULL AND NOT (${lhs} = ANY(${arr}::jsonb[]))`);
        break;
      }
      case "array-contains":
        conds.push(`jsonb_typeof(${lhs}) = 'array' AND ${lhs} @> jsonb_build_array(${p(JSON.stringify(value))}::jsonb)`);
        break;
      case "array-contains-any": {
        if (!Array.isArray(value) || value.length === 0 || value.length > 30) {
          throw new ApiError("invalid-argument", "array-contains-any needs 1–30 values.");
        }
        const ors = value.map((x) => `${lhs} @> jsonb_build_array(${p(JSON.stringify(x))}::jsonb)`);
        conds.push(`jsonb_typeof(${lhs}) = 'array' AND (${ors.join(" OR ")})`);
        break;
      }
      default:
        throw new ApiError("invalid-argument", `Unsupported operator ${String(op)}.`);
    }
  }

  const order: string[] = [];
  let lastDir = "ASC";
  for (const o of spec.orderBy ?? []) {
    if (!Array.isArray(o) || typeof o[0] !== "string") throw new ApiError("invalid-argument", "Bad orderBy clause.");
    const [field, dir] = o;
    const d2 = dir === "desc" ? "DESC" : "ASC";
    lastDir = d2;
    if (field === "__name__" || field === "id") {
      order.push(`id ${d2}`);
      continue;
    }
    const expr = `(data #> ${p(fieldPathParam(field))}::text[])`;
    conds.push(`${expr} IS NOT NULL`);
    order.push(`${expr} ${d2}`);
  }
  order.push(`id ${lastDir}`);

  let sql = `SELECT ${keyCols(d).map(q).join(", ")}, data, version, create_time, update_time FROM ${q(d.table)}`;
  if (conds.length) sql += ` WHERE ${conds.join(" AND ")}`;
  sql += ` ORDER BY ${order.join(", ")}`;
  if (withLimit && spec.limit !== undefined) {
    if (!Number.isInteger(spec.limit) || spec.limit < 0) throw new ApiError("invalid-argument", "Bad limit.");
    sql += ` LIMIT ${Math.min(spec.limit, MAX_QUERY_LIMIT)}`;
  } else if (withLimit) {
    sql += ` LIMIT ${MAX_QUERY_LIMIT * 5}`;
  }
  return { sql, params, def: d, parentIds: col.parentIds };
}

/** Most rows a single query may look at before giving up. */
const MAX_SCAN = 5000;
const PAGE = 200;

/**
 * Runs a query and returns only documents the caller may read.
 *
 * The rules are applied BEFORE the limit, page by page, so the result is
 * exactly "the first N readable matches": hidden documents behave as if they
 * didn't exist and can't be probed through ordering or limits.
 */
export function query(caller: Caller, spec: QuerySpec): Promise<Doc[]> {
  return wrap(async () => {
    if (spec.limit !== undefined && (!Number.isInteger(spec.limit) || spec.limit < 0)) {
      throw new ApiError("invalid-argument", "Bad limit.");
    }
    const want = Math.min(spec.limit ?? MAX_SCAN, MAX_QUERY_LIMIT * 5);
    const { sql, params, def: d, parentIds } = buildQuery(spec, false);
    const ctx = newCtx(caller);
    const out: Doc[] = [];
    let offset = 0;
    while (out.length < want) {
      const res = await pool.query<RowShape & { id: string }>(
        `${sql} LIMIT ${PAGE} OFFSET ${offset}`,
        params,
      );
      for (const row of res.rows) {
        const path = docPathFor(d, parentIds, row.id);
        const doc = { id: row.id, data: row.data };
        ctx.before.set(path, doc);
        if (await allowed(ctx, "list", path, doc, null)) {
          out.push(rowToDoc(resolveDoc(path), row));
          if (out.length >= want) break;
        }
      }
      offset += res.rows.length;
      if (res.rows.length < PAGE) break;
      if (offset >= MAX_SCAN) {
        throw new ApiError("resource-exhausted", "This query matches too many documents. Narrow it down.");
      }
    }
    return out;
  });
}

export async function count(caller: Caller, spec: QuerySpec): Promise<number> {
  const docs = await query(caller, { ...spec, limit: undefined });
  return spec.limit === undefined ? docs.length : Math.min(docs.length, spec.limit);
}

// ---- Writes --------------------------------------------------------------------

/** Paths changed by commits, for realtime listeners. */
type ChangeListener = (paths: string[]) => void;
const changeListeners = new Set<ChangeListener>();
export function onLocalChange(fn: ChangeListener): () => void {
  changeListeners.add(fn);
  return () => changeListeners.delete(fn);
}

export async function notifyChanged(c: Client, paths: string[]): Promise<void> {
  markChanged(c, paths);
  // Chunked to stay under NOTIFY's 8000-byte payload limit.
  let chunk: string[] = [];
  let size = 0;
  const flush = async () => {
    if (chunk.length) await c.query("SELECT pg_notify('doc_changes', $1)", [JSON.stringify(chunk)]);
    chunk = [];
    size = 0;
  };
  for (const p of paths) {
    if (size + p.length + 4 > 7000) await flush();
    chunk.push(p);
    size += p.length + 4;
  }
  await flush();
}

/**
 * A create/update precondition failed. Only say why (already-exists /
 * not-found) to callers who may read the document; others get
 * permission-denied, so failures can't be used to probe what exists.
 */
async function preconditionFailed(ctx: Ctx, path: string, err: ApiError): Promise<never> {
  if (await allowed(ctx, "get", path, ctx.before.get(path) ?? null, null)) throw err;
  throw new ApiError("permission-denied", "Missing or insufficient permissions.", { path });
}

/** What a user's commit changed, for side effects such as push notifications. */
export interface CommittedChange {
  path: string;
  before: Data | null;
  after: Data | null;
}
type UserCommitHook = (actorUid: string, changes: CommittedChange[]) => void;
const userCommitHooks = new Set<UserCommitHook>();

/** Called after every successful commit made by an app user (not the server). */
export function onUserCommit(fn: UserCommitHook): () => void {
  userCommitHooks.add(fn);
  return () => userCommitHooks.delete(fn);
}

export function commit(caller: Caller, spec: CommitSpec): Promise<CommitResult> {
  return commitInner(caller, spec).then(({ result, changes }) => {
    if (caller.kind === "user" && caller.auth && changes.length) {
      for (const hook of userCommitHooks) {
        try {
          hook(caller.auth.uid, changes);
        } catch (e) {
          console.error("Commit hook failed:", e);
        }
      }
    }
    return result;
  });
}

function commitInner(caller: Caller, spec: CommitSpec): Promise<{ result: CommitResult; changes: CommittedChange[] }> {
  return wrap(async () => {
    if (!Array.isArray(spec.writes)) throw new ApiError("invalid-argument", "writes must be a list.");
    if (spec.writes.length > MAX_WRITES) throw new ApiError("invalid-argument", `At most ${MAX_WRITES} writes per commit.`);
    const writes = spec.writes.map((w) => {
      if (typeof w !== "object" || w === null || typeof w.path !== "string") throw new ApiError("invalid-argument", "Bad write.");
      if (!["set", "update", "delete", "create"].includes(w.op)) throw new ApiError("invalid-argument", "Bad write op.");
      const data = w.op === "delete" ? undefined : sanitize(w.data ?? {}, true);
      if (data !== undefined && !isPlainObject(data)) throw new ApiError("invalid-argument", "Document data must be a map.");
      return { ...w, r: resolveDoc(w.path), data: data as Data | undefined };
    });
    if (!Array.isArray(spec.reads ?? [])) throw new ApiError("invalid-argument", "reads must be a list.");
    if ((spec.reads ?? []).length > 100) throw new ApiError("invalid-argument", "At most 100 reads per transaction.");
    const reads = (spec.reads ?? []).map((x) => ({ r: resolveDoc(String(x.path)), version: Number(x.version) || 0 }));

    return tx(async (c) => {
      const ctx = newCtx(caller, c);
      // Lock every touched document in a stable order to avoid deadlocks.
      const touched = new Map<string, ResolvedDoc>();
      for (const w of writes) touched.set(w.r.path, w.r);
      for (const x of reads) touched.set(x.r.path, x.r);
      const original = new Map<string, RowShape | undefined>();
      const sorted = [...touched.keys()].sort();
      // Row locks can't lock a document that doesn't exist yet, so every
      // touched path also takes a transaction-scoped advisory lock: two
      // commits on the same path (even a missing one) run one after the other.
      for (const path of sorted) {
        await c.query("SELECT pg_advisory_xact_lock(hashtextextended($1, 727))", [path]);
      }
      for (const path of sorted) {
        const r = touched.get(path)!;
        const row = await loadRow(c, r, true);
        original.set(path, row);
        ctx.before.set(path, row ? { id: r.id, data: row.data } : null);
      }

      // A transaction may only depend on documents the caller can read.
      for (const x of reads) {
        if (!(await allowed(ctx, "get", x.r.path, ctx.before.get(x.r.path) ?? null, null))) {
          throw new ApiError("permission-denied", "Missing or insufficient permissions.", { path: x.r.path, op: "get" });
        }
      }
      for (const x of reads) {
        const row = original.get(x.r.path);
        const current = row ? Number(row.version) : 0;
        if (current !== x.version) {
          throw new ApiError("aborted", "The document changed while the transaction ran. Try again.");
        }
      }

      // Apply writes in order to build the after-state.
      for (const w of writes) {
        const cur = ctx.after.has(w.r.path) ? ctx.after.get(w.r.path)! : ctx.before.get(w.r.path)!;
        let next: DocLike | null;
        switch (w.op) {
          case "delete":
            next = null;
            break;
          case "create":
            if (cur) await preconditionFailed(ctx, w.r.path, new ApiError("already-exists", `Document already exists: ${w.r.path}`));
            next = { id: w.r.id, data: applySet(w.data!, ctx.time) };
            break;
          case "set":
            next = { id: w.r.id, data: w.merge ? applyMerge(cur?.data ?? null, w.data!, ctx.time) : applySet(w.data!, ctx.time) };
            break;
          case "update":
            if (!cur) await preconditionFailed(ctx, w.r.path, new ApiError("not-found", `No document to update: ${w.r.path}`));
            next = { id: w.r.id, data: applyUpdate(cur!.data, w.data!, ctx.time) };
            break;
        }
        ctx.after.set(w.r.path, next);
      }

      // Security rules, once per document, on its original and final state.
      for (const [path, after] of ctx.after) {
        const before = ctx.before.get(path) ?? null;
        if (!before && !after) {
          // Deleting a missing doc writes nothing, but the delete rule still
          // runs (resource == null), so a refusal can't reveal what exists.
          if (!(await allowed(ctx, "delete", path, null, null))) {
            throw new ApiError("permission-denied", "Missing or insufficient permissions.", { path, op: "delete" });
          }
          continue;
        }
        const op: Op = !after ? "delete" : before ? "update" : "create";
        if (!(await allowed(ctx, op, path, before, after))) {
          throw new ApiError("permission-denied", "Missing or insufficient permissions.", { path, op });
        }
      }

      const result: CommitResult = { commitTime: ctx.time, writes: [] };
      for (const [path, after] of ctx.after) {
        if (!after && !ctx.before.get(path)) continue; // nothing to delete
        const r = touched.get(path)!;
        const cols = keyCols(r.def);
        const keyVals = [...r.parentIds, r.id];
        if (!after) {
          await c.query(
            `DELETE FROM ${q(r.def.table)} WHERE ${cols.map((col, i) => `${q(col)} = $${i + 1}`).join(" AND ")}`,
            keyVals,
          );
          result.writes.push({ path, version: 0, exists: false });
        } else {
          const res = await c.query<{ version: number }>(
            `INSERT INTO ${q(r.def.table)} (${cols.map(q).join(", ")}, data, create_time, update_time)
             VALUES (${cols.map((_, i) => `$${i + 1}`).join(", ")}, $${cols.length + 1}::jsonb, $${cols.length + 2}, $${cols.length + 2})
             ON CONFLICT (${cols.map(q).join(", ")}) DO UPDATE
               SET data = EXCLUDED.data, version = nextval('doc_version_seq'), update_time = EXCLUDED.update_time
             RETURNING version`,
            [...keyVals, JSON.stringify(after.data), ctx.time],
          );
          result.writes.push({ path, version: Number(res.rows[0].version), exists: true });
        }
      }
      await notifyChanged(c, [...ctx.after.keys()]);
      const changes: CommittedChange[] = [...ctx.after.entries()]
        .filter(([path, after]) => after || ctx.before.get(path))
        .map(([path, after]) => ({ path, before: ctx.before.get(path)?.data ?? null, after: after?.data ?? null }));
      return { result, changes };
    });
  });
}

// ---- Server-side helpers (no rules) ---------------------------------------------------

/** Deletes a document and every document nested under it. Returns paths removed. */
export async function deleteRecursive(c: Client, docPath: string): Promise<number> {
  const r = resolveDoc(docPath);
  const prefix = r.def.pattern;
  const ownKeys = [...r.parentIds, r.id];
  let removed = 0;
  // Children first, the document itself last.
  const defs = COLLECTIONS.filter((d) => d.pattern.startsWith(prefix + "/")).sort(
    (a, b) => b.pattern.length - a.pattern.length,
  );
  for (const d of [...defs, r.def]) {
    const cols = keyCols(d).slice(0, ownKeys.length);
    const res = await c.query<{ id: string; [k: string]: unknown }>(
      `DELETE FROM ${q(d.table)} WHERE ${cols.map((col, i) => `${q(col)} = $${i + 1}`).join(" AND ")} RETURNING ${keyCols(d).map(q).join(", ")}`,
      ownKeys,
    );
    removed += res.rowCount ?? 0;
    const paths = res.rows.map((row) => docPathFor(d, d.parentCols.map((pc) => String(row[pc])), String(row.id)));
    await notifyChanged(c, paths);
  }
  return removed;
}

/** Runs a server-side query directly (no rules). */
export async function adminQuery(c: Client | typeof pool, spec: QuerySpec): Promise<Doc[]> {
  const { sql, params, def: d, parentIds } = buildQuery(spec, true);
  const res = await c.query<RowShape & { id: string }>(sql, params);
  return res.rows.map((row) => rowToDoc(resolveDoc(docPathFor(d, parentIds, row.id)), row));
}

export async function adminGet(c: Client | typeof pool, path: string, lock = false): Promise<Doc> {
  const r = resolveDoc(path);
  return rowToDoc(r, await loadRow(c, r, lock));
}

/** Writes a document directly (no rules). data must already be final (no sentinels). */
export async function adminPut(c: Client, path: string, data: Data): Promise<void> {
  const r = resolveDoc(path);
  const cols = keyCols(r.def);
  await c.query(
    `INSERT INTO ${q(r.def.table)} (${cols.map(q).join(", ")}, data)
     VALUES (${cols.map((_, i) => `$${i + 1}`).join(", ")}, $${cols.length + 1}::jsonb)
     ON CONFLICT (${cols.map(q).join(", ")}) DO UPDATE
       SET data = EXCLUDED.data, version = nextval('doc_version_seq'), update_time = now()`,
    [...r.parentIds, r.id, JSON.stringify(data)],
  );
  await notifyChanged(c, [r.path]);
}

export async function adminDelete(c: Client, path: string): Promise<void> {
  const r = resolveDoc(path);
  const cols = keyCols(r.def);
  await c.query(
    `DELETE FROM ${q(r.def.table)} WHERE ${cols.map((col, i) => `${q(col)} = $${i + 1}`).join(" AND ")}`,
    [...r.parentIds, r.id],
  );
  await notifyChanged(c, [r.path]);
}

/** Applies Firestore-style writes server-side, inside the caller's transaction. */
export async function adminWrite(c: Client, w: WriteSpec, time = new Date().toISOString()): Promise<void> {
  const r = resolveDoc(w.path);
  if (w.op === "delete") return adminDelete(c, w.path);
  const data = sanitize(w.data ?? {}, true) as Data;
  const cur = await loadRow(c, r, true);
  let next: Data;
  if (w.op === "create") {
    if (cur) throw new ApiError("already-exists", `Document already exists: ${r.path}`);
    next = applySet(data, time);
  } else if (w.op === "update") {
    if (!cur) throw new ApiError("not-found", `No document to update: ${r.path}`);
    next = applyUpdate(cur.data, data, time);
  } else {
    next = w.merge ? applyMerge(cur?.data ?? null, data, time) : applySet(data, time);
  }
  await adminPut(c, r.path, next);
}
