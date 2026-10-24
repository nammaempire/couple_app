/**
 * Every document collection the app uses, and the Postgres table behind it.
 *
 * Each collection is its own table. A row is one document:
 *   - the ids of its parent documents (e.g. couple_id) and its own id
 *   - data     jsonb   the document's fields
 *   - version  bigint  changes on every write (optimistic transactions)
 *   - create_time / update_time
 *
 * Paths look like Firestore's: "couples/{coupleId}/messages/{messageId}".
 */

export interface CollectionDef {
  /** Path pattern of a document in this collection. */
  pattern: string;
  /** Postgres table name. */
  table: string;
  /** Column names for the parent ids, outermost first. */
  parentCols: string[];
  /** Extra indexes: jsonb field paths that are filtered or ordered on. */
  indexes?: string[][];
}

function def(pattern: string, table: string, indexes?: string[][]): CollectionDef {
  const params = [...pattern.matchAll(/\{(\w+)\}/g)].map((m) => m[1]);
  const parentCols = params.slice(0, -1).map(snake);
  return { pattern, table, parentCols, indexes };
}

function snake(s: string): string {
  return s.replace(/[A-Z]/g, (c) => "_" + c.toLowerCase());
}

const C = "couples/{coupleId}";

export const COLLECTIONS: CollectionDef[] = [
  def("users/{userId}", "users", [["coupleId"]]),
  def("users/{userId}/devices/{deviceId}", "user_devices"),
  def("users/{userId}/securityEvents/{eventId}", "user_security_events", [["createdAt"]]),
  def("phoneIndex/{e164}", "phone_index", [["uid"]]),
  def("pairRequests/{requestId}", "pair_requests", [["toUid"], ["fromUid"], ["coupleId"]]),
  def("purchases/{purchaseId}", "purchases", [["coupleId"]]),
  def("invites/{code}", "invites", [["coupleId"]]),
  def("couples/{coupleId}", "couples", [["separation", "effectiveAt"]]),
  def(`${C}/messages/{messageId}`, "couple_messages", [["sentAt"]]),
  def(`${C}/moods/{userId}`, "couple_moods"),
  def(`${C}/dailyQuestions/{dateKey}`, "couple_daily_questions"),
  def(`${C}/call/{callId}`, "couple_calls"),
  def(`${C}/memories/{memoryId}`, "couple_memories"),
  def(`${C}/events/{eventId}`, "couple_events"),
  def(`${C}/notes/{noteId}`, "couple_notes"),
  def(`${C}/notes/{noteId}/sealed/{docId}`, "couple_note_sealed"),
  def(`${C}/datePlans/{planId}`, "couple_date_plans"),
  def(`${C}/bucketList/{itemId}`, "couple_bucket_list"),
  def(`${C}/wishlist/{itemId}`, "couple_wishlist"),
  def(`${C}/wishlistClaims/{itemId}`, "couple_wishlist_claims"),
  def(`${C}/places/{placeId}`, "couple_places"),
  def(`${C}/expenses/{expenseId}`, "couple_expenses"),
  def(`${C}/deviceChecks/{checkId}`, "couple_device_checks"),
  def(`${C}/gifts/{giftId}`, "couple_gifts"),
  def(`${C}/books/{bookId}`, "couple_books"),
  def(`${C}/vault/{docId}`, "couple_vault"),
  def(`${C}/vaultItems/{itemId}`, "couple_vault_items"),
  def(`${C}/vaultEvents/{eventId}`, "couple_vault_events"),
  def(`${C}/songs/{songId}`, "couple_songs"),
  def(`${C}/videos/{videoId}`, "couple_videos"),
  def(`${C}/listening/{docId}`, "couple_listening"),
  def(`${C}/watching/{docId}`, "couple_watching"),
  def(`${C}/settings/{docId}`, "couple_settings"),
  def(`${C}/games/{gameId}`, "couple_games"),
  def(`${C}/games/{gameId}/secret/{docId}`, "couple_game_secrets"),
  def(`${C}/nudges/{nudgeId}`, "couple_nudges"),
];

