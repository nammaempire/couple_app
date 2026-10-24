/**
 * Files in the S3-compatible bucket (Railway Bucket), with storage rules.
 *
 *   PUT    /v1/files/<path>        upload (body = bytes; Content-Type, Content-Length;
 *                                  optional x-file-metadata: base64url JSON of custom metadata)
 *   POST   /v1/files/url {path}    a download URL for an existing file
 *   DELETE /v1/files/<path>        delete
 *   GET    /f/<path>?t=<sig>       download link (redirects to a short-lived bucket URL)
 *
 * Object keys are the same paths the app used in Firebase Storage
 * (e.g. couples/{coupleId}/photos/{id}.jpg).
 */
import { createHmac, timingSafeEqual } from "node:crypto";
import { PassThrough, Transform } from "node:stream";
import { pipeline } from "node:stream/promises";
import type { Readable } from "node:stream";
import {
  DeleteObjectCommand,
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  S3Client,
} from "@aws-sdk/client-s3";
import { Upload } from "@aws-sdk/lib-storage";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { bearer, verifyToken } from "./auth.js";
import { config } from "./config.js";
import { pool } from "./db.js";
import { ApiError } from "./errors.js";
import { adminGet } from "./store.js";
import { storageRules, type ObjectMeta, type StorageRuleContext } from "./rules/storage.js";
import type { AuthInfo, DocLike } from "./rules/engine.js";

// ---- Bucket access (swappable for tests) -------------------------------------------

export interface Bucket {
  head(key: string): Promise<ObjectMeta | null>;
  put(key: string, body: Readable, size: number, contentType: string, metadata: Record<string, string>): Promise<void>;
  delete(key: string): Promise<void>;
  deletePrefix(prefix: string): Promise<number>;
  signedGetUrl(key: string, seconds: number): Promise<string>;
  /**
   * Buckets that can't hand out a URL of their own (the in-memory one used
   * for tests and local runs) return the bytes here, and /f/ serves them.
   */
  read?(key: string): Promise<{ meta: ObjectMeta; bytes: Buffer } | null>;
}

class S3Bucket implements Bucket {
  private s3 = new S3Client({
    endpoint: config.s3.endpoint || undefined,
    region: config.s3.region,
    forcePathStyle: config.s3.forcePathStyle,
    credentials: { accessKeyId: config.s3.accessKeyId, secretAccessKey: config.s3.secretAccessKey },
  });
  private b = config.s3.bucket;

