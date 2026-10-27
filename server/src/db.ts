import pg from "pg";
import { config } from "./config.js";

// Return jsonb as text-parsed JSON (default) and timestamptz as ISO strings.
pg.types.setTypeParser(1184, (v) => new Date(v).toISOString());
pg.types.setTypeParser(20, (v) => Number(v)); // bigint (versions) as numbers

export const pool = new pg.Pool({
  connectionString: config.databaseUrl,
  ssl: config.databaseSsl ? { rejectUnauthorized: false } : undefined,
  max: 10,
  keepAlive: true,
});

// An idle connection can be dropped by Postgres (restart, failover). Without
// a listener that error would crash the process; the pool reconnects itself.
pool.on("error", (e) => {
  console.error("Postgres connection error (pool will reconnect):", e.message);
});

export type Client = pg.PoolClient;

/**
 * Document paths changed inside a transaction, announced to this process's
 * live listeners right after COMMIT. (NOTIFY also announces them to other
 * instances, but this doesn't depend on that connection being healthy.)
 */
const pendingChanges = new WeakMap<object, string[]>();
type CommitListener = (paths: string[]) => void;
const commitListeners = new Set<CommitListener>();

export function markChanged(c: Client, paths: string[]): void {
  const list = pendingChanges.get(c);
  if (list) list.push(...paths);
  else pendingChanges.set(c, [...paths]);
}

export function onCommitted(fn: CommitListener): () => void {
  commitListeners.add(fn);
  return () => commitListeners.delete(fn);
}

function emitCommitted(c: Client): void {
  const paths = pendingChanges.get(c);
  pendingChanges.delete(c);
  if (!paths?.length) return;
  for (const fn of commitListeners) {
    try {
      fn(paths);
    } catch (e) {
      console.error("Change listener failed:", e);
    }
  }
}

/** Runs [fn] in a transaction, retrying on serialization failures / deadlocks. */
export async function tx<T>(fn: (c: Client) => Promise<T>, attempts = 4): Promise<T> {
  for (let i = 0; ; i++) {
    const c = await pool.connect();
    try {
      pendingChanges.delete(c);
      await c.query("BEGIN");
      const r = await fn(c);
      await c.query("COMMIT");
      emitCommitted(c);
      return r;
    } catch (e) {
      pendingChanges.delete(c);
      await c.query("ROLLBACK").catch(() => {});
      const code = (e as { code?: string }).code;
      if ((code === "40001" || code === "40P01") && i < attempts - 1) continue;
      throw e;
    } finally {
      c.release();
    }
  }
}
