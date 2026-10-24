/**
 * Pure helpers for the one-time Firebase → Postgres/S3 import:
 * value conversion, Storage URL rewriting, argument parsing and the small
 * interfaces the importer reads Firebase through (so tests can fake them).
 *
 * Nothing in here talks to Firebase, Postgres or S3.
 */
import type { Readable } from "node:stream";
import type { Data, Json } from "../src/values.js";

// ---- Source interfaces --------------------------------------------------------------

/** One Firestore document as the importer sees it. */
export interface SourceDoc {
  /** Full path, e.g. "couples/c1/messages/m1". */
  path: string;
  /** False for a "missing" document that only has subcollections. */
  exists: boolean;
  data?: Record<string, unknown>;
  createTime?: Date;
  updateTime?: Date;
}

export interface FirestoreSource {
  /** Ids of the root collections. */
  rootCollections(): Promise<string[]>;
  /** Ids of a document's subcollections. */
  subcollections(docPath: string): Promise<string[]>;
  /** Every document in a collection (including missing parents), in pages. */
  documents(collectionPath: string): AsyncIterable<SourceDoc[]>;
}

export interface SourceObject {
  name: string;
  size: number;
  contentType?: string;
  metadata?: Record<string, unknown>;
}

export interface StorageSource {
  /** Every object in the bucket, in pages. */
  list(): AsyncIterable<SourceObject[]>;
  open(name: string): Readable;
}

// ---- Value conversion ---------------------------------------------------------------

export interface ConvertCtx {
  /** Firebase Storage bucket whose URLs are rewritten. */
  sourceBucket: string;
  /** Builds the new server's download URL for a storage path. */
  toUrl: (path: string) => string;
  /** Collected warnings (strings). */
  warn: (msg: string) => void;
  /** Called for every rewritten URL with the storage path it pointed at. */
  onRewrite?: (path: string, from: string) => void;
  /** Called for Firebase Storage URLs of another bucket (left unchanged). */
  onForeignUrl?: (url: string) => void;
}

const MAX_DEPTH = 30;

function isPlain(v: object): boolean {
  const p = Object.getPrototypeOf(v);
  return p === Object.prototype || p === null;
}

function isTimestampLike(v: any): boolean {
  return typeof v?.toDate === "function" && typeof v.seconds === "number" && typeof v.nanoseconds === "number";
}

function isGeoPointLike(v: any): boolean {
  return typeof v?.latitude === "number" && typeof v.longitude === "number" && typeof v.isEqual === "function";
}

function isDocRefLike(v: any): boolean {
  return typeof v?.path === "string" && typeof v.collection === "function" && typeof v.listCollections === "function";
}

function isVectorLike(v: any): boolean {
  return typeof v?.toArray === "function" && v?.constructor?.name === "VectorValue";
}

/** ISO string with millisecond precision, the server's timestamp format. */
export function isoOf(d: Date): string {
  return d.toISOString();
}

/**
 * Converts one Firestore value to the server's JSON value model.
 * Returns undefined when the field should be dropped.
 */
export function convertValue(v: unknown, ctx: ConvertCtx, where: string, depth = 0): Json | undefined {
  if (depth > MAX_DEPTH) {
    ctx.warn(`${where}: nested too deeply, field dropped`);
    return undefined;
  }
  if (v === null || v === undefined) return null;
  if (typeof v === "boolean") return v;
  if (typeof v === "number") {
    if (!Number.isFinite(v)) {
      ctx.warn(`${where}: ${v} is not storable in JSON, stored as null`);
      return null;
    }
    return v;
  }
  if (typeof v === "bigint") {
    ctx.warn(`${where}: bigint stored as a number`);
    return Number(v);
  }
  if (typeof v === "string") return rewriteString(cleanString(v, ctx, where), ctx);
  if (Array.isArray(v)) {
    const out: Json[] = [];
    v.forEach((x, i) => {
      const c = convertValue(x, ctx, `${where}[${i}]`, depth + 1);
      if (c !== undefined) out.push(c);
    });
    return out;
  }
  if (typeof v === "object") {
    if (v instanceof Date) return { $ts: isoOf(v) };
    if (isTimestampLike(v)) return { $ts: isoOf((v as { toDate(): Date }).toDate()) };
    if (isGeoPointLike(v)) {
      const g = v as { latitude: number; longitude: number };
      return { latitude: g.latitude, longitude: g.longitude };
    }
    if (isDocRefLike(v)) return (v as { path: string }).path;
    if (v instanceof Uint8Array) {
      ctx.warn(`${where}: bytes stored as a base64 string`);
      return Buffer.from(v.buffer, v.byteOffset, v.byteLength).toString("base64");
    }
    if (isVectorLike(v)) {
      ctx.warn(`${where}: vector stored as a list of numbers`);
      return (v as { toArray(): number[] }).toArray();
    }
    if (!isPlain(v)) {
      ctx.warn(`${where}: unsupported value (${(v as object).constructor?.name ?? "object"}), field dropped`);
      return undefined;
    }
    return convertMap(v as Record<string, unknown>, ctx, where, depth);
  }
  ctx.warn(`${where}: unsupported value (${typeof v}), field dropped`);
  return undefined;
}

