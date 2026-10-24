/**
 * Document values as they travel over the wire and sit in Postgres (jsonb).
 *
 * Documents are JSON objects. Two kinds of tagged objects are special:
 *
 *  - Timestamps:  {"$ts": "2026-10-24T07:00:00.000Z"}   (stored as-is)
 *  - Write-time sentinels, only allowed inside writes:
 *      {"$sv": "serverTimestamp"}
 *      {"$sv": "delete"}
 *      {"$sv": "increment", "by": 1}
 *      {"$sv": "arrayUnion",  "values": [...]}
 *      {"$sv": "arrayRemove", "values": [...]}
 *
 * Timestamps are always written with Date#toISOString(), so they are a fixed
 * width and sort correctly both as text and as jsonb.
 */

export type Json = null | boolean | number | string | Json[] | { [k: string]: Json };
export type Data = { [k: string]: Json };

export type Ts = { $ts: string };

export function ts(date: Date | string | number): Ts {
  const d = date instanceof Date ? date : new Date(date);
  if (Number.isNaN(d.getTime())) throw new ValueError("Invalid timestamp.");
  return { $ts: d.toISOString() };
}

export function isPlainObject(v: unknown): v is { [k: string]: Json } {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

export function isTs(v: unknown): v is Ts {
  return isPlainObject(v) && typeof v.$ts === "string" && Object.keys(v).length === 1;
}

export function tsMillis(v: unknown): number | null {
  if (!isTs(v)) return null;
  const n = Date.parse(v.$ts);
  return Number.isNaN(n) ? null : n;
}

export function isSentinel(v: unknown): v is { $sv: string; by?: number; values?: Json[] } {
  return isPlainObject(v) && typeof v.$sv === "string";
}

export class ValueError extends Error {}

/** Names that would reach Object.prototype; never valid field names. */
const FORBIDDEN_KEYS = new Set(["__proto__", "constructor", "prototype"]);

function checkKey(k: string): void {
  if (FORBIDDEN_KEYS.has(k)) throw new ValueError(`"${k}" is not a valid field name.`);
}

/** Checks a value coming from a client and normalises its timestamps. */
export function sanitize(v: unknown, allowSentinels: boolean, depth = 0): Json {
  if (depth > 32) throw new ValueError("Value is nested too deeply.");
  if (v === null || typeof v === "boolean" || typeof v === "string") return v as Json;
  if (typeof v === "number") {
    if (!Number.isFinite(v)) throw new ValueError("Numbers must be finite.");
    return v;
  }
  if (Array.isArray(v)) {
    return v.map((x) => {
      if (isSentinel(x)) throw new ValueError("Sentinels are not allowed inside arrays.");
      return sanitize(x, false, depth + 1);
    });
  }
  if (isPlainObject(v)) {
    if ("$ts" in v) {
      if (!isTs(v)) throw new ValueError("Malformed timestamp.");
      return ts(v.$ts);
    }
    if ("$sv" in v) {
      if (!allowSentinels) throw new ValueError("Sentinels are only allowed in writes.");
      switch (v.$sv) {
        case "serverTimestamp":
        case "delete":
          return { $sv: v.$sv };
        case "increment": {
          const by = (v as { by?: unknown }).by;
          if (typeof by !== "number" || !Number.isFinite(by)) throw new ValueError("increment needs a number.");
          return { $sv: "increment", by };
        }
        case "arrayUnion":
        case "arrayRemove": {
          const values = (v as { values?: unknown }).values;
          if (!Array.isArray(values)) throw new ValueError(`${v.$sv} needs values.`);
          return { $sv: v.$sv, values: values.map((x) => sanitize(x, false, depth + 1)) };
        }
        default:
          throw new ValueError(`Unknown sentinel ${String(v.$sv)}.`);
      }
    }
    const out: Data = {};
    for (const [k, x] of Object.entries(v)) {
      if (k.length === 0 || k.length > 1500) throw new ValueError("Bad field name.");
      if (k.startsWith("$")) throw new ValueError("Field names may not start with $.");
      checkKey(k);
      out[k] = sanitize(x, allowSentinels, depth + 1);
    }
    return out;
  }
  throw new ValueError("Unsupported value.");
}

/** Order-independent deep equality (object keys in any order). */
export function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (typeof a !== typeof b) return false;
  if (a === null || b === null) return false;
  if (Array.isArray(a)) {
    if (!Array.isArray(b) || a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) if (!deepEqual(a[i], b[i])) return false;
    return true;
  }
  if (Array.isArray(b)) return false;
  if (typeof a === "object") {
    const ao = a as Record<string, unknown>;
    const bo = b as Record<string, unknown>;
    const ak = Object.keys(ao);
    if (ak.length !== Object.keys(bo).length) return false;
    for (const k of ak) {
      if (!(k in bo) || !deepEqual(ao[k], bo[k])) return false;
    }
    return true;
  }
  return false;
}

