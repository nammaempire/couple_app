/** Creates or updates the database tables. Safe to run on every deploy. */
import { pool } from "./db.js";
import { schemaSql } from "./schema.js";

export async function migrate(): Promise<void> {
  const c = await pool.connect();
  try {
    // One migrator at a time, even with several instances starting together.
    await c.query("SELECT pg_advisory_lock(727274)");
    await c.query(schemaSql());
  } finally {
    await c.query("SELECT pg_advisory_unlock(727274)").catch(() => {});
    c.release();
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  migrate()
    .then(() => {
      console.log("Database is up to date.");
      return pool.end();
    })
    .catch((e) => {
      console.error(e);
      process.exit(1);
    });
}