// Postgres jsonb can't hold U+0000 or unpaired UTF-16 surrogates.
const BAD_CHARS = /\u0000|[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/g;

/** Removes characters Postgres jsonb rejects (with a warning). */
export function cleanString(s: string, ctx: Pick<ConvertCtx, "warn">, where: string): string {
  BAD_CHARS.lastIndex = 0;
  if (!BAD_CHARS.test(s)) return s;
  ctx.warn(`${where}: text had characters Postgres can't store (NUL or broken emoji); replaced`);
  return s.replace(BAD_CHARS, (c) => (c === "\u0000" ? "" : "\ufffd"));
}

function convertMap(m: Record<string, unknown>, ctx: ConvertCtx, where: string, depth: number): Data {
  const out: Data = {};
  for (const [rawKey, x] of Object.entries(m)) {
    const k = cleanString(rawKey, ctx, where || "field name");
    const at = where ? `${where}.${k}` : k;
    if (k.startsWith("$")) {
      ctx.warn(`${at}: field names may not start with "$", field dropped`);
      continue;
    }
    if (k.length === 0 || k.length > 1500) {
      ctx.warn(`${at}: bad field name, field dropped`);
      continue;
    }
    const c = convertValue(x, ctx, at, depth + 1);
    if (c !== undefined) out[k] = c;
  }
  return out;
}

/** Converts a whole document's fields. [docPath] is used in warnings. */
export function convertDoc(data: Record<string, unknown>, ctx: ConvertCtx, docPath: string): Data {
  return convertMap(data, { ...ctx, warn: (m) => ctx.warn(`${docPath} ${m}`) }, "", 0);
}

// ---- Storage URL rewriting ----------------------------------------------------------

export interface StorageUrlRef {
  bucket: string;
  path: string;
}

function safeDecode(s: string): string | null {
  try {
    return decodeURIComponent(s);
  } catch {
    return null;
  }
}

/**
 * The bucket and object path behind a Firebase/Google Cloud Storage URL, or null.
 * Understands:
 *   https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<encoded path>?alt=media&token=…
 *   https://storage.googleapis.com/<bucket>/<path>
 *   https://<bucket>.storage.googleapis.com/<path>
 *   gs://<bucket>/<path>
 */
export function parseStorageUrl(s: string): StorageUrlRef | null {
  const str = s.trim();
  if (str.length > 4096) return null;
  const gs = /^gs:\/\/([^/?#]+)\/([^?#]+)$/.exec(str);
  if (gs) return { bucket: gs[1], path: gs[2] };
  if (!/^https?:\/\//i.test(str)) return null;
  let u: URL;
  try {
    u = new URL(str);
  } catch {
    return null;
  }
  const host = u.hostname.toLowerCase();
  if (host === "firebasestorage.googleapis.com") {
    const m = /^\/v0\/b\/([^/]+)\/o\/(.+)$/.exec(u.pathname);
    if (!m) return null;
    const bucket = safeDecode(m[1]);
    const path = safeDecode(m[2]);
    return bucket && path ? { bucket, path } : null;
  }
  if (host === "storage.googleapis.com") {
    const m = /^\/([^/]+)\/(.+)$/.exec(u.pathname);
    if (!m || m[1] === "download" || m[1] === "storage") return null; // JSON API forms, not used by the app
    const path = safeDecode(m[2]);
    return path ? { bucket: m[1], path } : null;
  }
  if (host.endsWith(".storage.googleapis.com")) {
    const bucket = host.slice(0, -".storage.googleapis.com".length);
    const path = safeDecode(u.pathname.replace(/^\/+/, ""));
    return bucket && path ? { bucket, path } : null;
  }
  return null;
}

/** Returns the rewritten string, or the input unchanged. */
export function rewriteString(s: string, ctx: ConvertCtx): string {
  const t = s.trimStart();
  if (!(t.startsWith("http") || t.startsWith("gs:"))) return s;
  const ref = parseStorageUrl(s);
  if (!ref || !ref.path || ref.path.endsWith("/")) return s;
  if (ref.bucket !== ctx.sourceBucket) {
    ctx.onForeignUrl?.(s);
    return s;
  }
  ctx.onRewrite?.(ref.path, s);
  return ctx.toUrl(ref.path);
}

// ---- Storage objects ------------------------------------------------------------------

/** Custom metadata keys that are Firebase-internal and not copied. */
const DROP_META = new Set(["firebasestoragedownloadtokens"]);

/**
 * Custom metadata for the target bucket: keys lower-cased (the server's
 * storage rules read them lower-cased), Firebase's download token dropped,
 * values as strings. Values S3 can't carry in a header are dropped with a warning.
 */
export function convertMetadata(meta: Record<string, unknown> | undefined, warn: (m: string) => void, name: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(meta ?? {})) {
    const key = k.toLowerCase();
    if (DROP_META.has(key) || v === null || v === undefined) continue;
    const val = String(v);
    // S3 user metadata travels as HTTP headers: printable ASCII only.
    if (!/^[a-z0-9_-]{1,64}$/.test(key) || !/^[\x20-\x7e]*$/.test(val)) {
      warn(`${name}: metadata "${k}" can't be stored in S3 metadata, dropped`);
      continue;
    }
    out[key] = val;
  }
  return out;
}

/** Same rule the server applies to paths uploaded/deleted through its API. */
const SERVER_PATH_RE = /^[A-Za-z0-9_\-+.@=]+(\/[A-Za-z0-9_\-+.@=]+){1,8}$/;
export function serverAcceptsPath(p: string): boolean {
  return SERVER_PATH_RE.test(p) && !p.split("/").some((s) => s === "." || s === "..");
}

// ---- Paths ---------------------------------------------------------------------------

/** "foo/abc/bar/def" → "foo/{id}/bar/{id}" (for grouping skipped paths). */
export function genericPath(docPath: string): string {
  return docPath
    .split("/")
    .map((s, i) => (i % 2 === 1 ? "{id}" : s))
    .join("/");
}

// ---- Arguments ------------------------------------------------------------------------

export interface ImportOptions {
  dryRun: boolean;
  only: "all" | "firestore" | "storage";
  /** Root collections to import (empty = all). */
  collections: string[];
  verbose: boolean;
  envFile?: string;
  concurrency: number;
  help: boolean;
}

export class ArgError extends Error {}

export function parseArgs(argv: string[]): ImportOptions {
  const o: ImportOptions = { dryRun: false, only: "all", collections: [], verbose: false, concurrency: 4, help: false };
  for (const a of argv) {
    const [k, v] = a.includes("=") ? [a.slice(0, a.indexOf("=")), a.slice(a.indexOf("=") + 1)] : [a, undefined];
    switch (k) {
      case "--dry-run":
        o.dryRun = true;
        break;
      case "--verbose":
      case "-v":
        o.verbose = true;
        break;
      case "--help":
      case "-h":
        o.help = true;
        break;
      case "--only":
        if (v !== "firestore" && v !== "storage") throw new ArgError(`--only must be "firestore" or "storage".`);
        o.only = v;
        break;
      case "--collection":
        if (!v) throw new ArgError("--collection needs a value, e.g. --collection=couples");
        o.collections.push(...v.split(",").map((s) => s.trim()).filter(Boolean));
        break;
      case "--concurrency": {
        const n = Number(v);
        if (!Number.isInteger(n) || n < 1 || n > 32) throw new ArgError("--concurrency must be 1-32.");
        o.concurrency = n;
        break;
      }
      case "--env-file":
        if (!v) throw new ArgError("--env-file needs a path.");
        o.envFile = v;
        break;
      default:
        throw new ArgError(`Unknown option "${a}". Try --help.`);
    }
  }
  return o;
}

export const USAGE = `Copies Firestore documents and Firebase Storage files into the new backend.

Usage: npm run import-firebase -- [options]

  --dry-run             read and convert everything, write nothing
  --only=firestore      only documents      --only=storage   only files
  --collection=<name>   only this root collection (repeat or comma-separate)
  --concurrency=<n>     parallel file copies (default 4)
  --env-file=<path>     load environment variables from a file first
  --verbose             log every document and file
  --help                this text

See scripts/README-import.md.`;

// ---- Misc -----------------------------------------------------------------------------

/** Runs fn over items with at most [limit] in flight. */
export async function mapLimit<T>(items: T[], limit: number, fn: (x: T, i: number) => Promise<void>): Promise<void> {
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const i = next++;
      await fn(items[i], i);
    }
  });
  await Promise.all(workers);
}