function clone<T extends Json>(v: T): T {
  return v === null || typeof v !== "object" ? v : (JSON.parse(JSON.stringify(v)) as T);
}

/** Turns a sentinel into its final value, given the field's old value. */
function resolveSentinel(s: { $sv: string; by?: number; values?: Json[] }, old: Json | undefined, now: string): Json | undefined {
  switch (s.$sv) {
    case "serverTimestamp":
      return { $ts: now };
    case "delete":
      return undefined;
    case "increment":
      return (typeof old === "number" ? old : 0) + (s.by ?? 0);
    case "arrayUnion": {
      const arr = Array.isArray(old) ? [...old] : [];
      for (const x of s.values ?? []) if (!arr.some((y) => deepEqual(x, y))) arr.push(x);
      return arr;
    }
    case "arrayRemove": {
      const arr = Array.isArray(old) ? old : [];
      return arr.filter((y) => !(s.values ?? []).some((x) => deepEqual(x, y)));
    }
    default:
      throw new ValueError(`Unknown sentinel ${s.$sv}.`);
  }
}

/** A full value with every sentinel resolved (for set without merge). */
function resolveAll(v: Json, old: Json | undefined, now: string): Json | undefined {
  if (isSentinel(v)) return resolveSentinel(v, old, now);
  if (isPlainObject(v) && !isTs(v)) {
    const out: Data = {};
    for (const [k, x] of Object.entries(v)) {
      const r = resolveAll(x, undefined, now);
      if (r !== undefined) out[k] = r;
    }
    return out;
  }
  return v;
}

/** set(data) with no merge: replaces the document. */
export function applySet(data: Data, now: string): Data {
  return resolveAll(data, undefined, now) as Data;
}

/** set(data, {merge: true}): maps are merged recursively. */
export function applyMerge(old: Data | null, data: Data, now: string): Data {
  const out: Data = old ? clone(old) : {};
  mergeInto(out, data, now);
  return out;
}

function mergeInto(target: Data, patch: Data, now: string): void {
  for (const [k, v] of Object.entries(patch)) {
    if (isSentinel(v)) {
      const r = resolveSentinel(v, target[k], now);
      if (r === undefined) delete target[k];
      else target[k] = r;
    } else if (isPlainObject(v) && !isTs(v)) {
      const cur = target[k];
      const next: Data = isPlainObject(cur) && !isTs(cur) ? cur : {};
      mergeInto(next, v, now);
      target[k] = next;
    } else {
      target[k] = v;
    }
  }
}

/** Splits "a.b.c" (Firestore-style field paths in update()). Backticks quote a segment. */
export function splitFieldPath(path: string): string[] {
  const out: string[] = [];
  let cur = "";
  let quoted = false;
  for (const ch of path) {
    if (ch === "`") quoted = !quoted;
    else if (ch === "." && !quoted) {
      out.push(cur);
      cur = "";
    } else cur += ch;
  }
  out.push(cur);
  if (out.some((s) => s.length === 0)) throw new ValueError(`Bad field path "${path}".`);
  out.forEach(checkKey);
  return out;
}

/** update({"a.b": v}): each key is a field path; the doc must exist. */
export function applyUpdate(old: Data, fields: Data, now: string): Data {
  const out = clone(old);
  for (const [key, v] of Object.entries(fields)) {
    const segs = splitFieldPath(key);
    let node: Data = out;
    for (let i = 0; i < segs.length - 1; i++) {
      const cur = node[segs[i]];
      if (!isPlainObject(cur) || isTs(cur)) node[segs[i]] = {};
      node = node[segs[i]] as Data;
    }
    const last = segs[segs.length - 1];
    const r = isSentinel(v) ? resolveSentinel(v, node[last], now) : resolveAll(v, undefined, now);
    if (r === undefined) delete node[last];
    else node[last] = r;
  }
  return out;
}

/** Top-level keys that differ between two documents (rules' diff().affectedKeys()). */
export function affectedKeys(after: Data | null | undefined, before: Data | null | undefined): Set<string> {
  const a = after ?? {};
  const b = before ?? {};
  const out = new Set<string>();
  for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
    if (!(k in a) || !(k in b) || !deepEqual(a[k], b[k])) out.add(k);
  }
  return out;
}

/** Reads a nested field ("a.b") from a document; undefined when missing. */
export function getField(data: Data | null | undefined, path: string): Json | undefined {
  let node: Json | undefined = data ?? undefined;
  for (const seg of splitFieldPath(path)) {
    if (!isPlainObject(node) || isTs(node) || !Object.prototype.hasOwnProperty.call(node, seg)) return undefined;
    node = node[seg];
  }
  return node;
}
