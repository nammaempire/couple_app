import pg from "pg";
import { config } from "./config.js";

// Return jsonb as text-parsed JSON (default) and timestamptz as ISO strings.
pg.types.setTypeParser(1184, (v) => new Date(v).toISOString());
pg.types.setTypeParser(20, (v) => Number(v)); // bigint (versions) as numbers

export const pool = new pg.Pool({
  connectionString: config.databaseUrl,
  ssl: config.databaseSsl ? { rejectUnauthorized: false } : undefined,
  max: 10,
});

// An idle connection can be dropped by Postgres (restart, failover). Without
// a listener that error would crash the process; the pool reconnects itself.
pool.on("error", (e) => {
  console.error("Postgres connection error (pool will reconnect):", e.message);
});

export type Client = pg.PoolClient;

/** Runs [fn] in a transaction, retrying on serialization failures / deadlocks. */
export async function tx<T>(fn: (c: Client) => Promise<T>, attempts = 4): Promise<T> {
  for (let i = 0; ; i++) {
    const c = await pool.connect();
    try {
      await c.query("BEGIN");
      const r = await fn(c);
      await c.query("COMMIT");
      return r;
    } catch (e) {
      await c.query("ROLLBACK").catch(() => {});
      const code = (e as { code?: string }).code;
      if ((code === "40001" || code === "40P01") && i < attempts - 1) continue;
      throw e;
    } finally {
      c.release();
    }
  }
}
