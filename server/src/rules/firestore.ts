/**
 * Document rules, ported from firestore.rules (the source of truth; keep the
 * two in step). Each `match` block is one entry below with its full path
 * pattern and the same param names; `function`s declared inside a match are
 * local helpers next to it.
 *
 * Semantics kept from the rules language:
 *  - Reading a missing field (`d.x`) is an error, and an error denies. Data is
 *    read through `strict()` views that throw on a missing key, so
 *    `request.resource.data.x == null` fails when `x` is absent, like Firestore.
 *  - `a || b` in rules is true when either side is true even if the other side
 *    errors. Where a left-hand side can error and the right-hand side could
 *    still allow, `or()` is used instead of JS `||`.
 *  - Arithmetic and ordering need numbers / timestamps (`num()`, `ms()`), so a
 *    wrong type errors instead of being coerced.
 */
import * as E from "./engine.js";
import type { Rule, RuleContext as Ctx } from "./engine.js";
import { affectedKeys, isPlainObject, isTs, type Data } from "../values.js";

// ---- Rules-language helpers --------------------------------------------------

/** A value read from a document. Maps are strict views (see `strict`). */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type V = any;
type Thunk = () => boolean | Promise<boolean>;

const RAW = Symbol("raw");
/** Object.prototype's own names, captured at load (never inherited data). */
const PROTO_KEYS = new Set(Object.getOwnPropertyNames(Object.prototype));

const strictHandler: ProxyHandler<Data> = {
  get(t, k) {
    if (k === RAW) return t;
    if (typeof k === "symbol") return Reflect.get(t, k);
    if (Object.prototype.hasOwnProperty.call(t, k)) return strict(t[k]);
    // Let library code probe ($ts, toJSON, Object.prototype members) safely.
    if (k.startsWith("$") || k === "toJSON" || k === "then" || PROTO_KEYS.has(k)) return Reflect.get(t, k);
    throw new Error(`Property ${k} is undefined on object.`);
  },
};

/** A map whose missing fields throw on access, like `map.field` in rules. */
function strict(v: unknown): V {
  if (!isPlainObject(v) || isTs(v)) return v;
  return new Proxy(v as Data, strictHandler);
}

/** The plain value behind a strict view. */
function raw(v: V): V {
  return v !== null && typeof v === "object" && !Array.isArray(v) && v[RAW] ? v[RAW] : v;
}

function asMap(v: V): Data {
  const r = raw(v);
  if (!isPlainObject(r) || isTs(r)) throw new Error("not a map");
  return r as Data;
}

function asList(v: V): V[] {
  if (!Array.isArray(v)) throw new Error("not a list");
  return v;
}

/** request.resource.data */
const D = (c: Ctx): V => strict(E.newData(c));
/** resource.data */
const R = (c: Ctx): V => strict(E.oldData(c));

/** request.auth.uid (an error when signed out). */
function me(c: Ctx): string {
  if (!c.auth) throw new Error("request.auth is null");
  return c.auth.uid;
}

/** request.auth.token.get('phone_number', null) */
function tokenPhone(c: Ctx): V {
  if (!c.auth) throw new Error("request.auth is null");
  const t = c.auth.token;
  return Object.prototype.hasOwnProperty.call(t, "phone_number") ? (t.phone_number ?? null) : null;
}

const signedIn = (c: Ctx): boolean => c.auth !== null;

/** map.get(key, default) */
function get(m: V, k: string, fallback: V): V {
  const d = asMap(m);
  return strict(Object.prototype.hasOwnProperty.call(d, k) ? d[k] : fallback);
}

/** `key in map` */
function has(m: V, k: string): boolean {
  return Object.prototype.hasOwnProperty.call(asMap(m), k);
}

/** map.keys() */
const keys = (m: V): string[] => Object.keys(asMap(m));

/** `x in list` */
const inL = (x: V, list: V): boolean => E.inList(raw(x), asList(list));

const eq = (a: V, b: V): boolean => E.eq(raw(a), raw(b));
const size = (v: V): number => E.size(raw(v));
const isStr = E.isString;
const isBool = E.isBool;
const isInt = E.isInt;
const isNumber = E.isNumber;
const isList = E.isList;
const isMap = (v: V): boolean => E.isMap(raw(v));
const isTimestamp = (v: V): boolean => E.isTimestamp(v);

/** A number for arithmetic / ordering (an error otherwise). */
function num(v: V): number {
  if (!isNumber(v)) throw new Error("not a number");
  return v;
}

/** A timestamp as milliseconds, for ordering (an error otherwise). */
const ms = (v: V): number => E.millis(v);

/** request.time as milliseconds. */
const now = (c: Ctx): number => E.nowMillis(c);

/** `v == request.time` */
const isNow = (c: Ctx, v: V): boolean => E.isRequestTime(c, v);

/** string.matches(re): full match; `re` must be anchored. */
function matches(v: V, re: RegExp): boolean {
  if (typeof v !== "string") throw new Error("not a string");
  return re.test(v);
}

/** request.resource.data.diff(resource.data).affectedKeys() */
function changedKeys(c: Ctx): Set<string> {
  E.newData(c);
  E.oldData(c);
  return E.changedKeys(c);
}

/** a.diff(b).affectedKeys() for two maps. */
const mapDiff = (a: V, b: V): Set<string> => affectedKeys(asMap(a), asMap(b));

/** list.removeAll(items) */
const removeAll = (list: V, items: V[]): V[] => asList(list).filter((x) => !E.inList(x, items));

/** list.concat(items) */
const concat = (list: V, items: V[]): V[] => [...asList(list), ...items];

/**
 * `a || b || …` with the rules language's error handling: true if any side is
 * true (even when another errors), otherwise an error if any side errored.
 */
async function or(...sides: Thunk[]): Promise<boolean> {
  let err: unknown = null;
  for (const side of sides) {
    try {
      if (await side()) return true;
    } catch (e) {
      err ??= e;
    }
  }
  if (err) throw err;
  return false;
}

/** A path segment interpolated with $(…): must be a string. */
function seg(v: V): string {
  if (typeof v !== "string") throw new Error("path segment is not a string");
  return v;
}

// Full-match regexes. RE2's `.` excludes only \n, hence [^\n].
const HTTPS_RE = /^https:\/\/[^\n]+$/; // '^https://.+'
const HTTP_S_RE = /^https?:\/\/[^\n]+$/i; // '(?i)^https?://.+'
const E164_RE = /^[+][1-9][0-9]{6,14}$/;

// ---- Shared functions (top of firestore.rules) ---------------------------------

/** get(coupleDoc(coupleId)).data */
async function coupleData(c: Ctx, coupleId: V = c.params.coupleId): Promise<V> {
  return strict(await E.getData(c, `couples/${seg(coupleId)}`));
}

/** getAfter(coupleDoc(coupleId)).data */
async function coupleAfter(c: Ctx, coupleId: V = c.params.coupleId): Promise<V> {
  return strict(await E.getAfterData(c, `couples/${seg(coupleId)}`));
}

async function isMemberOf(c: Ctx, coupleId: V = c.params.coupleId): Promise<boolean> {
  return signedIn(c) && inL(me(c), (await coupleData(c, coupleId)).memberIds);
}

// Membership as it will be once the current write/batch/transaction commits.
// Used when a couple and a user link are written together.
async function isMemberAfter(c: Ctx, coupleId: V): Promise<boolean> {
  return signedIn(c) && inL(me(c), (await coupleAfter(c, coupleId)).memberIds);
}

/** The users/{userId} profile names a couple and the caller is in it. */
async function inUsersCouple(c: Ctx, userId: string): Promise<boolean> {
  const u = strict(await E.getData(c, `users/${userId}`));
  return get(u, "coupleId", null) !== null && (await isMemberOf(c, u.coupleId));
}