export function formatBytes(n: number): string {
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  let x = n;
  while (x >= 1024 && i < u.length - 1) {
    x /= 1024;
    i++;
  }
  return `${i === 0 ? x : x.toFixed(1)} ${u[i]}`;
}

// ---- Summary --------------------------------------------------------------------------

export interface TableCounts {
  inserted: number;
  updated: number;
  /** Already identical, or changed in the new backend after the Firestore copy. */
  unchanged: number;
}

export interface Summary {
  dryRun: boolean;
  docsRead: number;
  /** Documents that don't exist but have subcollections (walked, not stored). */
  missingParents: number;
  tables: Record<string, TableCounts>;
  /** Skipped document paths, grouped by shape. */
  skipped: Record<string, { count: number; reason: string; examples: string[] }>;
  urlsRewritten: number;
  /** Storage URLs of another bucket, left unchanged. */
  foreignUrls: number;
  files: { listed: number; copied: number; skipped: number; failed: number; bytes: number };
  /** Rewritten links whose file isn't in the source bucket (only when both parts ran). */
  linksToMissingFiles: string[];
  warnings: string[];
  fatal?: string;
}

export function newSummary(dryRun: boolean): Summary {
  return {
    dryRun,
    docsRead: 0,
    missingParents: 0,
    tables: {},
    skipped: {},
    urlsRewritten: 0,
    foreignUrls: 0,
    files: { listed: 0, copied: 0, skipped: 0, failed: 0, bytes: 0 },
    linksToMissingFiles: [],
    warnings: [],
  };
}