export interface ResolvedDoc {
  def: CollectionDef;
  /** Full document path, e.g. "couples/abc/messages/m1". */
  path: string;
  /** Path of the collection, e.g. "couples/abc/messages". */
  collectionPath: string;
  id: string;
  /** Parent id values, in parentCols order. */
  parentIds: string[];
  /** Pattern params, e.g. {coupleId: "abc", messageId: "m1"}. */
  params: Record<string, string>;
}

export interface ResolvedCollection {
  def: CollectionDef;
  path: string;
  parentIds: string[];
  params: Record<string, string>;
}

export class PathError extends Error {}

const ID_RE = /^[A-Za-z0-9_\-+.@:=]{1,200}$/;

export function validId(s: string): boolean {
  return ID_RE.test(s) && s !== "." && s !== "..";
}

function splitPath(path: string): string[] {
  const segs = path.replace(/^\/+|\/+$/g, "").split("/");
  if (segs.some((s) => s.length === 0)) throw new PathError(`Bad path "${path}".`);
  return segs;
}

function matchPattern(segs: string[], pattern: string): Record<string, string> | null {
  const p = pattern.split("/");
  if (p.length !== segs.length) return null;
  const params: Record<string, string> = {};
  for (let i = 0; i < p.length; i++) {
    const m = /^\{(\w+)\}$/.exec(p[i]);
    if (m) {
      if (!validId(segs[i])) return null;
      params[m[1]] = segs[i];
    } else if (p[i] !== segs[i]) return null;
  }
  return params;
}

export function resolveDoc(path: string): ResolvedDoc {
  const segs = splitPath(path);
  if (segs.length % 2 !== 0) throw new PathError(`"${path}" is not a document path.`);
  for (const d of COLLECTIONS) {
    const params = matchPattern(segs, d.pattern);
    if (params) {
      const values = Object.values(params);
      return {
        def: d,
        path: segs.join("/"),
        collectionPath: segs.slice(0, -1).join("/"),
        id: segs[segs.length - 1],
        parentIds: values.slice(0, -1),
        params,
      };
    }
  }
  throw new PathError(`Unknown document path "${path}".`);
}

export function resolveCollection(path: string): ResolvedCollection {
  const segs = splitPath(path);
  if (segs.length % 2 !== 1) throw new PathError(`"${path}" is not a collection path.`);
  // Resolve with a placeholder id, then drop it.
  const r = resolveDoc([...segs, "x"].join("/"));
  const { [Object.keys(r.params).pop()!]: _drop, ...params } = r.params;
  return { def: r.def, path: segs.join("/"), parentIds: r.parentIds, params };
}

/** Builds a document path from a table row's keys. */
export function docPathFor(d: CollectionDef, parentIds: string[], id: string): string {
  const p = d.pattern.split("/");
  const vals = [...parentIds, id];
  let i = 0;
  return p.map((s) => (/^\{\w+\}$/.test(s) ? vals[i++] : s)).join("/");
}

function q(ident: string): string {
  return `"${ident.replace(/"/g, '""')}"`;
}

/** DDL for every table (idempotent). */
export function schemaSql(): string {
  const out: string[] = [
    `CREATE SEQUENCE IF NOT EXISTS doc_version_seq;`,
  ];
  for (const d of COLLECTIONS) {
    const cols = [...d.parentCols, "id"];
    out.push(
      `CREATE TABLE IF NOT EXISTS ${q(d.table)} (
${cols.map((c) => `  ${q(c)} text NOT NULL,`).join("\n")}
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  version bigint NOT NULL DEFAULT nextval('doc_version_seq'),
  create_time timestamptz NOT NULL DEFAULT now(),
  update_time timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (${cols.map(q).join(", ")})
);`,
    );
    for (const fieldPath of d.indexes ?? []) {
      const name = `${d.table}_${fieldPath.join("_")}_idx`.toLowerCase().slice(0, 63);
      const keys = [...d.parentCols.map(q), `(data #> '{${fieldPath.join(",")}}')`];
      out.push(`CREATE INDEX IF NOT EXISTS ${q(name)} ON ${q(d.table)} (${keys.join(", ")});`);
    }
  }
  return out.join("\n\n");
}

export { q as quoteIdent };
