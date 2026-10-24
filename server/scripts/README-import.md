# Copying the Firebase data into the new backend

This is a one-time job. It copies every Firestore document into Postgres and every
Firebase Storage file into the Railway bucket. File links saved in documents
(photos, videos, voice notes, profile pictures…) are rewritten to point at the
new server. Nothing in Firebase is changed or deleted.

You run it from your own computer, inside the `server` folder. You need Node 22+.

## 1. Get a Firebase key

1. Open the [Firebase console](https://console.firebase.google.com), pick the project.
2. Click the gear icon → **Project settings** → **Service accounts**.
3. Click **Generate new private key** → **Generate key**. A `.json` file downloads.
4. Move it somewhere safe, for example `server/scripts/firebase-key.json`
   (files ending in `.json` in this folder are ignored by git). **Never commit or share it.**

## 2. Collect the settings

Create a file `server/scripts/import.env` (also ignored by git) with:

```
GOOGLE_APPLICATION_CREDENTIALS=scripts/firebase-key.json

# Only if needed: the bucket name shown in Firebase console → Storage, e.g. gs://xyz.
# Default is <project-id>.firebasestorage.app. Older projects use <project-id>.appspot.com.
# FIREBASE_STORAGE_BUCKET=

# Railway → Postgres → Connect → "Public network" connection URL
# (the private *.railway.internal one only works inside Railway).
DATABASE_URL=postgresql://postgres:...@....proxy.rlwy.net:12345/railway

# Railway → Bucket → Credentials (same values as the server's variables)
S3_ENDPOINT=
S3_REGION=auto
S3_BUCKET=
S3_ACCESS_KEY_ID=
S3_SECRET_ACCESS_KEY=

# Copy these two EXACTLY from the server service's Variables tab.
# If they differ, the rewritten file links will not open in the app.
PUBLIC_URL=https://your-server.up.railway.app
FILE_URL_SECRET=
```

If the server has `S3_FORCE_PATH_STYLE` or `DATABASE_SSL` set, copy those too.

## 3. Dry run (reads only, writes nothing)

```
cd server
npm install
npm run import-firebase -- --env-file=scripts/import.env --dry-run
```

At the end you get a summary: documents per table, skipped paths, links that will
be rewritten, files that will be copied and their total size, and warnings.
Check that:

- the tables and counts look like your data (e.g. `couple_messages` ≈ number of chat messages);
- **Skipped documents** only lists things you don't need (anything the new backend
  doesn't know about is skipped, not lost — it stays in Firebase);
- the warnings make sense (e.g. "bytes stored as a base64 string", "field names may not start with $").

## 4. Real run

Best done when few people use the app (the copy is a snapshot of that moment).

```
npm run import-firebase -- --env-file=scripts/import.env
```

It first creates the tables if needed, then copies documents, then files. Progress
is printed as it goes. To keep a full log: add `--verbose > import-log.txt 2>&1`.

You can also do the two parts separately: `--only=firestore` or `--only=storage`,
and limit documents to some root collections with `--collection=users,couples`.

## 5. Check the result

- The summary's counts per table should match the dry run.
- `Storage files: … 0 failed`. Files already copied show as "already there".
- "Links to files that are not in the Firebase bucket" lists links whose file was
  already deleted in Firebase; those were broken before too.
- Open the app on the new backend: chats, photos, voice notes and profile pictures should load.
- Optional: run the same command again. It should report 0 new / 0 updated and copy 0 files.

## If it stops halfway

Just run **the same command again**. It is safe to repeat:

- documents are written with "insert or update", so nothing is duplicated;
- a document that was changed in the new backend after its last Firestore change is left alone;
- documents changed in Firebase since the last run are updated;
- files that are already in the bucket with the same size are skipped.

Common reasons it stops:

| Message | What to do |
| --- | --- |
| `Can't start: … is not set` | Fill in that setting in `import.env`. |
| `No Firebase key` / `invalid_grant` | Check the key path; generate a new key if it was deleted. |
| `bucket … not found` | Set `FIREBASE_STORAGE_BUCKET` to the name shown in Firebase console → Storage. |
| `RESOURCE_EXHAUSTED` / quota | Firebase's daily free read quota ran out. Wait a day or enable billing, then run again. |
| Connection / SSL errors to Postgres | Use the *public* `DATABASE_URL`; try `DATABASE_SSL=true`. |
| `Some files failed to copy` (exit code 2) | Run again; only the missing files are copied. |

Exit codes: 0 = done, 1 = stopped with an error, 2 = done but some files failed.

## Good to know

- Firestore cost: about 2 reads per document (the document, plus a check for subcollections).
  Storage: every file is downloaded once (Google bills download traffic).
- Deleting something in Firebase after the import does not delete it in the new backend.
- When you're done, delete the key: Google Cloud console → IAM & Admin → Service accounts →
  the `firebase-adminsdk` account → Keys → delete. Then delete `firebase-key.json` and `import.env`.
