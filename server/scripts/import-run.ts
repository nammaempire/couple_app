/**
 * The import itself: walks a FirestoreSource into Postgres and copies a
 * StorageSource into a Bucket. Firebase access is injected (see
 * import-from-firebase.ts for the real one, test/import-*.test.ts for fakes).
 *
 * Re-running is safe: documents are upserted (a row changed in the new
 * backend after its Firestore update time is left alone), and files already
 * in the target bucket with the same size are skipped.
 */
import { pool, tx, type Client } from "../src/db.js";
import type { Bucket } from "../src/files.js";
import { migrate } from "../src/migrate.js";
import { PathError, quoteIdent as q, resolveDoc, type ResolvedDoc } from "../src/schema.js";
import { notifyChanged } from "../src/store.js";
import { sanitize, type Data } from "../src/values.js";
import {
  convertDoc,
  convertMetadata,
  isoOf,
  mapLimit,
  newSummary,
  serverAcceptsPath,
  skipDoc,
  type ConvertCtx,
  type FirestoreSource,
  type ImportOptions,
  type SourceDoc,
  type StorageSource,
  type Summary,
} from "./import-lib.js";

export interface RunDeps {
  firestore?: FirestoreSource;
  storage?: StorageSource;
  /** Target bucket. Not needed for a dry run (then nothing is checked there). */
  target?: Bucket;
  /** Firebase Storage bucket name, e.g. "my-app.firebasestorage.app". */
  sourceBucket: string;
  /** The deployed server's downloadUrl(path). */
  toUrl: (path: string) => string;
  log?: (line: string) => void;
}

interface Row {
  r: ResolvedDoc;
  data: Data;
  createTime: string;
  updateTime: string;
}

const SUBCOLLECTION_PROBES = 16;
const ROWS_PER_INSERT = 250;

export async function runImport(opts: ImportOptions, deps: RunDeps): Promise<Summary> {
  const s = newSummary(opts.dryRun);
  const log = deps.log ?? ((l: string) => console.log(l));
  const vlog = (l: string) => opts.verbose && log(l);
  const warn = (m: string) => {
    s.warnings.push(m);
    vlog(`  warning: ${m}`);
  };
  const rewrittenPaths = new Set<string>();
  const sourceFiles = new Set<string>();

  try {
    if (opts.only !== "storage") {
      if (!deps.firestore) throw new Error("No Firestore source.");
      if (!opts.dryRun) await migrate();
      await importFirestore(opts, deps, deps.firestore, s, log, vlog, warn, rewrittenPaths);
    }
    if (opts.only !== "firestore") {
      if (!deps.storage) throw new Error("No Storage source.");
      if (!opts.dryRun && !deps.target) throw new Error("No target bucket.");
      await copyStorage(opts, deps, deps.storage, s, log, vlog, warn, sourceFiles);
    }
    if (opts.only === "all") {
      s.linksToMissingFiles = [...rewrittenPaths].filter((p) => !sourceFiles.has(p)).sort();
    }
  } catch (e) {
    s.fatal = e instanceof Error ? e.message : String(e);
  }
  return s;
}

// ---- Firestore ---------------------------------------------------------------------------