// ---- Users -----------------------------------------------------------------------

// Avatar fields, when present, keep the shape the app reads. The avatar's
// parts aren't listed, so newer app versions can add more.
function avatarOk(c: Ctx): boolean {
  const d = D(c);
  return (
    (!has(d, "avatar") || d.avatar === null || (isMap(d.avatar) && size(d.avatar) <= 24)) &&
    (!has(d, "avatarAsPhoto") || d.avatarAsPhoto === null || isBool(d.avatarAsPhoto))
  );
}

// A phone number on the profile is always the one this account verified by
// SMS. `mutePartner` is a plain switch. The server writes `pairingEndedAt` /
// `pairingEndedHow` when a pairing ends; the person may only clear them.
function profileExtrasOk(c: Ctx, phoneChanged: boolean): boolean {
  const d = D(c);
  return (
    (!phoneChanged || !has(d, "phone") || d.phone === null || eq(d.phone, tokenPhone(c))) &&
    (!has(d, "mutePartner") || isBool(d.mutePartner)) &&
    (!has(d, "blockNewPhoneUntil") || d.blockNewPhoneUntil === null || isTimestamp(d.blockNewPhoneUntil))
  );
}

function pairingEndedUntouched(c: Ctx): boolean {
  const ck = changedKeys(c);
  const d = D(c);
  return (
    (!ck.has("pairingEndedAt") || !has(d, "pairingEndedAt")) &&
    (!ck.has("pairingEndedHow") || !has(d, "pairingEndedHow"))
  );
}

const users: Rule[] = [
  {
    pattern: "users/{userId}",
    // You can read your own profile, and your partner's once you share a
    // couple. Nobody else can see names, photos or emails.
    read: async (c) =>
      signedIn(c) &&
      (me(c) === c.params.userId ||
        (get(R(c), "coupleId", null) !== null && (await isMemberOf(c, R(c).coupleId)))),
    // New profiles start unpaired.
    create: (c) =>
      signedIn(c) &&
      me(c) === c.params.userId &&
      get(D(c), "coupleId", null) === null &&
      !has(D(c), "pairingEndedAt") &&
      avatarOk(c) &&
      profileExtrasOk(c, true),
    // You may edit your own profile. `coupleId` can only point at a couple you
    // are actually a member of (after this write), or be cleared.
    update: async (c) =>
      signedIn(c) &&
      me(c) === c.params.userId &&
      avatarOk(c) &&
      profileExtrasOk(c, changedKeys(c).has("phone")) &&
      pairingEndedUntouched(c) &&
      (!changedKeys(c).has("coupleId") || D(c).coupleId === null || (await isMemberAfter(c, D(c).coupleId))),
    delete: () => false,
  },
  {
    // Phones that passed the new-phone check (recycled-number protection). The
    // owner manages them; the partner may see the list.
    pattern: "users/{userId}/devices/{deviceId}",
    read: async (c) => signedIn(c) && (me(c) === c.params.userId || (await inUsersCouple(c, c.params.userId))),
    create: (c) => {
      const d = D(c);
      return (
        signedIn(c) &&
        me(c) === c.params.userId &&
        E.hasOnly(keys(d), ["name", "addedAt", "lastSeenAt", "via"]) &&
        isStr(d.name) &&
        size(d.name) <= 60 &&
        isNow(c, d.addedAt) &&
        isNow(c, d.lastSeenAt) &&
        inL(d.via, ["first", "partner", "email", "wait"])
      );
    },
    update: (c) =>
      signedIn(c) &&
      me(c) === c.params.userId &&
      E.hasOnly(changedKeys(c), ["lastSeenAt"]) &&
      isNow(c, D(c).lastSeenAt),
    delete: (c) => signedIn(c) && me(c) === c.params.userId,
  },
  {
    // Security notices for the account owner. Their partner may post the one
    // that says they turned down a sign-in on a new phone.
    pattern: "users/{userId}/securityEvents/{eventId}",
    read: (c) => signedIn(c) && me(c) === c.params.userId,
    delete: (c) => signedIn(c) && me(c) === c.params.userId,
    create: async (c) => {
      const d = D(c);
      return (
        signedIn(c) &&
        E.hasOnly(keys(d), ["type", "deviceName", "at"]) &&
        isStr(d.deviceName) &&
        size(d.deviceName) <= 60 &&
        isNow(c, d.at) &&
        ((me(c) === c.params.userId && inL(d.type, ["newPhoneRejected", "newPhoneWaiting", "newPhoneApproved"])) ||
          (eq(d.type, "newPhoneRejected") && (await inUsersCouple(c, c.params.userId))))
      );
    },
    update: () => false,
  },
];

// ---- Phone numbers and pairing by number ---------------------------------------

// pairRequests/{id}: "Asha wants to pair with you". The sender offers their
// couple of one and its invite code; the receiver accepts by joining with that
// code (the invite rules), then marks it.
function e164OrEmpty(v: V): boolean {
  return isStr(v) && (v === "" || matches(v, E164_RE));
}

const pairing: Rule[] = [
  {
    // phoneIndex/{+919876543210}: which account a verified number belongs to,
    // so a partner can be found by number. One doc can be fetched at a time
    // but never listed. Only the account that verified the number by SMS may
    // claim it (a recycled number moves to its new owner).
    pattern: "phoneIndex/{e164}",
    get: (c) => signedIn(c),
    list: () => false,
    create: (c) => phoneIndexWriteOk(c),
    update: (c) => phoneIndexWriteOk(c),
    delete: (c) => signedIn(c) && eq(R(c).uid, me(c)),
  },
  {
    pattern: "pairRequests/{requestId}",
    read: async (c) =>
      signedIn(c) &&
      (await or(
        () => eq(R(c).fromUid, me(c)),
        () => eq(R(c).toUid, me(c)),
      )),
    create: async (c) => {
      const d = D(c);
      return (
        signedIn(c) &&
        E.hasOnly(keys(d), [
          "fromUid", "fromName", "fromPhone", "toUid", "toPhone", "coupleId", "inviteCode", "status", "createdAt",
        ]) &&
        eq(d.fromUid, me(c)) &&
        isStr(d.toUid) &&
        !eq(d.toUid, me(c)) &&
        isStr(d.fromName) &&
        size(d.fromName) <= 60 &&
        e164OrEmpty(d.fromPhone) &&
        e164OrEmpty(d.toPhone) &&
        eq(d.status, "pending") &&
        isNow(c, d.createdAt) &&
        eq((await coupleData(c, d.coupleId)).memberIds, [me(c)]) &&
        eq((await coupleData(c, d.coupleId)).inviteCode, d.inviteCode)
      );
    },
    // Only the status moves, once, out of 'pending': the receiver accepts or
    // declines, the sender cancels.
    update: async (c) =>
      signedIn(c) &&
      E.hasOnly(changedKeys(c), ["status"]) &&
      eq(R(c).status, "pending") &&
      (await or(
        () => eq(me(c), R(c).toUid) && inL(D(c).status, ["accepted", "declined"]),
        () => eq(me(c), R(c).fromUid) && eq(D(c).status, "cancelled"),
      )),
    delete: (c) => signedIn(c) && eq(R(c).fromUid, me(c)),
  },
  {
    // purchases/{hash}: written only by the server when it verifies a Google
    // Play purchase.
    pattern: "purchases/{purchaseId}",
    read: () => false,
    write: () => false,
  },
];

function phoneIndexWriteOk(c: Ctx): boolean {
  const d = D(c);
  return (
    signedIn(c) &&
    eq(tokenPhone(c), c.params.e164) &&
    E.hasOnly(keys(d), ["uid", "createdAt"]) &&
    eq(d.uid, me(c)) &&
    isNow(c, d.createdAt)
  );
}

