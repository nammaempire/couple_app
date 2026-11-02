/**
 * Daily database backups, kept in the bucket next to the app's files.
 *
 *   backups/db/<UTC time>.jsonl.gz       (or .jsonl.gz.enc when encrypted)
 *
 * A backup is one consistent snapshot of every table (a read-only
 * REPEATABLE READ transaction): a header line, then one line per row,
 * `{"t": table, "r": row}`, gzip-compressed and, when BACKUP_ENCRYPTION_KEY
 * is set, encrypted with AES-256-GCM. Rows are written with to_jsonb() and
 * read back with jsonb_populate_record(), so every column round-trips.
 *
 * The scheduler checks every hour and makes a backup when the newest one is
 * more than a day old, so it runs about once a day and catches up after a
 * restart. Backups older than BACKUP_RETENTION_DAYS (at most 30, as the
 * privacy policy promises) are deleted. Users can never reach backups: the
 * storage rules deny every path outside the app's own folders.
 *
 * Files (photos, videos…) are not copied; the bucket keeps them itself.
 * Restore with scripts/restore-backup.ts (see server/README.md).
 */
import { createCipheriv, createDecipheriv, randomBytes, scryptSync } from "node:crypto";
import { createReadStream, createWriteStream } from "node:fs";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { once } from "node:events";
import { PassThrough } from "node:stream";
import { pipeline } from "node:stream/promises";
import { createGzip, gunzipSync } from "node:zlib";
import { config } from "../config.js";
import { pool, tx, type Client } from "../db.js";
import { getBucket, type Bucket } from "../files.js";
import { quoteIdent as q } from "../schema.js";
import { logger } from "../functions/log.js";

export const BACKUP_PREFIX = "backups/db/";
export const BACKUP_FORMAT = "us-backup";
export const BACKUP_VERSION = 1;
/** Make a new backup once the newest is older than this. */
export const BACKUP_EVERY_MS = 24 * 60 * 60 * 1000 - 30 * 60 * 1000;
/** /health/backup reports a problem once the newest backup is older than this. */
export const BACKUP_STALE_MS = 36 * 60 * 60 * 1000;
/** pg_try_advisory_lock key, so only one instance backs up at a time. */
export const BACKUP_LOCK_KEY = 727276;

const MAGIC = Buffer.from("USBK1");
const FETCH = 500;

export interface BackupInfo {
  key: string;
  size: number;
  /** When the backup was made (from its name). */
  at: Date;
  encrypted: boolean;
}

export interface BackupResult extends BackupInfo {
  tables: Record<string, number>;
  deletedOld: number;
}

// ---- Naming ----------------------------------------------------------------

/** backups/db/2026-11-02T21-30-00Z.jsonl.gz(.enc) */
export function backupKey(at: Date, encrypted: boolean): string {
  const stamp = at.toISOString().replace(/\.\d{3}Z$/, "Z").replace(/:/g, "-");
  return `${BACKUP_PREFIX}${stamp}.jsonl.gz${encrypted ? ".enc" : ""}`;
}

export function parseBackupKey(key: string): Date | null {
  const m = /^backups\/db\/(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})Z\.jsonl\.gz(\.enc)?$/.exec(key);
  if (!m) return null;
  const d = new Date(`${m[1]}T${m[2]}:${m[3]}:${m[4]}Z`);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** Every backup in the bucket, oldest first. */
export async function listBackups(bucket: Bucket = getBucket()): Promise<BackupInfo[]> {
  const out: BackupInfo[] = [];
  for (const o of await bucket.list(BACKUP_PREFIX)) {
    const at = parseBackupKey(o.key);
    if (at) out.push({ key: o.key, size: o.size, at, encrypted: o.key.endsWith(".enc") });
  }
  return out.sort((a, b) => a.at.getTime() - b.at.getTime());
}

// ---- Encryption --------------------------------------------------------------

function keyFrom(passphrase: string, salt: Buffer): Buffer {
  return scryptSync(passphrase, salt, 32);
}

/** MAGIC | salt(16) | iv(12) | ciphertext | tag(16) */
export function decryptBackup(data: Buffer, passphrase: string): Buffer {
  if (!data.subarray(0, MAGIC.length).equals(MAGIC)) throw new Error("Not an encrypted Us backup.");
  const salt = data.subarray(5, 21);
  const iv = data.subarray(21, 33);
  const tag = data.subarray(data.length - 16);
  const body = data.subarray(33, data.length - 16);
  const d = createDecipheriv("aes-256-gcm", keyFrom(passphrase, salt), iv);
  d.setAuthTag(tag);
  try {
    return Buffer.concat([d.update(body), d.final()]);
  } catch {
    throw new Error("Wrong BACKUP_ENCRYPTION_KEY, or the backup is damaged.");
  }
}

// ---- Making a backup -------------------------------------------------------

/** Every table in the database's public schema. */
async function tableNames(c: Client): Promise<string[]> {
  const r = await c.query<{ name: string }>(
    `SELECT table_name AS name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name`,
  );
  return r.rows.map((x) => x.name);
}

