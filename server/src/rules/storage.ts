/**
 * File rules, ported from storage.rules. Same model as Firebase Storage rules:
 * an operation is allowed when any matching allow-function returns true.
 */
import type { AuthInfo, DocLike } from "./engine.js";

export interface ObjectMeta {
  name: string;
  /** Bytes. */
  size: number;
  contentType: string;
  /** Custom metadata (keys lower-cased). */
  metadata: Record<string, string>;
  updated: string;
}

export interface StorageRuleContext {
  auth: AuthInfo | null;
  time: string;
  params: Record<string, string>;
  path: string;
  /** The stored file (null when it doesn't exist). */
  resource: ObjectMeta | null;
  /** For uploads: the incoming file. */
  request: { resource: ObjectMeta | null };
  /** firestore.get()/exists() — reads documents (pre-request state). */
  firestore: { get(path: string): Promise<DocLike | null>; exists(path: string): Promise<boolean> };
}

export type StorageAllow = (c: StorageRuleContext) => boolean | Promise<boolean>;

export interface StorageRule {
  pattern: string;
  read?: StorageAllow;
  write?: StorageAllow;
  create?: StorageAllow;
  update?: StorageAllow;
  delete?: StorageAllow;
}

// ---- Helpers mirroring the functions in storage.rules ---------------------------

const MB = 1024 * 1024;

/** request.resource (throws on delete/read, which denies like a rules error). */
function incoming(c: StorageRuleContext): ObjectMeta {
  if (!c.request.resource) throw new Error("no request.resource");
  return c.request.resource;
}

/** resource (throws when the file doesn't exist). */
function stored(c: StorageRuleContext): ObjectMeta {
  if (!c.resource) throw new Error("no resource");
  return c.resource;
}

/**
 * Custom metadata value. Firebase kept key case (rules read `senderId`); this
 * server lower-cases keys on upload (S3 does too), so look them up
 * case-insensitively.
 */
function meta(m: ObjectMeta, key: string): string | undefined {
  const k = key.toLowerCase();
  if (Object.prototype.hasOwnProperty.call(m.metadata, k)) return m.metadata[k];
  for (const [mk, v] of Object.entries(m.metadata)) if (mk.toLowerCase() === k) return v;
  return undefined;
}

/** contentType.matches(re): RE2 full match. */
function typeMatches(m: ObjectMeta, re: RegExp): boolean {
  return typeof m.contentType === "string" && re.test(m.contentType);
}
const IMAGE = /^image\/.*$/;
const VIDEO = /^video\/.*$/;
const AUDIO = /^audio\/.*$/;

/** isMemberOf(coupleId) */
async function isMemberOf(c: StorageRuleContext, coupleId: unknown): Promise<boolean> {
  if (c.auth === null) return false;
  if (typeof coupleId !== "string" || coupleId.length === 0) throw new Error("bad coupleId");
  const couple = await c.firestore.get(`couples/${coupleId}`);
  if (!couple) throw new Error("missing couple");
  const members = couple.data.memberIds;
  if (!Array.isArray(members)) throw new Error("memberIds is not a list");
  return members.includes(c.auth.uid);
}

/** isPartnerOf(userId): the signed-in user shares a couple with userId. */
async function isPartnerOf(c: StorageRuleContext, userId: string): Promise<boolean> {
  if (c.auth === null) return false;
  const user = await c.firestore.get(`users/${userId}`);
  if (!user) throw new Error("missing user");
  return isMemberOf(c, user.data.coupleId);
}

/** isImageUnder(megabytes) */
function isImageUnder(c: StorageRuleContext, megabytes: number): boolean {
  const r = incoming(c);
  return r.size < megabytes * MB && typeMatches(r, IMAGE);
}

const member = (c: StorageRuleContext) => isMemberOf(c, c.params.coupleId);
const isOwner = (c: StorageRuleContext) => c.auth !== null && c.auth.uid === c.params.userId;

const CP = "couples/{coupleId}";

export const storageRules: StorageRule[] = [
  {
    pattern: `${CP}/photos/{photoId}`,
    read: member,
    write: async (c) => (await member(c)) && isImageUnder(c, 15),
    delete: member,
  },
  // Chat videos. The app limits them to 3 minutes; 100 MB is the hard cap.
  {
    pattern: `${CP}/videos/{videoId}`,
    read: member,
    write: async (c) => (await member(c)) && incoming(c).size < 100 * MB && typeMatches(incoming(c), VIDEO),
    delete: member,
  },
  // Voice messages (AAC in .m4a, recorded for up to 5 minutes).
  {
    pattern: `${CP}/voice/{voiceId}`,
    read: member,
    write: async (c) => (await member(c)) && incoming(c).size < 10 * MB && typeMatches(incoming(c), AUDIO),
    delete: member,
  },
  // Memory photos, video thumbnails and videos.
  {
    pattern: `${CP}/memories/{fileId}`,
    read: member,
    create: memoryUpload,
    update: memoryUpload,
    delete: member,
  },
  // Voice love letters. Only the sender may read the file directly; the
  // recipient plays it through the link kept in the sealed note.
  {
    pattern: `${CP}/notes/{fileId}`,
    read: async (c) => (await member(c)) && meta(stored(c), "senderId") === c.auth!.uid,
    create: async (c) =>
      (await member(c)) &&
      meta(incoming(c), "senderId") === c.auth!.uid &&
      incoming(c).size < 10 * MB &&
      typeMatches(incoming(c), AUDIO),
    delete: async (c) => (await member(c)) && meta(stored(c), "senderId") === c.auth!.uid,
  },
  // Shared couple picture, set during onboarding or later.
  {
    pattern: `${CP}/profile/{photoId}`,
    read: member,
    write: async (c) => (await member(c)) && isImageUnder(c, 10),
    delete: member,
  },
  // Chat background photos both partners see.
  {
    pattern: `${CP}/backgrounds/{fileId}`,
    read: member,
    create: async (c) => (await member(c)) && isImageUnder(c, 10),
    delete: member,
  },
  // Memory books: PDFs made on a phone, shared with the partner.
  {
    pattern: `${CP}/books/{fileId}`,
    read: member,
    delete: member,
    create: async (c) => (await member(c)) && incoming(c).size < 50 * MB && incoming(c).contentType === "application/pdf",
  },
  // Vault files: encrypted on the phone; the server only stores opaque bytes.
  {
    pattern: `${CP}/vault/{fileId}`,
    read: member,
    create: async (c) =>
      (await member(c)) && incoming(c).size < 15 * MB && incoming(c).contentType === "application/octet-stream",
    delete: member,
  },
  // A personal chat background: only its owner ever sees it.
  {
    pattern: "users/{userId}/backgrounds/{fileId}",
    read: isOwner,
    delete: isOwner,
    create: (c) => isOwner(c) && isImageUnder(c, 10),
  },
  // A user's own profile picture. Their partner can see it too.
  {
    pattern: "users/{userId}/profile/{photoId}",
    read: async (c) => c.auth !== null && (isOwner(c) || (await isPartnerOf(c, c.params.userId))),
    write: (c) => isOwner(c) && isImageUnder(c, 10),
    delete: isOwner,
  },
  // Everything else: denied (match /{allPaths=**} { allow read, write: if false; }).
];

async function memoryUpload(c: StorageRuleContext): Promise<boolean> {
  if (!(await member(c))) return false;
  const r = incoming(c);
  return r.size < 100 * MB && (typeMatches(r, IMAGE) || typeMatches(r, VIDEO));
}