// ---- Invites ---------------------------------------------------------------------

const invites: Rule[] = [
  {
    // One document per invite code: invites/{code}. Codes can be looked up one
    // at a time (get) but never listed, so they cannot be enumerated.
    pattern: "invites/{code}",
    get: (c) => signedIn(c),
    list: () => false,
    // Created alongside (or for) a couple you belong to, whose invite code is
    // this document's id.
    create: async (c) =>
      signedIn(c) &&
      eq(D(c).createdBy, me(c)) &&
      eq(D(c).used, false) &&
      (await isMemberAfter(c, D(c).coupleId)) &&
      eq((await coupleAfter(c, D(c).coupleId)).inviteCode, c.params.code),
    // Accepting: the joiner marks an unused invite as used by themselves, in
    // the same transaction that adds them to the couple.
    update: async (c) =>
      signedIn(c) &&
      eq(R(c).used, false) &&
      eq(D(c).used, true) &&
      eq(D(c).usedBy, me(c)) &&
      E.hasOnly(changedKeys(c), ["used", "usedBy", "usedAt"]) &&
      (await isMemberAfter(c, R(c).coupleId)),
    // The creator may withdraw their invite.
    delete: (c) => signedIn(c) && eq(R(c).createdBy, me(c)),
  },
];

// ---- Couples ---------------------------------------------------------------------

// Ending a pairing (`separation`). Either partner asks; it takes effect 14 days
// later, or 7 days after the other agrees, whichever is sooner. The other
// partner may agree or decline but can never stop it; only the one who asked
// can cancel. The server deletes everything once `effectiveAt` has passed.
function within(c: Ctx, t: V, days: number): boolean {
  return (
    isTimestamp(t) &&
    ms(t) > now(c) + (days * 1440 - 10) * 60_000 &&
    ms(t) < now(c) + (days * 1440 + 10) * 60_000
  );
}

const SEPARATION_KEYS = ["requestedBy", "requestedAt", "status", "agreedAt", "declinedAt", "effectiveAt"];

function separationOk(c: Ctx): boolean {
  const before = get(R(c), "separation", null);
  const after = get(D(c), "separation", null);
  const u = me(c);
  return (
    !changedKeys(c).has("separation") ||
    // Asking.
    (before === null &&
      after !== null &&
      E.hasOnly(keys(after), SEPARATION_KEYS) &&
      eq(after.requestedBy, u) &&
      isNow(c, after.requestedAt) &&
      eq(after.status, "requested") &&
      after.agreedAt === null &&
      after.declinedAt === null &&
      within(c, after.effectiveAt, 14)) ||
    // Changing their mind: only the one who asked.
    (before !== null && after === null && eq(before.requestedBy, u)) ||
    // The other partner agrees (also after declining): it ends 7 days from
    // now, or on the original date if that is sooner.
    (before !== null &&
      after !== null &&
      !eq(before.requestedBy, u) &&
      inL(before.status, ["requested", "declined"]) &&
      eq(after.status, "agreed") &&
      isNow(c, after.agreedAt) &&
      eq(after.requestedBy, before.requestedBy) &&
      eq(after.requestedAt, before.requestedAt) &&
      eq(after.declinedAt, before.declinedAt) &&
      E.hasOnly(keys(after), SEPARATION_KEYS) &&
      (eq(after.effectiveAt, before.effectiveAt) ||
        (within(c, after.effectiveAt, 7) && ms(after.effectiveAt) <= ms(before.effectiveAt)))) ||
    // The other partner declines: nothing else changes.
    (before !== null &&
      after !== null &&
      !eq(before.requestedBy, u) &&
      eq(before.status, "requested") &&
      eq(after.status, "declined") &&
      isNow(c, after.declinedAt) &&
      eq(after.requestedBy, before.requestedBy) &&
      eq(after.requestedAt, before.requestedAt) &&
      eq(after.agreedAt, before.agreedAt) &&
      eq(after.effectiveAt, before.effectiveAt) &&
      E.hasOnly(keys(after), SEPARATION_KEYS))
  );
}

/** Members edit shared details, but cannot add anyone. */
function memberEdit(c: Ctx): boolean {
  const d = D(c);
  const r = R(c);
  const u = me(c);
  const ck = changedKeys(c);
  return (
    inL(u, r.memberIds) &&
    // The only membership change a member can make is removing themselves.
    (!ck.has("memberIds") || eq(d.memberIds, removeAll(r.memberIds, [u]))) &&
    // Clearing the chat for both is stamped with the server's time.
    (!ck.has("chatClearedAt") || isNow(c, d.chatClearedAt)) &&
    (!ck.has("chatClearedBy") || eq(d.chatClearedBy, u)) &&
    // A shared "no screenshots in our chat" switch.
    (!ck.has("blockScreenshots") || isBool(d.blockScreenshots)) &&
    separationOk(c) &&
    // `ending` is the server's own lock while it deletes a couple.
    !ck.has("ending") &&
    // Premium is granted only by the server after it verifies a purchase. A
    // Memory book credit can only be spent: down by one, never below zero
    // (the book itself is checked under /books).
    !ck.has("premium") &&
    (!ck.has("bookCredits") ||
      (isInt(d.bookCredits) &&
        d.bookCredits === num(get(r, "bookCredits", 0)) - 1 &&
        d.bookCredits >= 0))
  );
}

/**
 * Joining: a non-member adds only themselves to a couple of one, and only by
 * consuming this couple's invite in the same transaction.
 */
async function joining(c: Ctx): Promise<boolean> {
  const d = D(c);
  const r = R(c);
  const u = me(c);
  const invite = `invites/${seg(r.inviteCode)}`;
  return (
    !inL(u, r.memberIds) &&
    size(r.memberIds) === 1 &&
    eq(d.memberIds, concat(r.memberIds, [u])) &&
    E.hasOnly(changedKeys(c), ["memberIds", "activatedAt"]) &&
    eq(strict(await E.getData(c, invite)).coupleId, c.params.coupleId) &&
    eq(strict(await E.getData(c, invite)).used, false) &&
    eq(strict(await E.getAfterData(c, invite)).usedBy, u)
  );
}

const couples: Rule[] = [
  {
    pattern: "couples/{coupleId}",
    // Only the two members can read the couple, which holds the last message
    // preview, dates and nicknames.
    read: (c) => signedIn(c) && inL(me(c), R(c).memberIds),
    create: (c) => signedIn(c) && eq(D(c).memberIds, [me(c)]) && isStr(D(c).inviteCode),
    update: async (c) =>
      signedIn(c) &&
      (await or(
        () => memberEdit(c),
        () => joining(c),
      )),
    // A couple still waiting for a partner can be cancelled by its creator.
    delete: (c) => signedIn(c) && eq(R(c).memberIds, [me(c)]),
  },
];

// ---- Messages ----------------------------------------------------------------------

const SYSTEM_TYPES = ["chatCleared", "screenshot", "screenshotBlock"];

// Couple stickers carry the quote as text (so older app versions still show
// it) and a small `sticker` map naming the scene.
function stickerOk(c: Ctx): boolean {
  const d = D(c);
  return (
    !eq(get(d, "type", ""), "sticker") ||
    (isStr(d.text) &&
      size(d.text) <= 400 &&
      isMap(d.sticker) &&
      isStr(get(d.sticker, "id", "")) &&
      size(get(d.sticker, "id", "")) > 0 &&
      size(get(d.sticker, "id", "")) <= 64)
  );
}

// System lines (chat cleared, screenshot taken, screenshot blocking switched)
// are short text only: no media, replies or reactions.
function systemOk(c: Ctx): boolean {
  const d = D(c);
  return (
    !inL(get(d, "type", ""), SYSTEM_TYPES) ||
    (isStr(d.text) &&
      size(d.text) <= 200 &&
      get(d, "imageUrl", null) === null &&
      get(d, "mediaUrl", null) === null &&
      get(d, "replyTo", null) === null &&
      size(get(d, "reactions", {})) === 0)
  );
}