/**
 * Writes the snapshot to [file] (gzip, then encrypted when a key is set).
 * Returns rows per table.
 */
async function writeSnapshot(file: string, at: Date, passphrase: string): Promise<Record<string, number>> {
  const counts: Record<string, number> = {};
  const lines = new PassThrough();
  // Waits when the compressor falls behind, so a big table never fills memory.
  const put = async (line: string) => {
    if (!lines.write(line)) await once(lines, "drain");
  };
  const gzip = createGzip({ level: 6 });
  const out = createWriteStream(file);

  let tag: Buffer | null = null;
  const done = passphrase
    ? (() => {
        const salt = randomBytes(16);
        const iv = randomBytes(12);
        const cipher = createCipheriv("aes-256-gcm", keyFrom(passphrase, salt), iv);
        out.write(Buffer.concat([MAGIC, salt, iv]));
        return pipeline(lines, gzip, cipher, out).then(() => {
          tag = cipher.getAuthTag();
        });
      })()
    : pipeline(lines, gzip, out);

  try {
    const c = await pool.connect();
    try {
      await c.query("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY");
      const tables = await tableNames(c);
      await put(JSON.stringify({ format: BACKUP_FORMAT, version: BACKUP_VERSION, createdAt: at.toISOString(), tables }) + "\n");
      for (const t of tables) {
        counts[t] = 0;
        await c.query(`DECLARE dump NO SCROLL CURSOR FOR SELECT to_jsonb(x) AS r FROM ${q(t)} x`);
        for (;;) {
          const r = await c.query<{ r: unknown }>(`FETCH ${FETCH} FROM dump`);
          for (const row of r.rows) await put(JSON.stringify({ t, r: row.r }) + "\n");
          counts[t] += r.rows.length;
          if (r.rows.length < FETCH) break;
        }
        await c.query("CLOSE dump");
      }
      await c.query("COMMIT");
    } catch (e) {
      await c.query("ROLLBACK").catch(() => {});
      throw e;
    } finally {
      c.release();
    }
    lines.end();
  } catch (e) {
    lines.destroy(e as Error);
    await done.catch(() => {});
    throw e;
  }
  await done;
  if (tag) {
    // The authentication tag goes at the end of the file.
    await new Promise<void>((resolve, reject) => {
      const a = createWriteStream(file, { flags: "a" });
      a.on("error", reject);
      a.end(tag, () => resolve());
    });
  }
  return counts;
}