async function importFirestore(
  opts: ImportOptions,
  deps: RunDeps,
  fs: FirestoreSource,
  s: Summary,
  log: (l: string) => void,
  vlog: (l: string) => void,
  warn: (m: string) => void,
  rewrittenPaths: Set<string>,
): Promise<void> {
  const ctx: ConvertCtx = {
    sourceBucket: deps.sourceBucket,
    toUrl: deps.toUrl,
    warn,
    onRewrite: (p) => {
      s.urlsRewritten++;
      rewrittenPaths.add(p);
    },
    onForeignUrl: (u) => {
      s.foreignUrls++;
      warn(`link to another bucket left unchanged: ${u.slice(0, 160)}`);
    },
  };

  let roots = (await fs.rootCollections()).sort();
  if (opts.collections.length) {
    const missing = opts.collections.filter((c) => !roots.includes(c));
    if (missing.length) warn(`--collection: no root collection named ${missing.join(", ")}`);
    roots = roots.filter((c) => opts.collections.includes(c));
  }
  log(`Firestore: root collections ${roots.join(", ") || "(none)"}`);

  let lastProgress = 0;
  const progress = () => {
    if (s.docsRead - lastProgress >= 500) {
      lastProgress = s.docsRead;
      log(`  … ${s.docsRead} documents read`);
    }
  };

  const walk = async (colPath: string): Promise<void> => {
    vlog(`collection ${colPath}`);
    for await (const page of fs.documents(colPath)) {
      const rows: Row[] = [];
      for (const d of page) {
        s.docsRead++;
        const row = prepare(d, ctx, s, warn);
        if (row) rows.push(row);
      }
      await writeRows(rows, opts, s, vlog);
      progress();

      // Subcollections can hang off any document, even a missing one.
      const subs: string[] = [];
      await mapLimit(page, SUBCOLLECTION_PROBES, async (d) => {
        for (const id of await fs.subcollections(d.path)) subs.push(`${d.path}/${id}`);
      });
      for (const sub of subs.sort()) await walk(sub);
    }
  };
  for (const root of roots) await walk(root);
}

function prepare(d: SourceDoc, ctx: ConvertCtx, s: Summary, warn: (m: string) => void): Row | null {
  if (!d.exists) {
    s.missingParents++;
    return null;
  }
  let r: ResolvedDoc;
  try {
    r = resolveDoc(d.path);
  } catch (e) {
    if (!(e instanceof PathError)) throw e;
    skipDoc(s, d.path, /Unknown document path/.test(e.message) ? "not used by the new backend" : e.message);
    return null;
  }
  const data = convertDoc(d.data ?? {}, ctx, d.path);
  try {
    sanitize(data, false);
  } catch (e) {
    warn(`${d.path}: ${(e as Error).message} — document skipped`);
    skipDoc(s, d.path, "value the new backend can't store");
    return null;
  }
  const update = d.updateTime ?? d.createTime ?? new Date();
  const create = d.createTime ?? update;
  return { r, data, createTime: isoOf(create), updateTime: isoOf(update) };
}

async function writeRows(rows: Row[], opts: ImportOptions, s: Summary, vlog: (l: string) => void): Promise<void> {
  if (!rows.length) return;
  const byTable = new Map<string, Row[]>();
  for (const row of rows) {
    const t = row.r.def.table;
    if (!byTable.has(t)) byTable.set(t, []);
    byTable.get(t)!.push(row);
    s.tables[t] ??= { inserted: 0, updated: 0, unchanged: 0 };
  }
  if (opts.dryRun) {
    for (const [t, rs] of byTable) {
      s.tables[t].inserted += rs.length;
      for (const row of rs) vlog(`  would write ${row.r.path} → ${t}`);
    }
    return;
  }
  await tx(async (c) => {
    const changed: string[] = [];
    for (const [t, rs] of byTable) {
      for (let i = 0; i < rs.length; i += ROWS_PER_INSERT) {
        const chunk = rs.slice(i, i + ROWS_PER_INSERT);
        const res = await upsert(c, chunk);
        const counts = s.tables[t];
        counts.unchanged += chunk.length - res.length;
        for (const r of res) {
          if (r.inserted) counts.inserted++;
          else counts.updated++;
          changed.push(r.path);
          vlog(`  ${r.inserted ? "new" : "updated"} ${r.path}`);
        }
      }
    }
    // Lets connected app clients see the change, if the server is running.
    await notifyChanged(c, changed);
  });
}