const messages: Rule[] = [
  {
    pattern: "couples/{coupleId}/messages/{messageId}",
    read: (c) => isMemberOf(c),
    create: async (c) => (await isMemberOf(c)) && eq(D(c).senderId, me(c)) && stickerOk(c) && systemOk(c),
    // Either partner may mark seen, react, or pin — but never change what a
    // message says or who sent it. The sender may delete their own message.
    // "Clear chat for both" first stamps the couple's `chatClearedAt` (server
    // time), then either partner may delete any message sent up to that moment.
    update: async (c) =>
      (await isMemberOf(c)) &&
      E.hasOnly(changedKeys(c), ["seen", "reactions", "pinned", "pinnedAt"]) &&
      (!inL(get(R(c), "type", ""), SYSTEM_TYPES) || E.hasOnly(changedKeys(c), ["seen"])),
    delete: async (c) =>
      (await isMemberOf(c)) &&
      (await or(
        () => eq(R(c).senderId, me(c)),
        async () =>
          isTimestamp(get(R(c), "sentAt", null)) &&
          isTimestamp(get(await coupleData(c), "chatClearedAt", null)) &&
          ms(R(c).sentAt) <= ms((await coupleData(c)).chatClearedAt),
      )),
  },
];

// ---- Moods, daily questions, calls, memories, events, notes ------------------------

const shared: Rule[] = [
  {
    // Mood check-ins: one document per partner, and you own only your own.
    pattern: "couples/{coupleId}/moods/{userId}",
    read: (c) => isMemberOf(c),
    write: async (c) => (await isMemberOf(c)) && me(c) === c.params.userId,
  },
  {
    // Daily questions: one document per day holding both answers. Either
    // partner may create or merge into it; nobody may delete the record.
    pattern: "couples/{coupleId}/dailyQuestions/{dateKey}",
    read: (c) => isMemberOf(c),
    create: (c) => isMemberOf(c),
    update: (c) => isMemberOf(c),
    delete: () => false,
  },
  {
    // Call signalling. A single `current` document both partners read and
    // write: the caller sets it ringing, the callee accepts or declines, and
    // either may end it.
    pattern: "couples/{coupleId}/call/{callId}",
    read: (c) => isMemberOf(c),
    create: async (c) => (await isMemberOf(c)) && eq(D(c).callerId, me(c)),
    update: (c) => isMemberOf(c),
    delete: (c) => isMemberOf(c),
  },
  {
    // Memories: shared by both. Either partner may edit one, but it stays
    // credited to whoever added it, and only they can delete it.
    pattern: "couples/{coupleId}/memories/{memoryId}",
    read: (c) => isMemberOf(c),
    create: async (c) => (await isMemberOf(c)) && eq(D(c).createdBy, me(c)),
    update: async (c) => (await isMemberOf(c)) && eq(D(c).createdBy, R(c).createdBy),
    delete: async (c) => (await isMemberOf(c)) && eq(R(c).createdBy, me(c)),
  },
  {
    // Calendar events. A private event is visible only to its creator — the
    // app queries shared events and its own events separately, since rules are
    // not filters.
    pattern: "couples/{coupleId}/events/{eventId}",
    read: async (c) => (await isMemberOf(c)) && (await eventCanSee(c)),
    create: async (c) => (await isMemberOf(c)) && eq(D(c).createdBy, me(c)) && isBool(D(c).private),
    // Either partner may edit a shared event; only the creator may change who
    // can see it. The creator never changes.
    update: async (c) =>
      (await isMemberOf(c)) &&
      (await eventCanSee(c)) &&
      eq(D(c).createdBy, R(c).createdBy) &&
      (await or(
        () => eq(D(c).private, R(c).private),
        () => eq(R(c).createdBy, me(c)),
      )),
    delete: async (c) => (await isMemberOf(c)) && (await eventCanSee(c)),
  },
  {
    // Love notes. The envelope (sender, recipient, delivery time) is visible to
    // both, so a scheduled note can show "arrives in 3 days".
    pattern: "couples/{coupleId}/notes/{noteId}",
    read: (c) => isMemberOf(c),
    create: async (c) =>
      (await isMemberOf(c)) &&
      eq(D(c).senderId, me(c)) &&
      !eq(D(c).recipientId, me(c)) &&
      inL(D(c).recipientId, (await coupleData(c)).memberIds) &&
      D(c).openedAt === null,
    // The recipient marks it opened, once it has been delivered.
    update: async (c) =>
      (await isMemberOf(c)) &&
      eq(R(c).recipientId, me(c)) &&
      E.hasOnly(changedKeys(c), ["openedAt"]) &&
      now(c) >= ms(R(c).deliverAt),
    // The sender can unsend.
    delete: async (c) => (await isMemberOf(c)) && eq(R(c).senderId, me(c)),
  },
  {
    // The words: readable by the sender any time, and by the recipient only
    // from the delivery time. Written once, with the envelope.
    pattern: "couples/{coupleId}/notes/{noteId}/sealed/{docId}",
    get: async (c) =>
      (await isMemberOf(c)) &&
      (await or(
        () => eq(R(c).senderId, me(c)),
        () => eq(R(c).recipientId, me(c)) && now(c) >= ms(R(c).deliverAt),
      )),
    list: () => false,
    create: async (c) => {
      if (!((await isMemberOf(c)) && c.params.docId === "content")) return false;
      const note = await sealedNote(c);
      return (
        eq(note.senderId, me(c)) &&
        eq(D(c).senderId, me(c)) &&
        eq(D(c).recipientId, note.recipientId) &&
        eq(D(c).deliverAt, note.deliverAt)
      );
    },
    update: () => false,
    delete: async (c) => (await isMemberOf(c)) && eq(R(c).senderId, me(c)),
  },
];

async function eventCanSee(c: Ctx): Promise<boolean> {
  return or(
    () => eq(R(c).private, false),
    () => eq(R(c).createdBy, me(c)),
  );
}

/** getAfter(couples/$(coupleId)/notes/$(noteId)).data */
async function sealedNote(c: Ctx): Promise<V> {
  return strict(await E.getAfterData(c, `couples/${c.params.coupleId}/notes/${c.params.noteId}`));
}

// ---- Plans: date planner, bucket list, wishlist, places, expenses -------------
//
// Shared planning lists. Either partner may add and edit; an item stays
// credited to whoever added it. Field checks keep documents in the shape the
// app reads.

function str(c: Ctx, field: string, maxLen: number): boolean {
  return isStr(D(c)[field]) && size(D(c)[field]) <= maxLen;
}

function title(c: Ctx, field: string): boolean {
  return str(c, field, 120) && size(D(c)[field]) > 0;
}

function optStr(c: Ctx, field: string, maxLen: number): boolean {
  return !has(D(c), field) || D(c)[field] === null || str(c, field, maxLen);
}

function optInt(c: Ctx, field: string, minValue: number, maxValue: number): boolean {
  const d = D(c);
  return !has(d, field) || d[field] === null || (isInt(d[field]) && d[field] >= minValue && d[field] <= maxValue);
}

function optTimestamp(c: Ctx, field: string): boolean {
  const d = D(c);
  return !has(d, field) || d[field] === null || isTimestamp(d[field]);
}

// '' or an http(s) link.
function optUrl(c: Ctx, field: string): boolean {
  const d = D(c);
  return !has(d, field) || d[field] === null || d[field] === "" || (str(c, field, 2000) && matches(d[field], HTTP_S_RE));
}

