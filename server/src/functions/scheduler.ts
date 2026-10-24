/**
 * Background jobs: "end due separations" every 15 minutes (the Cloud
 * Scheduler job processSeparations). Every instance runs the timer; a
 * Postgres advisory lock makes sure only one of them does a given tick.
 */
import { pool } from "../db.js";
import { logger } from "./log.js";
import { processSeparations } from "./separations.js";

export const SEPARATIONS_INTERVAL_MS = 15 * 60 * 1000;
/** pg_try_advisory_lock key for processSeparations. */
export const SEPARATIONS_LOCK_KEY = 727275;

/**
 * Runs one tick if no other instance is running one. Returns false when the
 * lock was held elsewhere.
 */
export async function runSeparationsTick(): Promise<boolean> {
  const c = await pool.connect();
  let locked = false;
  try {
    const r = await c.query<{ ok: boolean }>("SELECT pg_try_advisory_lock($1) AS ok", [SEPARATIONS_LOCK_KEY]);
    locked = r.rows[0]?.ok === true;
    if (!locked) return false;
    await processSeparations();
    return true;
  } finally {
    if (locked) await c.query("SELECT pg_advisory_unlock($1)", [SEPARATIONS_LOCK_KEY]).catch(() => {});
    c.release();
  }
}

/**
 * Starts the 15-minute timer. Returns a stop function; its promise resolves
 * once a tick that is already running has finished.
 */
export function startScheduler(intervalMs = SEPARATIONS_INTERVAL_MS): () => Promise<void> {
  let current: Promise<void> | null = null;
  let stopped = false;
  const tick = () => {
    if (current || stopped) return; // a slow tick never overlaps the next one
    current = runSeparationsTick()
      .then(() => undefined)
      .catch((e) => logger.error("processSeparations: tick failed", { error: String(e) }))
      .finally(() => {
        current = null;
      });
  };
  const timer = setInterval(tick, intervalMs);
  // One early tick after start-up, so frequent deploys never starve the job.
  const first = setTimeout(tick, Math.min(30_000, intervalMs));
  timer.unref?.();
  first.unref?.();
  return async () => {
    stopped = true;
    clearInterval(timer);
    clearTimeout(first);
    await current;
  };
}
