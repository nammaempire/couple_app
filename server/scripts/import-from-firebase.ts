/**
 * One-time import: copies the app's Firestore documents and Firebase Storage
 * files into the new backend (Postgres + S3-compatible bucket).
 *
 *   npm run import-firebase -- --dry-run
 *   npm run import-firebase
 *
 * Step-by-step instructions: scripts/README-import.md.
 *
 * Source: firebase-admin with a service-account key
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json   or   FIREBASE_SERVICE_ACCOUNT_JSON='{…}'
 *   FIREBASE_PROJECT_ID (default: the key's project), FIREBASE_STORAGE_BUCKET
 *   (default: <project>.firebasestorage.app)
 * Target: the same variables the server uses — DATABASE_URL (DATABASE_SSL),
 *   S3_*, and PUBLIC_URL + FILE_URL_SECRET exactly as deployed, so the
 *   rewritten file links validate.
 */
import { readFileSync } from "node:fs";
import { loadEnvFile } from "node:process";
import type { Readable } from "node:stream";
import { ArgError, USAGE, formatSummary, parseArgs, type FirestoreSource, type SourceDoc, type StorageSource } from "./import-lib.js";

const DEV_SECRET = "dev-only-file-url-secret-change-me";

function env(name: string): string {
  return (process.env[name] ?? "").trim();
}

interface Key {
  json: Record<string, string>;
  from: string;
}

function loadKey(): Key {
  const inline = env("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (inline) {
    const text = inline.startsWith("{") ? inline : Buffer.from(inline, "base64").toString("utf8");
    try {
      return { json: JSON.parse(text), from: "FIREBASE_SERVICE_ACCOUNT_JSON" };
    } catch {
      throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON (paste the whole key file, or its base64).");
    }
  }
  const file = env("GOOGLE_APPLICATION_CREDENTIALS");
  if (file) {
    try {
      return { json: JSON.parse(readFileSync(file, "utf8")), from: file };
    } catch (e) {
      throw new Error(`Can't read the service-account key at GOOGLE_APPLICATION_CREDENTIALS=${file}: ${(e as Error).message}`);
    }
  }
  throw new Error("No Firebase key. Set GOOGLE_APPLICATION_CREDENTIALS to the key file's path (see README-import.md).");
}

function redactDbUrl(u: string): string {
  try {
    const x = new URL(u);
    if (x.password) x.password = "****";
    return x.toString();
  } catch {
    return "(unparsable DATABASE_URL)";
  }
}

/** Checks the target settings. Problems are fatal for a real run, warnings for a dry run. */
function checkTarget(only: string, dryRun: boolean): string[] {
  const problems: string[] = [];
  if (only !== "storage" && !env("DATABASE_URL")) problems.push("DATABASE_URL is not set (copy it from Railway → Postgres → Connect → public URL).");
  if (only !== "storage") {
    const pub = env("PUBLIC_URL");
    if (!pub) problems.push("PUBLIC_URL is not set (use exactly the server's PUBLIC_URL, e.g. https://api.example.com).");
    else if (/localhost|127\.0\.0\.1/.test(pub)) problems.push(`PUBLIC_URL is ${pub}; the app can't open links to localhost.`);
    const secret = env("FILE_URL_SECRET");
    if (!secret || secret === DEV_SECRET) problems.push("FILE_URL_SECRET is not set (use exactly the server's value, or file links won't open).");
  }
  if (only !== "firestore" && !dryRun) {
    for (const k of ["S3_BUCKET", "S3_ACCESS_KEY_ID", "S3_SECRET_ACCESS_KEY"]) if (!env(k)) problems.push(`${k} is not set (Railway → Bucket → Credentials).`);
  }
  return problems;
}