async function isMember(c: Ctx, uid: V): Promise<boolean> {
  return inL(uid, (await coupleData(c)).memberIds);
}

const createdByMe = (c: Ctx): boolean => eq(D(c).createdBy, me(c));
const creatorUnchanged = (c: Ctx): boolean => eq(D(c).createdBy, R(c).createdBy);

function datePlanValid(c: Ctx): boolean {
  const d = D(c);
  return (
    title(c, "title") &&
    optStr(c, "notes", 2000) &&
    optStr(c, "location", 200) &&
    optStr(c, "reflection", 2000) &&
    inL(d.status, ["idea", "planned", "done"]) &&
    (!eq(d.status, "planned") || isTimestamp(d.scheduledAt)) &&
    optTimestamp(c, "scheduledAt") &&
    optTimestamp(c, "completedAt") &&
    optInt(c, "estimatedCostMinor", 0, 1000000000) &&
    optInt(c, "rating", 1, 5) &&
    (!has(d, "vibe") || inL(d.vibe, ["cozy", "adventure", "fancy", "outdoors", "food", "culture", "surprise"]))
  );
}

async function bucketValid(c: Ctx): Promise<boolean> {
  const d = D(c);
  return (
    title(c, "title") &&
    optStr(c, "notes", 2000) &&
    inL(d.category, ["travel", "adventure", "food", "learn", "home", "romance", "other"]) &&
    isBool(d.done) &&
    optTimestamp(c, "doneAt") &&
    (!has(d, "doneBy") || d.doneBy === null || (await isMember(c, d.doneBy))) &&
    optInt(c, "targetYear", 2000, 2200)
  );
}

function wishValid(c: Ctx): boolean {
  const d = D(c);
  return (
    title(c, "title") &&
    optStr(c, "notes", 1000) &&
    optUrl(c, "url") &&
    optInt(c, "priceMinor", 0, 1000000000) &&
    inL(d.priority, ["love", "like", "someday"]) &&
    (!has(d, "occasion") || inL(d.occasion, ["any", "birthday", "anniversary", "festival"])) &&
    (!has(d, "received") || isBool(d.received))
  );
}

function placeValid(c: Ctx): boolean {
  const d = D(c);
  return (
    title(c, "name") &&
    optStr(c, "area", 200) &&
    optUrl(c, "mapsUrl") &&
    optStr(c, "notes", 2000) &&
    inL(d.category, ["restaurant", "cafe", "bar", "outdoors", "travel", "shopping", "activity", "other"]) &&
    inL(d.status, ["wantToGo", "been"]) &&
    optInt(c, "rating", 1, 5) &&
    optTimestamp(c, "visitedAt") &&
    (!has(d, "favourite") || isBool(d.favourite))
  );
}

async function expenseValid(c: Ctx): Promise<boolean> {
  const d = D(c);
  return (
    inL(d.kind, ["expense", "settlement"]) &&
    title(c, "title") &&
    optStr(c, "note", 500) &&
    isInt(d.amountMinor) &&
    d.amountMinor > 0 &&
    d.amountMinor <= 1000000000 &&
    (await isMember(c, d.paidBy)) &&
    inL(d.split, ["equal", "full", "custom"]) &&
    (!eq(d.kind, "settlement") || eq(d.split, "full")) &&
    (!eq(d.split, "custom") || isMap(d.shares)) &&
    inL(d.category, ["food", "groceries", "travel", "home", "bills", "shopping", "fun", "gifts", "other"]) &&
    isTimestamp(d.spentOn)
  );
}

/** "I'll get this" claims: get(couples/$(coupleId)/wishlist/$(itemId)).data */
async function wish(c: Ctx): Promise<V> {
  return strict(await E.getData(c, `couples/${c.params.coupleId}/wishlist/${c.params.itemId}`));
}

const plans: Rule[] = [
  {
    pattern: "couples/{coupleId}/datePlans/{planId}",
    read: (c) => isMemberOf(c),
    create: async (c) => (await isMemberOf(c)) && createdByMe(c) && datePlanValid(c),
    update: async (c) => (await isMemberOf(c)) && creatorUnchanged(c) && datePlanValid(c),
    delete: (c) => isMemberOf(c),
  },
  {
    pattern: "couples/{coupleId}/bucketList/{itemId}",
    read: (c) => isMemberOf(c),
    create: async (c) => (await isMemberOf(c)) && createdByMe(c) && (await bucketValid(c)),
    update: async (c) => (await isMemberOf(c)) && creatorUnchanged(c) && (await bucketValid(c)),
    delete: (c) => isMemberOf(c),
  },
  {
    // Each wish belongs to the person who wants it; only they edit it.
    pattern: "couples/{coupleId}/wishlist/{itemId}",
    read: (c) => isMemberOf(c),
    create: async (c) => (await isMemberOf(c)) && createdByMe(c) && wishValid(c),
    update: async (c) =>
      (await isMemberOf(c)) && eq(R(c).createdBy, me(c)) && creatorUnchanged(c) && wishValid(c),
    delete: async (c) => (await isMemberOf(c)) && eq(R(c).createdBy, me(c)),
  },
  {
    // "I'll get this": a secret claim on the partner's wish. Only the claimer
    // can ever read it, so the surprise survives. The app lists claims with
    // where('claimedBy', '==', uid), which these rules require.
    pattern: "couples/{coupleId}/wishlistClaims/{itemId}",
    read: async (c) => (await isMemberOf(c)) && eq(R(c).claimedBy, me(c)),
    create: async (c) => {
      const d = D(c);
      return (
        (await isMemberOf(c)) &&
        eq(d.claimedBy, me(c)) &&
        eq(d.itemOwner, (await wish(c)).createdBy) &&
        !eq(d.itemOwner, me(c)) &&
        isBool(d.purchased) &&
        E.hasOnly(keys(d), ["claimedBy", "itemOwner", "claimedAt", "purchased"])
      );
    },
    update: async (c) =>
      (await isMemberOf(c)) &&
      eq(R(c).claimedBy, me(c)) &&
      E.hasOnly(changedKeys(c), ["purchased"]) &&
      isBool(D(c).purchased),
    delete: async (c) => (await isMemberOf(c)) && eq(R(c).claimedBy, me(c)),
  },
  {
    pattern: "couples/{coupleId}/places/{placeId}",
    read: (c) => isMemberOf(c),
    create: async (c) => (await isMemberOf(c)) && createdByMe(c) && placeValid(c),
    update: async (c) => (await isMemberOf(c)) && creatorUnchanged(c) && placeValid(c),
    delete: (c) => isMemberOf(c),
  },
  {
    // Shared expenses, in integer minor units (paise). Either partner may
    // correct an entry; only whoever added it may delete it.
    pattern: "couples/{coupleId}/expenses/{expenseId}",
    read: (c) => isMemberOf(c),
    create: async (c) => (await isMemberOf(c)) && createdByMe(c) && (await expenseValid(c)),
    update: async (c) => (await isMemberOf(c)) && creatorUnchanged(c) && (await expenseValid(c)),
    delete: async (c) => (await isMemberOf(c)) && eq(R(c).createdBy, me(c)),
  },
];

// ---- Device checks, gifts and Memory books ----------------------------------------