  async head(key: string): Promise<ObjectMeta | null> {
    try {
      const r = await this.s3.send(new HeadObjectCommand({ Bucket: this.b, Key: key }));
      return {
        name: key,
        size: r.ContentLength ?? 0,
        contentType: r.ContentType ?? "application/octet-stream",
        metadata: r.Metadata ?? {},
        updated: (r.LastModified ?? new Date()).toISOString(),
      };
    } catch (e) {
      const status = (e as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode;
      if (status === 404) return null;
      throw e;
    }
  }

  async put(key: string, body: Readable, size: number, contentType: string, metadata: Record<string, string>): Promise<void> {
    const up = new Upload({
      client: this.s3,
      params: { Bucket: this.b, Key: key, Body: body, ContentType: contentType, Metadata: metadata, ContentLength: size },
      queueSize: 3,
      partSize: 8 * 1024 * 1024,
    });
    await up.done();
  }

  async delete(key: string): Promise<void> {
    await this.s3.send(new DeleteObjectCommand({ Bucket: this.b, Key: key }));
  }

  async deletePrefix(prefix: string): Promise<number> {
    let token: string | undefined;
    let n = 0;
    do {
      const list = await this.s3.send(new ListObjectsV2Command({ Bucket: this.b, Prefix: prefix, ContinuationToken: token }));
      const keys = (list.Contents ?? []).map((o) => ({ Key: o.Key! }));
      if (keys.length) {
        await this.s3.send(new DeleteObjectsCommand({ Bucket: this.b, Delete: { Objects: keys, Quiet: true } }));
        n += keys.length;
      }
      token = list.IsTruncated ? list.NextContinuationToken : undefined;
    } while (token);
    return n;
  }

  signedGetUrl(key: string, seconds: number): Promise<string> {
    return getSignedUrl(this.s3, new GetObjectCommand({ Bucket: this.b, Key: key }), { expiresIn: seconds });
  }
}

/** In-memory bucket for tests and local runs without S3 settings. */
export class MemoryBucket implements Bucket {
  objects = new Map<string, { meta: ObjectMeta; bytes: Buffer }>();
  async head(key: string) {
    return this.objects.get(key)?.meta ?? null;
  }
  async put(key: string, body: Readable, size: number, contentType: string, metadata: Record<string, string>) {
    const chunks: Buffer[] = [];
    for await (const c of body) chunks.push(Buffer.from(c as Buffer));
    const bytes = Buffer.concat(chunks);
    this.objects.set(key, { meta: { name: key, size: bytes.length, contentType, metadata, updated: new Date().toISOString() }, bytes });
  }
  async delete(key: string) {
    this.objects.delete(key);
  }
  async deletePrefix(prefix: string) {
    let n = 0;
    for (const k of [...this.objects.keys()]) if (k.startsWith(prefix)) {
      this.objects.delete(k);
      n++;
    }
    return n;
  }
  async signedGetUrl(key: string) {
    return `memory://${key}`;
  }
  async read(key: string) {
    return this.objects.get(key) ?? null;
  }
}

let bucket: Bucket = config.s3.bucket ? new S3Bucket() : new MemoryBucket();
export function setBucket(b: Bucket): void {
  bucket = b;
}
export function getBucket(): Bucket {
  return bucket;
}

// ---- Download links -------------------------------------------------------------------

function sign(path: string): string {
  return createHmac("sha256", config.fileUrlSecret).update(path).digest("base64url").slice(0, 32);
}

export function downloadUrl(path: string): string {
  const enc = path.split("/").map(encodeURIComponent).join("/");
  return `${config.publicUrl}/f/${enc}?t=${sign(path)}`;
}

/** The storage path inside one of our download URLs, or null. */
export function pathFromUrl(url: string): string | null {
  try {
    const u = new URL(url);
    const m = /^\/f\/(.+)$/.exec(u.pathname);
    if (!m) return null;
    return m[1].split("/").map(decodeURIComponent).join("/");
  } catch {
    return null;
  }
}

// ---- Rules --------------------------------------------------------------------------------

const PATH_RE = /^[A-Za-z0-9_\-+.@=]+(\/[A-Za-z0-9_\-+.@=]+){1,8}$/;

function checkPath(path: string): string {
  const p = path.replace(/^\/+/, "");
  if (!PATH_RE.test(p) || p.split("/").some((s) => s === "." || s === "..")) {
    throw new ApiError("invalid-argument", "Bad file path.");
  }
  return p;
}

function matchStorage(pattern: string, path: string): Record<string, string> | null {
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

type StorageOp = "read" | "create" | "update" | "delete";

async function storageAllowed(
  auth: AuthInfo | null,
  op: StorageOp,
  path: string,
  resource: ObjectMeta | null,
  incoming: ObjectMeta | null,
): Promise<boolean> {
  const time = new Date().toISOString();
  const cache = new Map<string, DocLike | null>();
  const fsGet = async (p: string) => {
    if (!cache.has(p)) {
      const d = await adminGet(pool, p);
      cache.set(p, d.exists ? { id: d.id, data: d.data! } : null);
    }
    return cache.get(p)!;
  };
  for (const rule of storageRules) {
    const params = matchStorage(rule.pattern, path);
    if (!params) continue;
    const ctx: StorageRuleContext = {
      auth,
      time,
      params,
      path,
      resource,
      request: { resource: incoming },
      firestore: { get: fsGet, exists: async (p) => (await fsGet(p)) !== null },
    };
    const fns = [rule[op], op === "read" ? undefined : rule.write].filter((f): f is NonNullable<typeof f> => !!f);
    for (const fn of fns) {
      try {
        if (await fn(ctx)) return true;
      } catch {
        /* deny */
      }
    }
  }
  return false;
}

async function authOf(req: FastifyRequest): Promise<AuthInfo> {
  return verifyToken(bearer(req.headers.authorization));
}

function decodeMetadata(h: unknown): Record<string, string> {
  if (typeof h !== "string" || !h) return {};
  try {
    const obj = JSON.parse(Buffer.from(h, "base64url").toString("utf8")) as Record<string, unknown>;
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(obj)) {
      if (!/^[a-zA-Z0-9_-]{1,64}$/.test(k)) throw new Error();
      out[k.toLowerCase()] = String(v).slice(0, 1024);
    }
    return out;
  } catch {
    throw new ApiError("invalid-argument", "Bad x-file-metadata header.");
  }
}

/** Counts bytes and fails if more than [max] arrive. */
function limiter(max: number): Transform {
  let seen = 0;
  return new Transform({
    transform(chunk: Buffer, _enc, cb) {
      seen += chunk.length;
      if (seen > max) cb(new ApiError("invalid-argument", "File is larger than declared."));
      else cb(null, chunk);
    },
    flush(cb) {
      if (seen !== max) cb(new ApiError("invalid-argument", "File is smaller than declared."));
      else cb();
    },
  });
}

export async function registerFiles(app: FastifyInstance): Promise<void> {
  await app.register(async (scope) => {
    scope.removeAllContentTypeParsers();
    scope.addContentTypeParser("*", (_req, payload, done) => done(null, payload));

    scope.put("/v1/files/*", async (req, reply) => {
      const auth = await authOf(req);
      const path = checkPath((req.params as { "*": string })["*"]);
      const size = Number(req.headers["content-length"]);
      if (!Number.isInteger(size) || size < 0) throw new ApiError("invalid-argument", "Content-Length is required.");
      const contentType = String(req.headers["content-type"] ?? "application/octet-stream").split(";")[0].trim();
      const metadata = decodeMetadata(req.headers["x-file-metadata"]);
      const existing = await bucket.head(path);
      const incoming: ObjectMeta = { name: path, size, contentType, metadata, updated: new Date().toISOString() };
      if (!(await storageAllowed(auth, existing ? "update" : "create", path, existing, incoming))) {
        // Drain the body so the client sees the error instead of a reset.
        (req.body as Readable).resume();
        throw new ApiError("permission-denied", "You can't upload this file.");
      }
      const body = new PassThrough();
      const done = bucket.put(path, body, size, contentType, metadata);
      await Promise.all([pipeline(req.body as Readable, limiter(size), body), done]);
      return reply.send({ path, size, contentType, metadata, downloadUrl: downloadUrl(path) });
    });
  });

  app.post("/v1/files/url", async (req) => {
    const auth = await authOf(req);
    const path = checkPath(String((req.body as { path?: unknown })?.path ?? ""));
    const meta = await bucket.head(path);
    if (!(await storageAllowed(auth, "read", path, meta, null))) throw new ApiError("permission-denied", "You can't open this file.");
    if (!meta) throw new ApiError("not-found", "No such file.");
    return { path, downloadUrl: downloadUrl(path), size: meta.size, contentType: meta.contentType, metadata: meta.metadata };
  });

  app.delete("/v1/files/*", async (req) => {
    const auth = await authOf(req);
    const path = checkPath((req.params as { "*": string })["*"]);
    const meta = await bucket.head(path);
    // Rules first (resource == null when missing), so "not found" is only
    // ever told to someone allowed to delete there.
    if (!(await storageAllowed(auth, "delete", path, meta, null))) throw new ApiError("permission-denied", "You can't delete this file.");
    if (!meta) throw new ApiError("not-found", "No such file.");
    await bucket.delete(path);
    return { ok: true };
  });

  // Download links: the signature proves the server handed this URL out.
  app.get("/f/*", async (req, reply) => {
    const raw = (req.params as { "*": string })["*"];
    const path = raw.split("/").map((s) => decodeURIComponent(s)).join("/");
    const t = String((req.query as { t?: string }).t ?? "");
    const want = sign(path);
    if (t.length !== want.length || !timingSafeEqual(Buffer.from(t), Buffer.from(want))) {
      throw new ApiError("permission-denied", "Invalid link.");
    }
    if (bucket.read) {
      const obj = await bucket.read(path);
      if (!obj) throw new ApiError("not-found", "No such file.");
      return reply
        .header("Cache-Control", "private, max-age=3000")
        .header("Content-Type", obj.meta.contentType)
        .send(obj.bytes);
    }
    const url = await bucket.signedGetUrl(path, 3600);
    return reply.header("Cache-Control", "private, max-age=3000").redirect(url, 302);
  });
}