/** Upserts rows of one table. Returns the rows that were inserted or changed. */
async function upsert(c: Client, rows: Row[]): Promise<{ path: string; inserted: boolean }[]> {
  const d = rows[0].r.def;
  const keys = [...d.parentCols, "id"];
  const cols = [...keys, "data", "create_time", "update_time"];
  const params: unknown[] = [];
  const values = rows.map((row) => {
    const vals = [...row.r.parentIds, row.r.id, JSON.stringify(row.data), row.createTime, row.updateTime];
    const ph = vals.map((v, j) => {
      params.push(v);
      const n = `$${params.length}`;
      return j === keys.length ? `${n}::jsonb` : j > keys.length ? `${n}::timestamptz` : n;
    });
    return `(${ph.join(", ")})`;
  });
  const t = q(d.table);
  const sql = `
    INSERT INTO ${t} AS t (${cols.map(q).join(", ")})
    VALUES ${values.join(",\n")}
    ON CONFLICT (${keys.map(q).join(", ")}) DO UPDATE
      SET data = EXCLUDED.data,
          create_time = EXCLUDED.create_time,
          update_time = EXCLUDED.update_time,
          version = nextval('doc_version_seq')
      WHERE t.update_time < EXCLUDED.update_time
         OR (t.update_time = EXCLUDED.update_time
             AND (t.data IS DISTINCT FROM EXCLUDED.data OR t.create_time IS DISTINCT FROM EXCLUDED.create_time))
    RETURNING ${keys.map((k) => `t.${q(k)}`).join(", ")}, (xmax = 0) AS inserted`;
  const res = await c.query(sql, params);
  const byKey = new Map(rows.map((row) => [[...row.r.parentIds, row.r.id].join("\u0000"), row.r.path]));
  return res.rows.map((r: Record<string, unknown>) => ({
    path: byKey.get(keys.map((k) => String(r[k])).join("\u0000")) ?? "?",
    inserted: r.inserted === true,
  }));
}

// ---- Storage --------------------------------------------------------------------------------

async function copyStorage(
  opts: ImportOptions,
  deps: RunDeps,
  src: StorageSource,
  s: Summary,
  log: (l: string) => void,
  vlog: (l: string) => void,
  warn: (m: string) => void,
  sourceFiles: Set<string>,
): Promise<void> {
  log(`Storage: copying gs://${deps.sourceBucket} → target bucket`);
  const target = deps.target;
  let lastProgress = 0;
  for await (const page of src.list()) {
    await mapLimit(page, opts.concurrency, async (o) => {
      s.files.listed++;
      sourceFiles.add(o.name);
      if (o.name.endsWith("/")) {
        // A console-made "folder" placeholder; buckets don't need them.
        s.files.skipped++;
        return;
      }
      if (!serverAcceptsPath(o.name)) {
        warn(`${o.name}: name has characters the server's upload/delete API refuses (download links still work)`);
      }
      const existing = target ? await target.head(o.name) : null;
      if (existing && existing.size === o.size) {
        s.files.skipped++;
        vlog(`  already there ${o.name}`);
        return;
      }
      const contentType = o.contentType || "application/octet-stream";
      const meta = convertMetadata(o.metadata, warn, o.name);
      if (opts.dryRun) {
        s.files.copied++;
        s.files.bytes += o.size;
        vlog(`  would copy ${o.name} (${o.size} bytes)`);
        return;
      }
      for (let attempt = 1; ; attempt++) {
        try {
          await target!.put(o.name, src.open(o.name), o.size, contentType, meta);
          s.files.copied++;
          s.files.bytes += o.size;
          vlog(`  copied ${o.name} (${o.size} bytes)`);
          break;
        } catch (e) {
          if (attempt < 3) {
            vlog(`  retrying ${o.name}: ${(e as Error).message}`);
            await new Promise((r) => setTimeout(r, 1000 * attempt));
            continue;
          }
          s.files.failed++;
          warn(`${o.name}: copy failed: ${(e as Error).message}`);
          break;
        }
      }
    });
    if (s.files.listed - lastProgress >= 200) {
      lastProgress = s.files.listed;
      log(`  … ${s.files.listed} files checked, ${s.files.copied} copied`);
    }
  }
}

export { pool };
