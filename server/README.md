# Us server

The app's backend: everything except sign-in.

| Part | Where |
|---|---|
| Sign-in (phone, email, Google) | **Firebase Auth**, unchanged |
| Data (users, couples, chat, memories, plans, games…) | **Postgres** on Railway |
| Files (photos, videos, voice notes, vault, memory books) | **Railway Bucket** (S3-compatible) |
| Live updates (chat, calls, games, listen-together) | **WebSockets** on this server |
| Server jobs (end a pairing, separations, Google Play purchases) | **This server** |

Node.js 22 + TypeScript, Fastify, `pg`. The app talks to it through
`lib/core/backend/` (a Firestore-shaped API: `Db`, `Files`, `Functions`).

## How it works (short)

- **Documents.** Each collection is a Postgres table (`src/schema.ts`): one
  row per document with its parent ids, `id`, `data jsonb`, `version`,
  `create_time`, `update_time`. Paths look like Firestore's, e.g.
  `couples/{coupleId}/messages/{messageId}`.
- **Security rules.** `src/rules/firestore.ts` and `src/rules/storage.ts`
  are line-by-line ports of the old `firestore.rules` / `storage.rules`. Every
  read, query, write, upload and live update from the app goes through them.
  A couple's data is visible only to its two members.
- **Sign-in check.** The app sends its Firebase ID token
  (`Authorization: Bearer …`); the server verifies it with Firebase's public
  keys. No Firebase service account is needed for this.
- **Live updates.** Every commit sends `NOTIFY doc_changes`; WebSocket
  listeners re-run and push fresh results (works with several instances).
- **Transactions.** Optimistic: reads carry a version; the commit is refused
  (`aborted`) if any changed, and the app retries — like Firestore.

## Differences from Firestore worth knowing