const premium: Rule[] = [
  {
    // A sign-in on a new phone waiting for the partner to confirm it's really
    // them (recycled-number protection). Only the OTHER partner decides, once.
    pattern: "couples/{coupleId}/deviceChecks/{checkId}",
    read: (c) => isMemberOf(c),
    create: async (c) => {
      const d = D(c);
      return (
        (await isMemberOf(c)) &&
        E.hasOnly(keys(d), ["uid", "deviceId", "deviceName", "createdAt", "status", "code"]) &&
        eq(d.uid, me(c)) &&
        isStr(d.deviceId) &&
        size(d.deviceId) <= 64 &&
        isStr(d.deviceName) &&
        size(d.deviceName) <= 60 &&
        isNow(c, d.createdAt) &&
        eq(d.status, "pending") &&
        isInt(d.code) &&
        d.code >= 10 &&
        d.code <= 99
      );
    },
    update: async (c) =>
      (await isMemberOf(c)) &&
      !eq(R(c).uid, me(c)) &&
      eq(R(c).status, "pending") &&
      E.hasOnly(changedKeys(c), ["status", "decidedBy", "decidedAt"]) &&
      inL(D(c).status, ["approved", "rejected"]) &&
      eq(D(c).decidedBy, me(c)) &&
      isNow(c, D(c).decidedAt),
    delete: async (c) => (await isMemberOf(c)) && eq(R(c).uid, me(c)),
  },
  {
    // Gifts are created by the server when it verifies a gift purchase. The
    // partner it's for marks it opened, once.
    pattern: "couples/{coupleId}/gifts/{giftId}",
    read: (c) => isMemberOf(c),
    create: () => false,
    delete: () => false,
    update: async (c) =>
      (await isMemberOf(c)) &&
      eq(R(c).toUid, me(c)) &&
      get(R(c), "openedAt", null) === null &&
      E.hasOnly(changedKeys(c), ["openedAt"]) &&
      isNow(c, D(c).openedAt),
  },
  {
    // A Memory book costs one credit: the same batch that creates it takes one
    // from the couple's bookCredits.
    pattern: "couples/{coupleId}/books/{bookId}",
    read: (c) => isMemberOf(c),
    create: async (c) => {
      const d = D(c);
      const { coupleId, bookId } = c.params;
      return (
        (await isMemberOf(c)) &&
        E.hasOnly(keys(d), ["createdBy", "title", "fromDate", "toDate", "pageCount", "storagePath", "createdAt"]) &&
        eq(d.createdBy, me(c)) &&
        isStr(d.title) &&
        size(d.title) > 0 &&
        size(d.title) <= 80 &&
        isTimestamp(d.fromDate) &&
        isTimestamp(d.toDate) &&
        ms(d.fromDate) <= ms(d.toDate) &&
        isInt(d.pageCount) &&
        d.pageCount > 0 &&
        d.pageCount <= 500 &&
        eq(d.storagePath, "couples/" + coupleId + "/books/" + bookId + ".pdf") &&
        isNow(c, d.createdAt) &&
        num(get(await coupleData(c), "bookCredits", 0)) >= 1 &&
        eq(get(await coupleAfter(c), "bookCredits", 0), num(get(await coupleData(c), "bookCredits", 0)) - 1)
      );
    },
    update: async (c) =>
      (await isMemberOf(c)) &&
      eq(R(c).createdBy, me(c)) &&
      E.hasOnly(changedKeys(c), ["title"]) &&
      isStr(D(c).title) &&
      size(D(c).title) > 0 &&
      size(D(c).title) <= 80,
    delete: (c) => isMemberOf(c),
  },
];

// ---- Vault: end-to-end encrypted private space -----------------------------------
// Everything readable is encrypted on the phones (see lib/features/vault). The
// server only ever sees ciphertext, device public keys and wrapped keys, so
// these rules check shape and membership; which phone may read the vault is
// decided by which devices hold a wrapped key, approved on a partner's phone.
// While a pairing is ending, the vault is closed for both: nothing can be read
// or added, and the server wipes it with everything else.
async function separating(c: Ctx): Promise<boolean> {
  return get(await coupleData(c), "separation", null) !== null;
}

/** Member of the couple and the vault is open (not separating). */
async function vaultOpen(c: Ctx): Promise<boolean> {
  return (await isMemberOf(c)) && !(await separating(c));
}

async function validVaultMeta(c: Ctx): Promise<boolean> {
  const d = D(c);
  return (
    c.params.docId === "meta" &&
    eq(d.version, 1) &&
    (await isMember(c, d.createdBy)) &&
    isMap(d.devices) &&
    size(d.devices) <= 8 &&
    isMap(d.keys) &&
    size(d.keys) <= 8 &&
    isStr(d.verifier) &&
    size(d.verifier) <= 4000 &&
    eq(d.updatedBy, me(c)) &&
    isNow(c, d.updatedAt)
  );
}

/**
 * `v.matches('^couples/' + coupleId + '/vault/[^/]+$')`, done without building
 * a regex from the id (a crafted id could make a backtracking regex hang).
 */
function isVaultFilePath(v: string, coupleId: string): boolean {
  const prefix = `couples/${coupleId}/vault/`;
  if (!v.startsWith(prefix)) return false;
  const rest = v.slice(prefix.length);
  return rest.length > 0 && !rest.includes("/") && !rest.includes("\n");
}

function vaultPath(c: Ctx, field: string): boolean {
  const v = get(D(c), field, null);
  return (
    v === null ||
    (isStr(v) && size(v) <= 200 && isVaultFilePath(v, c.params.coupleId))
  );
}

function validVaultItem(c: Ctx): boolean {
  const d = D(c);
  return (
    eq(d.senderId, me(c)) &&
    inL(d.kind, ["photo", "message"]) &&
    inL(d.shelf, ["a", "b"]) &&
    isStr(d.ct) &&
    size(d.ct) > 0 &&
    size(d.ct) <= 20000 &&
    vaultPath(c, "photoPath") &&
    vaultPath(c, "thumbPath") &&
    inL(d.policy, ["keep", "once", "day"]) &&
    (eq(d.policy, "day")
      ? isTimestamp(d.expiresAt) && ms(d.expiresAt) > now(c) && ms(d.expiresAt) < now(c) + 25 * 3_600_000
      : get(d, "expiresAt", null) === null) &&
    isMap(d.viewedBy) &&
    size(d.viewedBy) === 0 &&
    isNow(c, d.createdAt)
  );
}

const vault: Rule[] = [
  {
    pattern: "couples/{coupleId}/vault/{docId}",
    read: (c) => vaultOpen(c),
    create: async (c) => (await vaultOpen(c)) && (await validVaultMeta(c)) && eq(D(c).createdBy, me(c)),
    update: async (c) => (await vaultOpen(c)) && (await validVaultMeta(c)) && eq(D(c).createdBy, R(c).createdBy),
    // "Delete vault for both".
    delete: (c) => vaultOpen(c),
  },
  {
    pattern: "couples/{coupleId}/vaultItems/{itemId}",
    read: (c) => vaultOpen(c),
    create: async (c) => (await vaultOpen(c)) && validVaultItem(c),
    // The only change is marking it seen, and only for yourself.
    update: async (c) =>
      (await vaultOpen(c)) &&
      E.hasOnly(changedKeys(c), ["viewedBy"]) &&
      E.hasOnly(mapDiff(D(c).viewedBy, R(c).viewedBy), [me(c)]) &&
      isTimestamp(D(c).viewedBy[me(c)]),
    // Either partner may delete anything (view-once and expired items are
    // removed by whichever phone sees them first).
    delete: (c) => vaultOpen(c),
  },
  {
    pattern: "couples/{coupleId}/vaultEvents/{eventId}",
    read: (c) => vaultOpen(c),
    create: async (c) => {
      const d = D(c);
      return (
        (await vaultOpen(c)) &&
        eq(d.uid, me(c)) &&
        inL(d.type, ["wrongCode", "cooldown", "codeChanged", "deviceAdded", "deviceApproved", "wiped"]) &&
        isStr(d.deviceName) &&
        size(d.deviceName) <= 60 &&
        isNow(c, d.at)
      );
    },
    update: () => false,
    delete: (c) => vaultOpen(c),
  },
];