/** Makes a backup now, uploads it, and deletes ones past the retention. */
export async function runBackup(opts: { now?: Date; bucket?: Bucket; passphrase?: string; retentionDays?: number } = {}): Promise<BackupResult> {
  const at = opts.now ?? new Date();
  const bucket = opts.bucket ?? getBucket();
  const passphrase = opts.passphrase ?? config.backups.encryptionKey;
  const encrypted = passphrase.length > 0;
  const key = backupKey(at, encrypted);

  const dir = await mkdtemp(join(tmpdir(), "us-backup-"));
  const file = join(dir, "backup");
  try {
    const tables = await writeSnapshot(file, at, passphrase);
    const { size } = await stat(file);
    await bucket.put(key, createReadStream(file), size, encrypted ? "application/octet-stream" : "application/gzip", {
      format: BACKUP_FORMAT,
      version: String(BACKUP_VERSION),
    });
    const deletedOld = await pruneBackups(bucket, at, opts.retentionDays ?? config.backups.retentionDays);
    logger.info("backup: done", { key, size, rows: Object.values(tables).reduce((a, b) => a + b, 0), deletedOld });
    return { key, size, at, encrypted, tables, deletedOld };
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

/** Deletes backups older than [days] (never the newest one). */
export async function pruneBackups(bucket: Bucket, now: Date, days: number): Promise<number> {
  const all = await listBackups(bucket);
  const cutoff = now.getTime() - days * 24 * 60 * 60 * 1000;
  let n = 0;
  for (const b of all.slice(0, -1)) {
    if (b.at.getTime() < cutoff) {
      await bucket.delete(b.key);
      n++;
    }
  }
  return n;
}

// ---- Reading and restoring ---------------------------------------------------

export interface BackupContents {
  header: { format: string; version: number; createdAt: string; tables: string[] };
  rows: Map<string, unknown[]>;
}

/** Decrypts (when needed), unzips and parses a backup file. */
export function readBackup(data: Buffer, passphrase = ""): BackupContents {
  const encrypted = data.subarray(0, MAGIC.length).equals(MAGIC);
  if (encrypted && !passphrase) throw new Error("This backup is encrypted: set BACKUP_ENCRYPTION_KEY.");
  const text = gunzipSync(encrypted ? decryptBackup(data, passphrase) : data).toString("utf8");
  const lines = text.split("\n").filter((l) => l.length > 0);
  const header = JSON.parse(lines[0] ?? "{}");
  if (header.format !== BACKUP_FORMAT) throw new Error("Not a Us backup.");
  if (header.version !== BACKUP_VERSION) throw new Error(`Unsupported backup version ${header.version}.`);
  const rows = new Map<string, unknown[]>();
  for (const t of header.tables as string[]) rows.set(t, []);
  for (const l of lines.slice(1)) {
    const { t, r } = JSON.parse(l) as { t: string; r: unknown };
    rows.get(t)?.push(r);
  }
  return { header, rows };
}

export interface RestoreResult {
  tables: Record<string, number>;
  skippedTables: string[];
}

/**
 * Restores [contents] into the database the server is connected to. The
 * tables must exist (run migrate first) and, unless [replace], be empty.
 * With [replace], every table in the backup is emptied first. All in one
 * transaction: on any error nothing changes.
 */
export async function restoreBackup(contents: BackupContents, opts: { replace?: boolean } = {}): Promise<RestoreResult> {
  return tx(async (c) => {
    const existing = new Set(await tableNames(c));
    const tables: Record<string, number> = {};
    const skippedTables: string[] = [];
    const present = contents.header.tables.filter((t) => {
      if (existing.has(t)) return true;
      skippedTables.push(t);
      return false;
    });
    if (opts.replace) {
      if (present.length) await c.query(`TRUNCATE ${present.map(q).join(", ")}`);
    } else {
      for (const t of present) {
        const r = await c.query<{ n: number }>(`SELECT count(*)::int AS n FROM ${q(t)}`);
        if ((r.rows[0]?.n ?? 0) > 0) {
          throw new Error(`Table ${t} isn't empty. Restore into an empty database, or pass --replace.`);
        }
      }
    }
    for (const t of present) {
      const rows = contents.rows.get(t) ?? [];
      tables[t] = rows.length;
      for (let i = 0; i < rows.length; i += FETCH) {
        const batch = rows.slice(i, i + FETCH);
        await c.query(
          `INSERT INTO ${q(t)} SELECT * FROM jsonb_populate_recordset(NULL::${q(t)}, $1::jsonb)`,
          [JSON.stringify(batch)],
        );
      }
    }
    return { tables, skippedTables };
  }, 1);
}

// ---- Schedule and status ---------------------------------------------------

let lastError: { at: Date; message: string } | null = null;

/** Runs a backup if the newest one is due, with the advisory lock. */
export async function runBackupTick(now = new Date()): Promise<BackupResult | null> {
  const c = await pool.connect();
  let locked = false;
  try {
    const r = await c.query<{ ok: boolean }>("SELECT pg_try_advisory_lock($1) AS ok", [BACKUP_LOCK_KEY]);
    locked = r.rows[0]?.ok === true;
    if (!locked) return null;
    const newest = (await listBackups()).at(-1);
    if (newest && now.getTime() - newest.at.getTime() < BACKUP_EVERY_MS) return null;
    const result = await runBackup({ now });
    lastError = null;
    return result;
  } catch (e) {
    lastError = { at: now, message: String(e) };
    logger.error("backup: failed", { error: String(e) });
    return null;
  } finally {
    if (locked) await c.query("SELECT pg_advisory_unlock($1)", [BACKUP_LOCK_KEY]).catch(() => {});
    c.release();
  }
}

/** What /health/backup reports. */
export async function backupHealth(now = new Date()): Promise<{
  ok: boolean;
  enabled: boolean;
  latestAt: string | null;
  ageHours: number | null;
  count: number;
  encrypted: boolean | null;
  /** When the last attempt failed (details are in the server log). */
  lastFailedAt: string | null;
}> {
  if (!config.backups.enabled) {
    return { ok: true, enabled: false, latestAt: null, ageHours: null, count: 0, encrypted: null, lastFailedAt: null };
  }
  const all = await listBackups();
  const newest = all.at(-1);
  const age = newest ? now.getTime() - newest.at.getTime() : null;
  return {
    ok: age !== null && age < BACKUP_STALE_MS,
    enabled: true,
    latestAt: newest ? newest.at.toISOString() : null,
    ageHours: age === null ? null : Math.round((age / 3_600_000) * 10) / 10,
    count: all.length,
    encrypted: newest ? newest.encrypted : null,
    lastFailedAt: lastError ? lastError.at.toISOString() : null,
  };
}

/** Hourly check; returns a stop function. */
export function startBackups(intervalMs = 60 * 60 * 1000, firstDelayMs = 2 * 60 * 1000): () => Promise<void> {
  let current: Promise<unknown> | null = null;
  let stopped = false;
  const tick = () => {
    if (current || stopped) return;
    current = runBackupTick().finally(() => {
      current = null;
    });
  };
  const timer = setInterval(tick, intervalMs);
  const first = setTimeout(tick, firstDelayMs);
  timer.unref?.();
  first.unref?.();
  return async () => {
    stopped = true;
    clearInterval(timer);
    clearTimeout(first);
    await current;
  };
}