async function main(): Promise<number> {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (e) {
    if (e instanceof ArgError) {
      console.error(e.message);
      return 1;
    }
    throw e;
  }
  if (opts.help) {
    console.log(USAGE);
    return 0;
  }
  if (opts.envFile) loadEnvFile(opts.envFile);

  const problems = checkTarget(opts.only, opts.dryRun);
  if (problems.length && !opts.dryRun) {
    console.error("Can't start:\n" + problems.map((p) => "  - " + p).join("\n"));
    return 1;
  }

  const key = loadKey();
  const projectId = key.json.project_id || env("FIREBASE_PROJECT_ID");
  if (!projectId) throw new Error("Can't tell the Firebase project: the key has no project_id; set FIREBASE_PROJECT_ID.");
  if (env("FIREBASE_PROJECT_ID") && key.json.project_id && env("FIREBASE_PROJECT_ID") !== key.json.project_id) {
    console.warn(`Note: FIREBASE_PROJECT_ID=${env("FIREBASE_PROJECT_ID")} differs from the key's project ${key.json.project_id}; using the key's.`);
  }
  const sourceBucket = env("FIREBASE_STORAGE_BUCKET").replace(/^gs:\/\//, "") || `${projectId}.firebasestorage.app`;

  // Imported only now, so --env-file values reach the server's config.
  const { initializeApp, cert } = await import("firebase-admin/app");
  const { getFirestore } = await import("firebase-admin/firestore");
  const { getStorage } = await import("firebase-admin/storage");
  const { downloadUrl, getBucket } = await import("../src/files.js");
  const { runImport, pool } = await import("./import-run.js");

  const app = initializeApp({ credential: cert(key.json as never), projectId, storageBucket: sourceBucket }, "firebase-import");

  console.log(`Firebase import${opts.dryRun ? " — DRY RUN, nothing will be written" : ""}`);
  console.log(`  from project   ${projectId} (key: ${key.from})`);
  console.log(`  from bucket    gs://${sourceBucket}`);
  if (opts.only !== "storage") console.log(`  to database    ${redactDbUrl(env("DATABASE_URL"))}`);
  if (opts.only !== "firestore") console.log(`  to bucket      ${env("S3_BUCKET") || "(not set)"} at ${env("S3_ENDPOINT") || "(default AWS endpoint)"}`);
  if (opts.only !== "storage") console.log(`  file links     ${env("PUBLIC_URL") || "(not set)"}/f/…`);
  for (const p of problems) console.warn(`  warning: ${p}`);
  console.log("");

  let firestore: FirestoreSource | undefined;
  let storage: StorageSource | undefined;

  if (opts.only !== "storage") {
    const db = getFirestore(app);
    firestore = {
      async rootCollections() {
        return (await db.listCollections()).map((c) => c.id);
      },
      async subcollections(docPath) {
        return (await db.doc(docPath).listCollections()).map((c) => c.id);
      },
      async *documents(colPath) {
        // listDocuments also returns "missing" parents that only hold subcollections.
        const refs = await db.collection(colPath).listDocuments();
        for (let i = 0; i < refs.length; i += 300) {
          const snaps = await db.getAll(...refs.slice(i, i + 300));
          yield snaps.map(
            (s): SourceDoc => ({
              path: s.ref.path,
              exists: s.exists,
              data: s.exists ? s.data() : undefined,
              createTime: s.createTime?.toDate(),
              updateTime: s.updateTime?.toDate(),
            }),
          );
        }
      },
    };
  }

  if (opts.only !== "firestore") {
    const bucket = getStorage(app).bucket(sourceBucket);
    const [exists] = await bucket.exists();
    if (!exists) {
      throw new Error(
        `Firebase bucket gs://${sourceBucket} not found. Set FIREBASE_STORAGE_BUCKET to the name shown in ` +
          `Firebase console → Storage (older projects use ${projectId}.appspot.com).`,
      );
    }
    storage = {
      async *list() {
        let pageToken: string | undefined;
        do {
          const [files, next] = await bucket.getFiles({ autoPaginate: false, maxResults: 500, pageToken });
          yield files.map((f) => ({
            name: f.name,
            size: Number(f.metadata.size ?? 0),
            contentType: f.metadata.contentType,
            metadata: (f.metadata.metadata ?? {}) as Record<string, unknown>,
          }));
          pageToken = (next as { pageToken?: string } | null)?.pageToken;
        } while (pageToken);
      },
      open(name): Readable {
        return bucket.file(name).createReadStream();
      },
    };
  } else if (env("FIREBASE_STORAGE_BUCKET") === "") {
    console.log(`(Links are rewritten for gs://${sourceBucket}; set FIREBASE_STORAGE_BUCKET if your bucket has another name.)`);
  }

  const started = Date.now();
  const summary = await runImport(opts, {
    firestore,
    storage,
    target: opts.dryRun && !env("S3_BUCKET") ? undefined : getBucket(),
    sourceBucket,
    toUrl: downloadUrl,
  });
  console.log(formatSummary(summary));
  console.log(`Took ${Math.round((Date.now() - started) / 1000)} s.`);
  await pool.end().catch(() => {});
  if (summary.fatal) return 1;
  if (summary.files.failed) {
    console.log("Some files failed to copy; run the same command again to retry them.");
    return 2;
  }
  return 0;
}

main().then(
  (code) => process.exit(code),
  (e) => {
    console.error(`\nSTOPPED: ${e instanceof Error ? e.message : String(e)}`);
    if (process.env.DEBUG) console.error(e);
    process.exit(1);
  },
);