// ---- Music and Watch: saved links and shared sessions -----------------------------
// `songs` + `listening/now` (music) and `videos` + `watching/now` (YouTube
// watch-together) share one shape and one set of checks. Either partner may
// add, edit, love or delete an item. The link and who added it never change;
// plays only ever go up by one.

async function mediaValid(c: Ctx, sources: string[], kinds: string[]): Promise<boolean> {
  const d = D(c);
  return (
    isStr(d.url) &&
    size(d.url) <= 2000 &&
    matches(d.url, HTTPS_RE) &&
    inL(d.source, sources) &&
    inL(d.kind, kinds) &&
    isStr(d.mediaId) &&
    size(d.mediaId) <= 64 &&
    optStr(c, "title", 200) &&
    optStr(c, "artist", 200) &&
    optStr(c, "note", 500) &&
    optUrl(c, "thumbnailUrl") &&
    isStr(d.moment) &&
    size(d.moment) <= 32 &&
    (!has(d, "lovedBy") ||
      (isMap(d.lovedBy) && E.hasOnly(keys(d.lovedBy), asList((await coupleData(c)).memberIds)))) &&
    optInt(c, "playCount", 0, 1000000000) &&
    optTimestamp(c, "lastPlayedAt")
  );
}

async function mediaCreateOk(c: Ctx): Promise<boolean> {
  return (await isMemberOf(c)) && eq(D(c).addedBy, me(c)) && eq(get(D(c), "playCount", 0), 0);
}

async function mediaUpdateOk(c: Ctx): Promise<boolean> {
  const ck = changedKeys(c);
  return (
    (await isMemberOf(c)) &&
    !E.hasAny(ck, ["url", "source", "kind", "mediaId", "addedBy", "createdAt"]) &&
    (!ck.has("playCount") || eq(D(c).playCount, num(get(R(c), "playCount", 0)) + 1))
  );
}

// The one shared session (`listening/now` or `watching/now`). Every playback
// change bumps `version` by exactly one (the app does it in a transaction), so
// two phones can't silently overwrite each other. Checking in touches only
// your own entry in `listeners`.
async function sessionValid(c: Ctx, sources: string[]): Promise<boolean> {
  const d = D(c);
  return (
    isStr(d.songId) &&
    size(d.songId) > 0 &&
    size(d.songId) <= 64 &&
    isStr(d.url) &&
    size(d.url) <= 2000 &&
    matches(d.url, HTTPS_RE) &&
    inL(d.source, sources) &&
    isStr(d.mediaId) &&
    size(d.mediaId) <= 64 &&
    optStr(c, "title", 200) &&
    optStr(c, "artist", 200) &&
    optUrl(c, "thumbnailUrl") &&
    inL(d.status, ["countdown", "playing", "paused", "ended"]) &&
    isInt(d.positionMs) &&
    d.positionMs >= 0 &&
    isInt(d.at) &&
    isList(d.queue) &&
    size(d.queue) <= 50 &&
    inL(d.hostUid, (await coupleData(c)).memberIds) &&
    isMap(d.listeners) &&
    E.hasOnly(keys(d.listeners), asList((await coupleData(c)).memberIds)) &&
    isInt(d.version)
  );
}

// Who changed playback, when (server time), and the next version.
function playbackChange(c: Ctx, previousVersion: V): boolean {
  return eq(D(c).updatedBy, me(c)) && isNow(c, D(c).updatedAt) && eq(D(c).version, num(previousVersion) + 1);
}

function checkInOnly(c: Ctx): boolean {
  return E.hasOnly(changedKeys(c), ["listeners"]) && E.hasOnly(mapDiff(D(c).listeners, R(c).listeners), [me(c)]);
}

// `<sessions>/clock-{uid}` lets a phone measure server time.
function clockWriteOk(c: Ctx, docId: string): boolean {
  return docId === "clock-" + me(c) && E.hasOnly(keys(D(c)), ["t"]) && isNow(c, D(c).t);
}

const ALL_SOURCES = ["spotify", "youtube", "youtubeMusic", "appleMusic", "jioSaavn", "soundCloud", "other"];
const YOUTUBE_SOURCES = ["youtube", "youtubeMusic"];

async function songValid(c: Ctx): Promise<boolean> {
  return (
    (await mediaValid(c, ALL_SOURCES, ["track", "video", "album", "playlist", "other"])) &&
    inL(D(c).moment, ["ourSong", "romantic", "missYou", "happy", "sad", "roadTrip", "dance", "chill", "other"])
  );
}

// Videos to watch together: YouTube only, single videos only, so both phones
// can play them in the app.
async function videoValid(c: Ctx): Promise<boolean> {
  return (
    (await mediaValid(c, YOUTUBE_SOURCES, ["video"])) &&
    size(D(c).mediaId) > 0 &&
    inL(D(c).moment, ["movieNight", "funny", "romantic", "food", "travel", "music", "learn", "other"])
  );
}

/** listening/{docId} and watching/{docId} share their rules; `youtube` adds the watch checks. */
function sessionRule(pattern: string, youtube: boolean): Rule {
  const sources = youtube ? YOUTUBE_SOURCES : ALL_SOURCES;
  const nowValid = async (c: Ctx) => (await sessionValid(c, sources)) && (!youtube || size(D(c).mediaId) > 0);
  return {
    pattern,
    read: async (c) =>
      (await isMemberOf(c)) && (c.params.docId === "now" || c.params.docId === "clock-" + me(c)),
    create: async (c) =>
      (await isMemberOf(c)) &&
      (await or(
        async () => c.params.docId === "now" && (await nowValid(c)) && playbackChange(c, 0),
        () => clockWriteOk(c, c.params.docId),
      )),
    update: async (c) =>
      (await isMemberOf(c)) &&
      (await or(
        async () =>
          c.params.docId === "now" &&
          (await nowValid(c)) &&
          (await or(
            () => checkInOnly(c),
            () => playbackChange(c, R(c).version),
          )),
        () => clockWriteOk(c, c.params.docId),
      )),
    delete: () => false,
  };
}

function validLook(c: Ctx): boolean {
  const d = D(c);
  const bg = () => d.background;
  return (
    c.params.docId === "chatLook" &&
    (d.color === null || isInt(d.color)) &&
    isMap(bg()) &&
    inL(bg().kind, ["none", "pattern", "photo"]) &&
    isNumber(get(bg(), "dim", 0)) &&
    get(bg(), "dim", 0) >= 0 &&
    get(bg(), "dim", 0) <= 0.7 &&
    isNumber(get(bg(), "blur", 0)) &&
    get(bg(), "blur", 0) >= 0 &&
    get(bg(), "blur", 0) <= 12 &&
    (get(bg(), "photoUrl", null) === null ||
      (isStr(bg().photoUrl) && matches(bg().photoUrl, HTTPS_RE) && size(bg().photoUrl) <= 2000)) &&
    eq(d.updatedBy, me(c))
  );
}

const media: Rule[] = [
  {
    pattern: "couples/{coupleId}/songs/{songId}",
    read: (c) => isMemberOf(c),
    create: async (c) => (await mediaCreateOk(c)) && (await songValid(c)),
    update: async (c) => (await mediaUpdateOk(c)) && (await songValid(c)),
    delete: (c) => isMemberOf(c),
  },
  {
    pattern: "couples/{coupleId}/videos/{videoId}",
    read: (c) => isMemberOf(c),
    create: async (c) => (await mediaCreateOk(c)) && (await videoValid(c)),
    update: async (c) => (await mediaUpdateOk(c)) && (await videoValid(c)),
    delete: (c) => isMemberOf(c),
  },
  sessionRule("couples/{coupleId}/listening/{docId}", false),
  sessionRule("couples/{coupleId}/watching/{docId}", true),
  {
    // Chat look: colour and background both partners see. Only
    // `settings/chatLook` exists today. Either partner may change it.
    pattern: "couples/{coupleId}/settings/{docId}",
    read: (c) => isMemberOf(c),
    create: async (c) => (await isMemberOf(c)) && validLook(c),
    update: async (c) => (await isMemberOf(c)) && validLook(c),
    delete: () => false,
  },
];

