/**
 * A small rules engine with the same shape as Firestore security rules.
 *
 * Each rule set lists path patterns with allow-functions. An operation is
 * allowed when ANY matching allow-function returns true; a thrown error (for
 * example reading a field of a missing document) counts as false, just like
 * in Firestore rules.
 *
 *   get, list           <- read
 *   create, update, delete <- write
 */
import { affectedKeys, deepEqual, getField, isPlainObject, isTs, tsMillis, type Data, type Json } from "../values.js";

export type Op = "get" | "list" | "create" | "update" | "delete";

export interface AuthInfo {
  uid: string;
  /** Decoded Firebase ID token claims (phone_number, email, firebase.sign_in_provider, …). */
  token: Record<string, unknown>;
}

export interface DocLike {
  id: string;
  data: Data;
}

export interface RuleContext {
  auth: AuthInfo | null;
  /** Commit/request time as an ISO string; serverTimestamp() values equal it. */
  time: string;
  params: Record<string, string>;
  path: string;
  /** The stored document (null when it doesn't exist yet). */
  resource: DocLike | null;
  /** For writes: the document as it will be after the write (null for delete). */
  request: { resource: DocLike | null };
  /** Document as it was before this request. Null when missing. */
  get(path: string): Promise<DocLike | null>;
  exists(path: string): Promise<boolean>;
  /** Document as it will be once the whole commit applies. */
  getAfter(path: string): Promise<DocLike | null>;
  existsAfter(path: string): Promise<boolean>;
}

export type Allow = (c: RuleContext) => boolean | Promise<boolean>;

export interface Rule {
  pattern: string;
  read?: Allow;
  get?: Allow;
  list?: Allow;
  write?: Allow;
  create?: Allow;
  update?: Allow;
  delete?: Allow;
}

function matches(pattern: string, path: string): Record<string, string> | null {
  const p = pattern.split("/");
  const s = path.split("/");
  if (p.length !== s.length) return null;
  const params: Record<string, string> = {};
  for (let i = 0; i < p.length; i++) {
    const m = /^\{(\w+)\}$/.exec(p[i]);
    if (m) params[m[1]] = s[i];
    else if (p[i] !== s[i]) return null;
  }
  return params;
}

function allowsFor(rule: Rule, op: Op): Allow[] {
  const out: (Allow | undefined)[] = [];
  if (op === "get" || op === "list") out.push(rule[op], rule.read);
  else out.push(rule[op], rule.write);
  return out.filter((x): x is Allow => typeof x === "function");
}

export async function evaluate(
  rules: Rule[],
  op: Op,
  base: Omit<RuleContext, "params">,
): Promise<boolean> {
  for (const rule of rules) {
    const params = matches(rule.pattern, base.path);
    if (!params) continue;
    for (const allow of allowsFor(rule, op)) {
      try {
        if (await allow({ ...base, params })) return true;
      } catch {
        // An error in a rule denies, like Firestore.
      }
    }
  }
  return false;
}

// ---- Helpers that mirror the rules language --------------------------------

/** request.auth != null */
export const signedIn = (c: RuleContext): boolean => c.auth !== null;

export const uid = (c: RuleContext): string | null => c.auth?.uid ?? null;

/** The incoming document's data (request.resource.data). Throws if absent. */
export function newData(c: RuleContext): Data {
  if (!c.request.resource) throw new Error("no request.resource");
  return c.request.resource.data;
}

/** The stored document's data (resource.data). Throws if absent. */
export function oldData(c: RuleContext): Data {
  if (!c.resource) throw new Error("no resource");
  return c.resource.data;
}

/** request.resource.data.diff(resource.data).affectedKeys() */
export function changedKeys(c: RuleContext): Set<string> {
  return affectedKeys(c.request.resource?.data, c.resource?.data);
}

/** keys().hasOnly([...]) */
export function hasOnly(keys: Iterable<string>, allowed: string[]): boolean {
  for (const k of keys) if (!allowed.includes(k)) return false;
  return true;
}

/** keys().hasAll([...]) */
export function hasAll(keys: Iterable<string>, required: string[]): boolean {
  const set = new Set(keys);
  return required.every((k) => set.has(k));
}

/** keys().hasAny([...]) */
export function hasAny(keys: Iterable<string>, wanted: string[]): boolean {
  for (const k of keys) if (wanted.includes(k)) return true;
  return false;
}

export function keys(d: Data | null | undefined): string[] {
  return d ? Object.keys(d) : [];
}

/** map.get('field', default) — supports dotted paths too. */
export function field<T extends Json | undefined = Json>(d: Data | null | undefined, path: string, fallback: T | null = null): Json | T | null {
  const v = getField(d ?? null, path);
  return v === undefined ? fallback : v;
}

/** `'k' in d` */
export function has(d: Data | null | undefined, k: string): boolean {
  return !!d && Object.prototype.hasOwnProperty.call(d, k);
}

export const isString = (v: unknown): v is string => typeof v === "string";
export const isBool = (v: unknown): v is boolean => typeof v === "boolean";
export const isNumber = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
export const isInt = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v);
export const isFloat = isNumber;
export const isList = (v: unknown): v is Json[] => Array.isArray(v);
export const isMap = (v: unknown): v is Data => isPlainObject(v) && !isTs(v);
export const isTimestamp = (v: unknown): boolean => isTs(v);

/** `v == request.time` (true when the client sent serverTimestamp()). */
export function isRequestTime(c: RuleContext, v: unknown): boolean {
  return isTs(v) && v.$ts === c.time;
}

/** Milliseconds of a timestamp value (throws if it isn't one). */
export function millis(v: unknown): number {
  const n = tsMillis(v);
  if (n === null) throw new Error("not a timestamp");
  return n;
}

/** request.time as milliseconds. */
export function nowMillis(c: RuleContext): number {
  return Date.parse(c.time);
}

/** String / list / map size(). */
export function size(v: unknown): number {
  if (typeof v === "string") return [...v].length;
  if (Array.isArray(v)) return v.length;
  if (isMap(v)) return Object.keys(v).length;
  throw new Error("size() of unsupported value");
}

export const eq = deepEqual;

/** `x in list` */
export function inList(v: unknown, list: unknown): boolean {
  return Array.isArray(list) && list.some((x) => deepEqual(x, v));
}

/** Data of another document (pre-request); throws when missing, like get().data. */
export async function getData(c: RuleContext, path: string): Promise<Data> {
  const d = await c.get(path);
  if (!d) throw new Error(`missing ${path}`);
  return d.data;
}

export async function getAfterData(c: RuleContext, path: string): Promise<Data> {
  const d = await c.getAfter(path);
  if (!d) throw new Error(`missing ${path}`);
  return d.data;
}
