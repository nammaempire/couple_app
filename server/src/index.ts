import { buildApp } from "./app.js";
import { config } from "./config.js";
import { migrate } from "./migrate.js";
import { startScheduler } from "./functions/scheduler.js";
import { startBackups } from "./ops/backup.js";

/** Refuse to start in production with settings that would be unsafe. */
function checkProductionConfig(): void {
  if (!config.isProduction) return;
  const problems: string[] = [];
  if (config.fileUrlSecret === "dev-only-file-url-secret-change-me" || config.fileUrlSecret.length < 32) {
    problems.push("FILE_URL_SECRET must be set to a random string of at least 32 characters.");
  }
  if (!/^https:\/\//.test(config.publicUrl)) problems.push("PUBLIC_URL must be the server's https:// address.");
  if (!config.s3.bucket) problems.push("S3_BUCKET (and the other S3_* settings) must be set.");
  if (process.env.AUTH_TEST_MODE === "true") problems.push("AUTH_TEST_MODE must not be set in production.");
  if (config.backups.enabled && !config.backups.encryptionKey) {
    // The privacy policy says backups are encrypted.
    console.warn("BACKUP_ENCRYPTION_KEY is not set: daily backups are stored unencrypted. Set it on Railway.");
  }
    if (problems.length) {
    console.error("Refusing to start:\n- " + problems.join("\n- "));
    process.exit(1);
  }
}

process.on("unhandledRejection", (e) => {
  console.error("Unhandled rejection (kept running):", e);
});

async function main() {
  checkProductionConfig();
  await migrate();
  const app = await buildApp({ logger: true });
  const stopJobs: () => unknown = config.runScheduler ? startScheduler() : () => {};
  // Daily database backups to the bucket (needs a real bucket, not memory).
  const stopBackups: () => unknown =
    config.runScheduler && config.backups.enabled && config.s3.bucket ? startBackups() : () => {};
  const stop = () => Promise.all([stopJobs(), stopBackups()]);
  const shutdown = async () => {
    await stop();
    await app.close();
    process.exit(0);
  };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
  await app.listen({ port: config.port, host: "0.0.0.0" });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