// ---- Play: games between the two partners -----------------------------------------
//
// One document per game. `turn` names whoever must act next, and only they may
// change an active game; `moveCount` must go up by exactly one per write, so
// two phones can't both apply a move. Finished and cancelled games are frozen.

function fixedKeysUnchanged(c: Ctx): boolean {
  const d = D(c);
  const r = R(c);
  return (
    eq(d.type, r.type) &&
    eq(d.createdBy, r.createdBy) &&
    eq(d.invitee, r.invitee) &&
    eq(d.players, r.players) &&
    eq(d.createdAt, r.createdAt)
  );
}

// In the quiz, the guesses can't change once locked in, and the person being
// guessed about never changes.
function quizIntact(c: Ctx): boolean {
  const d = D(c);
  const r = R(c);
  return (
    !eq(r.type, "knowMe") ||
    ((!has(r.state, "subject") || eq(get(d.state, "subject", null), r.state.subject)) &&
      (!eq(get(r.state, "guessesLocked", false), true) ||
        (eq(get(d.state, "guessesLocked", false), true) && eq(get(d.state, "guesses", null), r.state.guesses))))
  );
}

function cancelling(c: Ctx): boolean {
  const d = D(c);
  return (
    eq(d.status, "cancelled") && d.turn === null && E.hasOnly(changedKeys(c), ["status", "turn", "moveCount", "updatedAt"])
  );
}

function accepting(c: Ctx): boolean {
  const d = D(c);
  const r = R(c);
  return (
    eq(r.status, "invited") && eq(d.status, "active") && eq(me(c), r.invitee) && inL(d.turn, r.players) && d.winner === null
  );
}

function takingTurn(c: Ctx): boolean {
  const d = D(c);
  const r = R(c);
  return (
    eq(r.status, "active") &&
    eq(me(c), r.turn) &&
    ((eq(d.status, "active") && inL(d.turn, r.players) && d.winner === null) ||
      (eq(d.status, "finished") &&
        d.turn === null &&
        (d.winner === null || eq(d.winner, "draw") || inL(d.winner, r.players))))
  );
}

/** get(couples/$(coupleId)/games/$(gameId)).data */
async function game(c: Ctx): Promise<V> {
  return strict(await E.getData(c, `couples/${c.params.coupleId}/games/${c.params.gameId}`));
}

const games: Rule[] = [
  {
    pattern: "couples/{coupleId}/games/{gameId}",
    read: (c) => isMemberOf(c),
    create: async (c) => {
      const d = D(c);
      return (
        (await isMemberOf(c)) &&
        inL(d.type, ["knowMe", "truthOrDare", "ticTacToe", "connectFour", "ludo", "snakesLadders"]) &&
        eq(d.createdBy, me(c)) &&
        !eq(d.invitee, me(c)) &&
        (await isMember(c, d.invitee)) &&
        eq(d.players, [me(c), raw(d.invitee)]) &&
        eq(d.status, "invited") &&
        d.turn === null &&
        d.winner === null &&
        eq(d.moveCount, 0) &&
        isMap(d.state)
      );
    },
    update: async (c) =>
      (await isMemberOf(c)) &&
      inL(R(c).status, ["invited", "active"]) &&
      fixedKeysUnchanged(c) &&
      eq(D(c).moveCount, num(R(c).moveCount) + 1) &&
      isMap(D(c).state) &&
      quizIntact(c) &&
      (await or(
        () => cancelling(c),
        () => accepting(c),
        () => takingTurn(c),
      )),
    delete: () => false,
  },
  {
    // Quiz answers about yourself. Written once by the person being guessed
    // about, in the same batch that hands the turn over. The guesser can read
    // them only after locking in their guesses.
    pattern: "couples/{coupleId}/games/{gameId}/secret/{docId}",
    get: async (c) =>
      (await isMemberOf(c)) &&
      (await or(
        () => eq(R(c).subject, me(c)),
        async () => eq(get((await game(c)).state, "guessesLocked", false), true),
        async () => eq((await game(c)).status, "finished"),
      )),
    list: () => false,
    create: async (c) => {
      if (!((await isMemberOf(c)) && c.params.docId === "answers")) return false;
      const g = await game(c);
      return (
        eq(g.type, "knowMe") &&
        eq(g.status, "active") &&
        eq(g.turn, me(c)) &&
        eq(get(g.state, "subject", null), me(c)) &&
        eq(D(c).subject, me(c)) &&
        isList(D(c).answers)
      );
    },
    update: () => false,
    delete: () => false,
  },
  {
    // Thinking-of-you buzzes. Append-only.
    pattern: "couples/{coupleId}/nudges/{nudgeId}",
    read: (c) => isMemberOf(c),
    create: async (c) => (await isMemberOf(c)) && eq(D(c).senderId, me(c)),
    update: () => false,
    delete: () => false,
  },
];

// ---- WebRTC call setup (new; replaces Agora) ----------------------------------------

const SIGNAL_KINDS = ["offer", "answer", "candidates"];

const callSignals: Rule[] = [
  {
    // Connection details the two phones swap to set up a call: one offer,
    // one answer, and batches of network candidates. Written once, never
    // edited; either partner may clear them when a new call starts.
    pattern: "couples/{coupleId}/callSignals/{signalId}",
    read: (c) => isMemberOf(c),
    create: async (c) => {
      const d = E.newData(c);
      return (
        (await isMemberOf(c)) &&
        E.hasOnly(Object.keys(d), ["from", "to", "callId", "kind", "payload", "createdAt"]) &&
        d.from === me(c) &&
        typeof d.to === "string" &&
        d.to !== me(c) &&
        inL(d.to, (await coupleData(c)).memberIds) &&
        typeof d.callId === "string" && d.callId.length > 0 && d.callId.length <= 64 &&
        SIGNAL_KINDS.includes(d.kind as string) &&
        typeof d.payload === "string" && d.payload.length <= 64_000 &&
        E.isRequestTime(c, d.createdAt)
      );
    },
    update: () => false,
    delete: (c) => isMemberOf(c),
  },
];

// ---- Push notification tokens (new; not in the old firestore.rules) ---------------

const pushTokens: Rule[] = [
  {
    // One document per phone: its FCM token and time zone. Only the owner
    // reads or writes them; the server reads them to send notifications.
    pattern: "users/{userId}/pushTokens/{tokenId}",
    read: (c) => signedIn(c) && me(c) === c.params.userId,
    create: (c) => signedIn(c) && me(c) === c.params.userId && pushTokenOk(c),
    update: (c) => signedIn(c) && me(c) === c.params.userId && pushTokenOk(c),
    delete: (c) => signedIn(c) && me(c) === c.params.userId,
  },
];

function pushTokenOk(c: Ctx): boolean {
  const d = E.newData(c);
  return (
    E.hasOnly(Object.keys(d), ["token", "platform", "timeZone", "updatedAt"]) &&
    typeof d.token === "string" && d.token.length > 0 && d.token.length <= 4096 &&
    (d.platform === "android" || d.platform === "ios") &&
    (d.timeZone === null || d.timeZone === undefined || (typeof d.timeZone === "string" && d.timeZone.length <= 64)) &&
    E.isRequestTime(c, d.updatedAt)
  );
}

export const firestoreRules: Rule[] = [
  ...pushTokens,
  ...callSignals,
  ...users,
  ...pairing,
  ...invites,
  ...couples,
  ...messages,
  ...shared,
  ...plans,
  ...premium,
  ...vault,
  ...media,
  ...games,
];
