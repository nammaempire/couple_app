/** Settings, all from environment variables (Railway → service → Variables). */

function opt(name: string, fallback = ""): string {
  const v = process.env[name];
  return v === undefined || v === "" ? fallback : v;
}

export const config = {
  port: Number(opt("PORT", "8080")),
  /** Postgres connection string. On Railway: ${{Postgres.DATABASE_URL}}. */
  databaseUrl: opt("DATABASE_URL", "postgres://postgres@127.0.0.1:5432/us_dev"),
  /** Use TLS to Postgres (Railway's private network doesn't need it). */
  databaseSsl: opt("DATABASE_SSL", "false") === "true",

  /** Firebase project whose ID tokens are accepted (sign-in stays on Firebase). */
  firebaseProjectId: opt("FIREBASE_PROJECT_ID", "together-48033"),

  /** Public https URL of this server, used in file download links. */
  publicUrl: opt("PUBLIC_URL", "http://localhost:8080").replace(/\/+$/, ""),

  /** S3-compatible bucket (Railway Bucket → Credentials). */
  s3: {
    endpoint: opt("S3_ENDPOINT"),
    region: opt("S3_REGION", "auto"),
    bucket: opt("S3_BUCKET"),
    accessKeyId: opt("S3_ACCESS_KEY_ID"),
    secretAccessKey: opt("S3_SECRET_ACCESS_KEY"),
    forcePathStyle: opt("S3_FORCE_PATH_STYLE", "false") === "true",
  },

  /** Secret that signs file download links. Any long random string. */
  fileUrlSecret: opt("FILE_URL_SECRET", "dev-only-file-url-secret-change-me"),

  /** Google Play: package name, and the Pub/Sub push audience for RTDN. */
  playPackageName: opt("PLAY_PACKAGE_NAME", "com.nammaempire.together"),
  /** Service account JSON (one line) with Play Console access; empty = Play API off. */
  googleServiceAccountJson: opt("GOOGLE_SERVICE_ACCOUNT_JSON"),
  /** Expected audience of Pub/Sub push tokens (usually PUBLIC_URL + "/webhooks/play-rtdn"). */
  rtdnAudience: opt("RTDN_AUDIENCE"),
  /** Email of the service account Pub/Sub signs push requests as. */
  rtdnServiceAccountEmail: opt("RTDN_SERVICE_ACCOUNT_EMAIL"),

  /**
   * Firebase service-account key (JSON on one line) used to send push
   * notifications through Firebase Cloud Messaging. Empty = no pushes.
   */
  firebaseServiceAccountJson: opt("FIREBASE_SERVICE_ACCOUNT_JSON"),
  /**
   * Contact email shown on the public pages: /privacy, /terms and
   * /delete-account (deletion requests without the app).
   */
  supportEmail: opt("SUPPORT_EMAIL"),
  backups: {
    /** Daily database backups to the bucket (under backups/db/). On by default. */
    enabled: opt("BACKUPS_ENABLED", "true") === "true",
    /**
     * Encrypts backups (AES-256-GCM, key derived from this passphrase). Keep a
     * copy somewhere safe: without it a backup can't be restored.
     */
    encryptionKey: opt("BACKUP_ENCRYPTION_KEY"),
    /** How many days of backups to keep (the privacy policy promises at most 30). */
    retentionDays: Math.min(30, Math.max(1, Number(opt("BACKUP_RETENTION_DAYS", "30")) || 30)),
  },

  /** The company's registered address, shown in the privacy policy and terms. */
  companyAddress: opt("COMPANY_ADDRESS"),
  /** Name of the Grievance Officer (Indian IT Rules), shown in the privacy policy. */
  grievanceOfficer: opt("GRIEVANCE_OFFICER"),

  /**
   * TURN relay for calls (coturn with use-auth-secret). Comma-separated URLs,
   * e.g. "turn:turn.example.com:3478,turns:turn.example.com:443?transport=tcp".
   * Empty = direct (STUN-only) calls.
   */
  turn: {
    urls: opt("TURN_URLS").split(",").map((u) => u.trim()).filter(Boolean),
    secret: opt("TURN_SECRET"),
    ttlSeconds: Number(opt("TURN_TTL_SECONDS", "21600")),
  },

  /** Run the "end due separations" job every 15 minutes. */
  runScheduler: opt("RUN_SCHEDULER", "true") === "true",

  /**
   * Tests only: accept "test:<uid>" bearer tokens. Never enabled when
   * NODE_ENV=production.
   */
  authTestMode: opt("AUTH_TEST_MODE", "false") === "true" && opt("NODE_ENV") === "test",

  isProduction: opt("NODE_ENV") === "production",
};