- **Queries return only what you may read.** Firestore refused a whole query
  that could include a document you can't read; this server leaves such
  documents out (rules are applied before the limit, so hidden documents
  can't be probed). The app never relied on those refusals.
- **No offline cache or instant local echo.** Writes need the server; a sent
  message appears once the server confirms it (usually well under a second).
- **Numbers:** `1.0` and `1` are the same number on this server.
- **File links** are signed links served by this server (`/f/…`). Like
  Firebase download URLs, they don't expire; keep `FILE_URL_SECRET` private.

## API

| Endpoint | What |
|---|---|
| `GET /health` | Health check (also checks Postgres) |
| `POST /v1/db/get` | `{paths:[…]}` → documents |
| `POST /v1/db/query` | `{collection, where, orderBy, limit}` → documents |
| `POST /v1/db/count` | same body → `{count}` |
| `POST /v1/db/commit` | `{writes:[{op,path,data,merge}], reads?:[{path,version}]}` |
| `WS /v1/realtime` | live documents and queries |
| `PUT /v1/files/<path>` | upload a file |
| `POST /v1/files/url` | `{path}` → download link |
| `DELETE /v1/files/<path>` | delete a file |
| `GET /f/<path>?t=…` | signed download link (redirects to the bucket) |
| `POST /v1/fn/finalizeSeparation` | end a separation whose date passed |
| `POST /v1/fn/leaveNow` | end the pairing now |
| `POST /v1/fn/verifyPurchase` | verify a Google Play purchase |
| `POST /webhooks/play-rtdn` | Google Play notifications (Pub/Sub push) |

Errors: `{"error": {"code": "permission-denied", "message": "…"}}` with codes
`invalid-argument, unauthenticated, permission-denied, not-found,
already-exists, aborted, failed-precondition, unavailable, internal`.

---

## Deploy on Railway

You already have the project **us-couple-app** with **Postgres** and a
**Bucket** (Singapore). Now add the server.

### 1. Put the code on GitHub

Push this repository (with the `server/` folder) to its GitHub repo.

### 2. Create the server service

1. In the project canvas: **+ Create → GitHub Repo** → pick the repo.
2. Open the new service → **Settings**:
   - **Root Directory**: `server`
   - **Config file** (if Railway asks): `server/railway.json`
     (it builds with the `Dockerfile` and checks `/health`).
   - **Region**: Southeast Asia (Singapore), same as Postgres and the bucket.
3. **Settings → Networking → Generate Domain.** You get something like
   `https://us-server-production.up.railway.app`. That is your **server URL**.

### 3. Set the variables

Service → **Variables** → add:

| Variable | Value |
|---|---|
| `NODE_ENV` | `production` |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` (reference to the Postgres service) |
| `PUBLIC_URL` | your server URL from step 2 (no trailing `/`) |
| `FIREBASE_PROJECT_ID` | `together-48033` |
| `FILE_URL_SECRET` | a long random string (e.g. 48+ random characters). **Keep it forever**: changing it breaks every saved file link. |
| `S3_ENDPOINT` | Bucket → **Credentials** → endpoint |
| `S3_REGION` | Bucket → Credentials → region (or `auto`) |
| `S3_BUCKET` | Bucket → Credentials → bucket name |
| `S3_ACCESS_KEY_ID` | Bucket → Credentials → access key |
| `S3_SECRET_ACCESS_KEY` | Bucket → Credentials → secret key |
| `S3_FORCE_PATH_STYLE` | `true` only if the bucket's credentials say to use path-style URLs |

For in-app purchases (can be added later; until then `verifyPurchase`
answers "unavailable"):

| Variable | Value |
|---|---|
| `GOOGLE_SERVICE_ACCOUNT_JSON` | the whole key JSON of a Google Cloud service account, on one line. In Play Console → Users and permissions, invite that account with **View financial data** and **Manage orders and subscriptions**. |
| `PLAY_PACKAGE_NAME` | `com.nammaempire.together` (default) |
| `RTDN_AUDIENCE` | `<server URL>/webhooks/play-rtdn` |
| `RTDN_SERVICE_ACCOUNT_EMAIL` | the service account Pub/Sub signs push requests as (see below) |

Optional: `RUN_SCHEDULER=false` turns off the 15-minute "end due
separations" job (leave it on); `FUNCTIONS_LOG=off` silences function logs;
`DATABASE_SSL=true` only if you connect to Postgres over its public URL.

Never set `AUTH_TEST_MODE` on Railway (it is ignored in production anyway).

Railway redeploys after you save variables. Open `<server URL>/health`:
`{"ok":true}` means the server is up and talking to Postgres. Tables are
created automatically on start.

### 4. Google Play notifications (only with in-app purchases)

Real-time developer notifications now arrive by **Pub/Sub push** instead of
a Cloud Function trigger. In Google Cloud (project `together-48033`):

```sh
gcloud pubsub topics create play-billing   # skip if it exists
gcloud pubsub topics add-iam-policy-binding play-billing \
  --member=serviceAccount:google-play-developer-notifications@system.gserviceaccount.com \
  --role=roles/pubsub.publisher
gcloud pubsub subscriptions create play-billing-push --topic=play-billing \
  --push-endpoint=<server URL>/webhooks/play-rtdn \
  --push-auth-service-account=<RTDN_SERVICE_ACCOUNT_EMAIL> \
  --push-auth-token-audience=<server URL>/webhooks/play-rtdn
```

In Play Console → Monetize → Monetization setup, set the topic to
`projects/together-48033/topics/play-billing` and send a test notification.

### 5. Point the app at the server

Build the app with the server URL:

```sh
flutter run --dart-define=API_URL=<server URL>
flutter build appbundle --release --dart-define=API_URL=<server URL> \
  --obfuscate --split-debug-info=build/symbols
```

(`lib/core/backend/backend_config.dart` reads `API_URL`.)

### 6. Copy the existing Firebase data

Once the server works, follow [`scripts/README-import.md`](scripts/README-import.md)
to copy all Firestore documents and Storage files into Railway. It is safe to
run more than once. Firebase itself is not changed.

---

## Develop and test locally

In production the server refuses to start if `FILE_URL_SECRET` is missing or
short, `PUBLIC_URL` isn't `https://`, the bucket isn't configured, or
`AUTH_TEST_MODE` is set.

Needs Node 22 and a Postgres.

```sh
cd server
npm install
# Tests: each test file creates and drops its own database.
TEST_DATABASE_ADMIN_URL=postgres://postgres@127.0.0.1:5432/postgres npm test
# Run the server against a local database, files kept in memory:
DATABASE_URL=postgres://postgres@127.0.0.1:5432/us_dev npm run dev
```

`npm run build` compiles to `dist/`; `npm start` runs it.

**End-to-end tests** (the app's real services against a real server):
start a test server, then run the Flutter e2e suite from the repo root.

```sh
# in server/
DATABASE_URL=postgres://postgres@127.0.0.1:5432/us_e2e AUTH_TEST_MODE=true \
  NODE_ENV=test PUBLIC_URL=http://127.0.0.1:18090 PORT=18090 npx tsx src/index.ts
# in the repo root, another terminal:
flutter test test_e2e/
```

`AUTH_TEST_MODE` (accepts `test:<uid>` tokens) only works with
`NODE_ENV=test`.