export function skipDoc(s: Summary, path: string, reason: string): void {
  const g = genericPath(path);
  const e = (s.skipped[g] ??= { count: 0, reason, examples: [] });
  e.count++;
  if (e.examples.length < 3) e.examples.push(path);
}

export function totalDocsWritten(s: Summary): number {
  return Object.values(s.tables).reduce((n, t) => n + t.inserted + t.updated, 0);
}

export function formatSummary(s: Summary, maxList = 50): string {
  const L: string[] = [];
  const dry = s.dryRun ? " (dry run: nothing was written)" : "";
  L.push("", "==================== Import summary" + dry + " ====================");
  L.push("", `Firestore: ${s.docsRead} documents read` + (s.missingParents ? ` (${s.missingParents} empty parent documents)` : ""));
  const tables = Object.entries(s.tables).sort(([a], [b]) => a.localeCompare(b));
  if (tables.length) {
    const w = Math.max(...tables.map(([t]) => t.length));
    L.push(s.dryRun ? "  table → documents that would be written" : "  table → new / updated / unchanged");
    for (const [t, c] of tables) {
      L.push(
        s.dryRun
          ? `  ${t.padEnd(w)}  ${c.inserted}`
          : `  ${t.padEnd(w)}  ${c.inserted} / ${c.updated} / ${c.unchanged}   (total ${c.inserted + c.updated + c.unchanged})`,
      );
    }
  }
  const skipped = Object.entries(s.skipped);
  const skippedN = skipped.reduce((n, [, e]) => n + e.count, 0);
  L.push("", `Skipped documents: ${skippedN}`);
  for (const [g, e] of skipped.sort(([, a], [, b]) => b.count - a.count).slice(0, maxList)) {
    L.push(`  ${g}  ×${e.count}  (${e.reason})  e.g. ${e.examples.join(", ")}`);
  }
  L.push("", `Storage links rewritten: ${s.urlsRewritten}` + (s.foreignUrls ? `   (left unchanged, other bucket: ${s.foreignUrls})` : ""));
  if (s.linksToMissingFiles.length) {
    L.push(`  Links to files that are not in the Firebase bucket: ${s.linksToMissingFiles.length}`);
    for (const p of s.linksToMissingFiles.slice(0, 20)) L.push(`    ${p}`);
  }
  const f = s.files;
  L.push(
    "",
    `Storage files: ${f.listed} listed, ${f.copied} ${s.dryRun ? "would be copied" : "copied"} (${formatBytes(f.bytes)}), ` +
      `${f.skipped} already there/skipped, ${f.failed} failed`,
  );
  L.push("", `Warnings: ${s.warnings.length}`);
  for (const w of s.warnings.slice(0, maxList)) L.push(`  - ${w}`);
  if (s.warnings.length > maxList) L.push(`  … and ${s.warnings.length - maxList} more (run with --verbose to see all)`);
  if (s.fatal) L.push("", `STOPPED WITH AN ERROR: ${s.fatal}`, "Fix the problem and run the same command again; finished work is kept.");
  L.push("");
  return L.join("\n");
}
