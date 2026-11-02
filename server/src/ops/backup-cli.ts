/**
 * Database backups by hand (the server also makes one every day).
 *
 * On Railway, open a shell in the running server (`railway ssh` in server/,
 * or the service's ⋮ → SSH) and run, with its settings already in place:
 *
 *   node dist/ops/backup-cli.js list                 every backup in the bucket
 *   node dist/ops/backup-cli.js now                  make a backup right now
 *   node dist/ops/backup-cli.js check [key|latest]   download and read a backup
 *                                                    (a restore drill; changes nothing)
 *   node dist/ops/backup-cli.js restore <key|latest> [--replace]
 *        restore into the database in DATABASE_URL. Without --replace the
 *        tables must be empty (a fresh database); with it, they are emptied
 *        first. Restoring over live data: tell your users first; the app
 *        reconnects by itself afterwards.
 *
 * From your computer instead: in server/, with DATABASE_URL (the database's
 * public URL), the S3_* settings and BACKUP_ENCRYPTION_KEY set, run
 * `npx tsx src/ops/backup-cli.ts list` (same commands).
 */
import { config } from "../config.js";
import { pool } from "../db.js";
import { getBucket } from "../files.js";
import { migrate } from "../migrate.js";
import { listBackups, readBackup, restoreBackup, runBackup, type BackupInfo } from "./backup.js";

async function pick(which: string | undefined): Promise<BackupInfo> {
  const all = await listBackups();
  if (all.length === 0) throw new Error("No backups in the bucket yet.");
  if (!which || which === "latest") return all[all.length - 1];
  const found = all.find((b) => b.key === which || b.key.endsWith(which));
  if (!found) throw new Error(`No backup called ${which}. Run "list" to see them.`);
  return found;
}

async function load(which: string | undefined) {
  const b = await pick(which);
  console.log(`Reading ${b.key} (${(b.size / 1024).toFixed(1)} KB, made ${b.at.toISOString()})…`);
  const bytes = await getBucket().getBytes(b.key);
  if (!bytes) throw new Error("The backup file is missing.");
  return readBackup(bytes, config.backups.encryptionKey);
}

async function main() {
  if (!config.s3.bucket) throw new Error("Set the S3_* settings (the bucket) first.");
  const [cmd, arg, flag] = process.argv.slice(2);
  switch (cmd) {
    case "list": {
      const all = await listBackups();
      if (all.length === 0) console.log("No backups yet.");
      for (const b of all) console.log(`${b.key}  ${(b.size / 1024).toFixed(1)} KB${b.encrypted ? "  (encrypted)" : ""}`);
      break;
    }
    case "now": {
      const r = await runBackup();
      console.log(`Made ${r.key} (${(r.size / 1024).toFixed(1)} KB). Rows:`, r.tables);
      break;
    }
    case "check": {
      const c = await load(arg);
      let total = 0;
      for (const [t, rows] of c.rows) {
        if (rows.length) console.log(`  ${t}: ${rows.length}`);
        total += rows.length;
      }
      console.log(`OK: ${total} rows in ${c.rows.size} tables, made ${c.header.createdAt}.`);
      break;
    }
    case "restore": {
      if (!arg) throw new Error("Say which backup: restore latest, or restore <key>.");
      const c = await load(arg);
      await migrate();
      const r = await restoreBackup(c, { replace: flag === "--replace" || arg === "--replace" });
      console.log("Restored rows:", r.tables);
      if (r.skippedTables.length) console.log("Not in this database (skipped):", r.skippedTables);
      console.log("Done. Start the us-server service again if you stopped it.");
      break;
    }
    default:
      console.log("Usage: node dist/ops/backup-cli.js list | now | check [latest|key] | restore <latest|key> [--replace]");
  }
}

main()
  .then(() => pool.end())
  .catch(async (e) => {
    console.error(String(e instanceof Error ? e.message : e));
    await pool.end().catch(() => {});
    process.exit(1);
  });
