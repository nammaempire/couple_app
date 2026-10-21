# Us — a private chat app for two

A Flutter app where two partners pair with an invite code and share a single
private conversation: text messages and photos, synced live.

**Built:** onboarding (welcome, email + Google sign-in, profile, create/join a
couple with code, QR or share sheet, setup checklist), real-time chat, photo
sending, voice and video calls, moods, daily question, memories, calendar,
love notes, Plans (date planner, bucket list, wishlist, places, shared
expenses) and Play: live games for two (How well do you know me?, Truth or
Dare, Tic-tac-toe, Connect Four, Ludo, Snakes & Ladders).

---

## What you must do before it runs

The app expects a Firebase project. Nothing in `lib/` needs editing — the setup
is all configuration.

### 1. Install the tooling

```bash
dart pub global activate flutterfire_cli
npm install -g firebase-tools
firebase login
```

### 2. Create a Firebase project

At <https://console.firebase.google.com>, create a project. Then enable:

- **Authentication → Sign-in method → Email/Password**
- **Firestore Database** (start in production mode; rules come from this repo)
- **Storage** (same)

### 3. Connect the app

From the project root:

```bash
flutterfire configure
```

This writes `lib/firebase_options.dart` and `android/app/google-services.json`.

`main.dart` already initialises Firebase with
`DefaultFirebaseOptions.currentPlatform`.

### 4. Add the Google Services Gradle plugin

In `android/settings.gradle.kts`, inside the `plugins { }` block:

```kotlin
id("com.google.gms.google-services") version "4.4.2" apply false
```

In `android/app/build.gradle.kts`, inside its `plugins { }` block:

```kotlin
id("com.google.gms.google-services")
```

### 5. Deploy the security rules

The rules in this repo restrict every message and photo to the two members of a
couple. Deploy them:

```bash
firebase deploy --only firestore:rules,storage:rules
```

You may need a `firebase.json` pointing at the files:

```json
{
  "firestore": { "rules": "firestore.rules" },
  "storage": { "rules": "storage.rules" }
}
```

To check the rules locally against the Firestore emulator (needs Node and
Java):

```bash
cd firestore-tests
npm install
npm test
```

### 6. Run

```bash
flutter pub get
flutter run
```

---

## Onboarding flow

`AuthGate` moves each person through these steps from Firestore state alone,
so no screen navigates to the next one:

1. **Welcome**: the promise, then *Get started* or *I already have an account*.
2. **Sign in**: Google, or email and password (with password reset).
3. **About you**: photo, name, optional nickname, optional birthday.
4. **Connect**: *Create our space* (optional couple name, start date and
   photo) or *I have an invite* (type the code or scan the QR).
5. **Invite**: the creator sees a QR code, the code and a *Share invite*
   button, and waits. The joiner sees who invited them and taps *Accept and
   connect*.
6. **Setup checklist**: anniversary, birthday, notification preferences and
   privacy. Every item is optional, and each one can be changed later from the
   Us tab.

Accounts created before onboarding existed skip steps 3 and 6 if they are
already paired.

## How pairing works

1. Partner A creates a space. In one batch this writes `couples/{id}`,
   `invites/{code}` and `coupleId` on A's profile.
2. Partner B looks the code up with a single `get` on `invites/{code}`.
   Invites can't be listed, so codes can't be enumerated.
3. B accepts in one transaction: adds themselves to `memberIds`, marks the
   invite `used`, and sets their own `coupleId`.

The security rules only allow step 3 when the couple has exactly one member
and the same write consumes that couple's unused invite. Couples can only be
read by their two members, and nobody can add a third person.

A waiting creator can cancel their space ("My partner already sent me a code")
to join the partner's invite instead.

### Google sign-in setup

1. Firebase console → **Authentication → Sign-in method** → enable **Google**.
2. Add your SHA-1 fingerprints under **Project settings → Your apps →
   Android** (debug: `cd android && ./gradlew signingReport`; also add the
   release keystore's SHA-1, and Play App Signing's if you publish).
3. Download the new `google-services.json` into `android/app/`. It must
   contain an `oauth_client` entry. Without one, the app shows "Google sign-in
   is not set up for this build yet".

## Data model

```
users/{uid}
  displayName, nickname, photoUrl, birthday, coupleId, email, createdAt,
  profileComplete, setupComplete, privacyReviewed,
  notificationPrefs: { messages, mood, dailyQuestion, dates, quietHours },
  avatar: { skin, face, hair, hairColor, eyes, eyeColor, brows, facialHair,
            glasses, accessory, faceAccessory, outfit, outfitColor,
            background }   (option ids; unknown ids fall back to defaults),
  avatarAsPhoto            true = show the avatar instead of the photo
                           (unset: avatar shows only when there's no photo)

invites/{code}
  coupleId, createdBy, inviterName, inviterPhotoUrl, coupleName,
  used, usedBy, usedAt, createdAt

couples/{coupleId}
  inviteCode, memberIds[], createdAt, activatedAt, coupleName, photoUrl,
  lastMessagePreview, lastMessageAt, startDate, nextMeetup,
  nicknames: { <setterUid>: "what that person calls their partner" }

couples/{coupleId}/moods/{uid}
  mood, note, updatedAt

couples/{coupleId}/dailyQuestions/{yyyy-MM-dd}
  prompt, date, answers: { <uid>: { text, answeredAt } }

couples/{coupleId}/memories/{memoryId}
  title, caption, date, place, album, favorite, createdBy, createdAt,
  media: [ { type ("image" | "video"), url, thumbUrl, aspectRatio, durationMs } ]

couples/{coupleId}/events/{eventId}
  title, type ("dateNight" | "trip" | "anniversary" | "birthday" | "custom"),
  start, end, allDay, location, notes, budget, repeatYearly,
  private, reminder ("none" | "atTime" | "hour" | "day" | "week"), createdBy

couples/{coupleId}/notes/{noteId}                 (envelope, both can read)
  senderId, recipientId, kind ("letter" | "openWhen"), openWhen, title,
  deliverAt, createdAt, openedAt, hasVoice, voiceDurationMs
couples/{coupleId}/notes/{noteId}/sealed/content  (recipient only from deliverAt)
  body, voiceUrl, deliverAt, senderId, recipientId

couples/{coupleId}/nudges/{nudgeId}
  senderId, sentAt, kind ("thinking" | "love" | "miss" | "hug" | "kiss")

couples/{coupleId}/call/current
  callerId, calleeId, type ("voice" | "video"),
  status ("ringing" | "accepted" | "declined" | "ended" | "missed"),
  channelName, startedAt, answeredAt, endedAt

couples/{coupleId}/messages/{messageId}
  senderId, type ("text" | "image" | "video" | "voice" | "call"), text,
  imageUrl (photo or video thumbnail), imageAspectRatio, mediaUrl (video or
  voice), durationMs, sentAt, seen, reactions: { <uid>: emoji },
  replyTo: { messageId, senderId, type, text }, pinned, pinnedAt,
  callType ("voice" | "video"), callOutcome ("completed" | "missed" | "declined")
```

Either partner may update only `seen`, `reactions`, `pinned` and `pinnedAt`.
Message text and sender can never be edited.

Plans (all under `couples/{coupleId}/`; money is always integer minor
units, e.g. paise):

```
datePlans/{id}       title, notes, status ("idea" | "planned" | "done"),
                     scheduledAt, location, estimatedCostMinor, vibe, rating,
                     reflection, completedAt, createdBy
bucketList/{id}      title, notes, category, done, doneAt, doneBy,
                     targetYear, createdBy
wishlist/{id}        title, notes, url, priceMinor, priority, occasion,
                     received, createdBy (the person who wants it)
wishlistClaims/{id}  claimedBy, itemOwner, claimedAt, purchased
                     (id = the wish's id; readable only by the claimer)
places/{id}          name, area, mapsUrl, category, status ("wantToGo" |
                     "been"), rating, visitedAt, notes, favourite, createdBy
expenses/{id}        kind ("expense" | "settlement"), title, amountMinor,
                     paidBy, split ("equal" | "full" | "custom"), shares,
                     category, spentOn, note, createdBy
couples/{id}.currency  ISO 4217 code for expenses (default "INR")
```

Chat look:

```
couples/{id}/settings/chatLook   color (ARGB int | null = default), background
                                 {kind "none"|"pattern"|"photo", patternId,
                                 photoUrl, storagePath, dim 0–0.7, blur 0–12},
                                 updatedBy, updatedAt
users/{uid}.chatLookMode         "shared" | "personal"
users/{uid}.chatLook             { color, background } (their own look)
```

Couple stickers are ordinary chat messages:

```
type: "sticker", text: the quote (≤ 90 characters in the app, ≤ 400 in the
rules), sticker: { id: scene id, e.g. "miss-moon", category: "missYou" }
```

The scene is drawn on the phone from both partners' *current* avatars, so
nothing is uploaded, and older app versions just show the quote as text.

Music:

```
couples/{id}/songs/{songId}
  url (https), source ("spotify" | "youtube" | "youtubeMusic" | "appleMusic" |
  "jioSaavn" | "soundCloud" | "other"), kind ("track" | "video" | "album" |
  "playlist" | "other"), mediaId (YouTube video id / Spotify id),
  title, artist, thumbnailUrl, note, moment, lovedBy { uid: true },
  addedBy, playCount, createdAt, lastPlayedAt
couples/{id}/listening/now       the one "listen together" session:
  songId, url, source, mediaId, title, artist, thumbnailUrl,
  status ("countdown" | "playing" | "paused" | "ended"), positionMs, at
  (server ms when positionMs was true), queue [songIds], hostUid,
  updatedBy, listeners { uid: last check-in, server ms }, version, updatedAt
couples/{id}/listening/clock-{uid}   { t: serverTimestamp } for measuring
                                     the phone's offset from server time
```

The rules make every playback change bump `version` by exactly one (the app
writes in a transaction), and a check-in may only touch your own listener
entry. A song's link and who added it never change; plays only go up by one.

Background photos: `couples/{id}/backgrounds/` (both partners) and
`users/{uid}/backgrounds/` (personal, only the owner can read it).

Play (`couples/{coupleId}/games/{id}`), one document per game:

```
type ("knowMe" | "truthOrDare" | "ticTacToe" | "connectFour" | "ludo" |
      "snakesLadders"),
status ("invited" | "active" | "finished" | "cancelled"),
createdBy, invitee, players, turn (whoever must act next), state (per game),
winner (uid | "draw" | null), moveCount, createdAt, updatedAt, finishedAt
games/{id}/secret/answers   quiz answers: readable by the person they're
                            about, and by the guesser only after locking in
```

The rules let only the `turn` holder change an active game and require
`moveCount` to go up by exactly one per write, so moves can't be made out of
turn or applied twice; finished games are frozen.

Storage: `couples/{id}/photos/` (chat photos and video thumbnails),
`couples/{id}/videos/`, `couples/{id}/voice/`, `couples/{id}/memories/`,
`couples/{id}/notes/` (voice letters, readable directly only by the sender),
`couples/{id}/profile/`
(couple photo), `users/{uid}/profile/` (profile photo).

## Project layout

Feature-first: each feature keeps its own data (Firestore/Storage services),
models, screens and widgets. Shared pieces live in `core/`. Imports always
use `package:couple_app/...`.

```
lib/
  main.dart                 entry point: Firebase init, runApp
  app.dart                  MaterialApp, theme, AuthGate
  firebase_options.dart     generated by flutterfire (do not edit)
  core/
    config/                 Agora App ID
    theme/                  colour palette and Material 3 theme
    services/               Storage uploads, voice playback, voice recording
    media/                  full-screen photo viewer and video player
    utils/                  snack bars, duration formatting, input formatters
    widgets/                empty state, avatar picker, voice clip player, name dialog
  features/
    auth/                   sign-in, AuthGate (routes onboarding vs app), AppUser
    couple/                 Couple and Invite models, CoupleService (pairing)
    onboarding/             welcome, profile, pairing steps, invite, QR scan, checklist
    shell/                  MainShell: bottom tabs, incoming calls, reminders
    home/                   Home tab: counter, love taps, moods, daily question
    chat/                   chat, search, media gallery, bubbles, composer
    calls/                  Agora voice/video calls and call signalling
    memories/               albums, timeline, editor, recaps
    together/               calendar, love notes, local reminders
    plans/                  date planner, bucket list, wishlist, places, expenses
    play/                   games hub and the games (know_me/, truth_or_dare/, board/)
    us/                     Us tab: profile, couple settings, question archive
    avatar/                 avatar model, painters, builder, AvatarView
    stickers/               couple sticker scenes, quotes, picker, sticker view
    music/                  song links, oEmbed lookup, listen-together sync,
                            YouTube player, library, editor, player, banner
```

Inside a feature:

```
features/<name>/
  data/       services that talk to Firebase or the device
  models/     plain data classes with fromDoc / toMap
  screens/    full-page routes (StatefulWidgets hold the state)
  widgets/    pieces of those screens, stateless where possible
```

## State management (Riverpod)

The app uses `flutter_riverpod` (no code generation). `main.dart` wraps the
app in a `ProviderScope` with automatic retry turned off, so stream errors
reach the screens exactly as Firestore reports them.

Each feature has a `providers/` folder:

- **Services:** `authServiceProvider`, `chatServiceProvider`,
  `coupleServiceProvider` and so on. Screens get services with `ref.read`
  instead of constructing them, so tests can override them.
- **Session:** `currentUserProvider` (the signed-in profile),
  `currentUidProvider`, `currentCoupleIdProvider`. They are only valid below
  the auth gate's signed-in branches.
- **Shared data:** `coupleProvider`, `partnerProvider`, `partnerNameProvider`,
  `eventsProvider`, `incomingNotesProvider`, `memoriesProvider`,
  `moodsProvider`, `todayQuestionProvider`, `questionHistoryProvider`.
  Providers that depend on the user are `autoDispose`, so they close when
  the user signs out.

Screen-local streams (chat paging, a single memory, love notes) stay inside
their screens. `MainShell` keeps the reminder inputs alive with
`ref.listenManual` and still owns the incoming-call and love-tap listeners.

## Features

**Onboarding.** Email or Google sign-in, a profile step, pairing by code, QR
or share sheet, and a setup checklist (see *Onboarding flow*).

**Home**
- Couple header with the couple photo, or both partners' avatars
- Quick actions: message, voice call, video call, dates
- Days together, with years/months/days and the next milestone
- Send love: one-tap Thinking of you, Love you, Miss you, Hug and Kiss that
  buzz the partner's phone
- Coming up: countdowns to the anniversary, both birthdays and the next meetup
- Moods for both partners, each with an optional note
- Daily question that unlocks once both have answered, with a gentle streak
  (shown from 2 days)

**Chat**
- Text, photos, videos (up to 3 minutes and 100 MB, with thumbnails) and
  voice messages (tap the mic to record, tap send)
- Replies: swipe a message right, or long-press and choose Reply. Tap the
  quote to jump to the original
- Couple reactions: Love, Miss you, Hug, Kiss, Laugh (double-tap to heart)
- Pin messages; the latest pin shows under the app bar
- Search (on-device, over the latest 1,000 messages) with jump-to-message
- Photos & videos gallery, grouped by month
- Older messages load as you scroll up
- Delivered/seen ticks, marked seen only while the chat is on screen
- Call records in the conversation: completed (with duration), missed or
  declined
- Delete your own messages for both of you, with confirmation

**Chat theme.** Chat ⋮ → Chat theme. Pick a colour (12 swatches) and a
background: none, one of 10 built-in patterns (hearts, doodles, dots, waves,
confetti, sunset, ocean, lavender, blush, mint) or a photo from your gallery,
your memories or photos sent in chat, with dim and blur sliders. "Both of
us" changes the chat for you both; "Just me" keeps a look only you see. A
live preview shows exactly how it will look.

**Avatars.** Us → Your avatar. Build a cartoon you: 8 skin tones, 5 face
shapes, 13 hair styles and 8 colours, eyes, brows, facial hair, glasses,
bindi, earrings, turban or headscarf, 7 outfits and a background. Preview
12 expressions; "Use as my profile picture" shows it everywhere your photo
would (home header, chat, calls). Dice for a random start, undo for the last
change.

**Couple stickers.** Chat → the smiley button next to the message box. 35
scenes of the two of you (a warm hug, a slow dance, the same moon from two
windows, a patched-up heart, peace flowers…) across Love, Romantic, Missing you,
Sorry, Good morning, Good night, Cheer up and Funny, each with ready quotes
(133 in all) or your own words. The sender is always on the left. Stickers
can be reacted to, replied to, pinned, searched by quote and the quote
copied.

**Music** (Together → Music). Your songs, saved as links from Spotify,
YouTube, YouTube Music, Apple Music, JioSaavn or SoundCloud. Paste a link
and the title, artist and cover fill in (YouTube, Spotify and SoundCloud
oEmbed, no API keys). Tag each song with what it means to you (Our song,
Romantic, Missing you, Happy, Sad, Road trip, Dance, Chill), add a note,
heart the ones you love, search and filter.

*Listen together.* Tap ▶ on any song: both phones count down and start at
the same moment, and the rest of the list follows as "Up next".

- YouTube and YouTube Music links play inside the app. Play, pause, seek and
  skip on either phone move both, and each phone corrects itself if it
  drifts more than 1.5 s. Times are in server milliseconds (each phone
  measures its own clock offset), so phones whose clocks disagree still
  match. The video stays visible, as YouTube's terms require.
- Spotify, Apple Music, JioSaavn and other links can't be controlled from
  another app, so both phones open the song in its own app when the count
  hits zero; "Start together again" re-syncs. For to-the-second sync in
  Spotify, use Spotify Jam.
- While a session is live, a banner above the tabs shows what's playing and
  lets your partner join.

**Watch together** (Together → Music → Videos). Save YouTube videos (trailers,
shows, vlogs) and watch them in sync, exactly like songs: shared
play, pause, seek and skip, a countdown start, Up next, and a fullscreen
landscape mode. Stored in `couples/{id}/videos` (YouTube single videos only;
moments movieNight, funny, romantic, food, travel, music, learn, other) with
the session in `couples/{id}/watching/now` (same shape as `listening/now`).
Netflix and Hotstar can't be played or controlled inside another app.

Without push notifications (which need Cloud Functions), your partner sees
the banner when they open the app, not as a notification.

**Clear chat** (Chat ⋮ → Clear chat).
- *Clear for me* stamps `users/{uid}.chatClearedAt`; messages up to then are
  hidden on your account only (your partner keeps them, media stays).
- *Clear for both* stamps `couples/{id}.chatClearedAt` (server time, which
  the rules check) and `chatClearedBy`, then deletes every message sent up to
  that moment plus its photos, videos and voice notes, 400 per batch, and
  posts a "cleared the chat" line. The rules let either partner delete any
  message sent before the stamp. Rerunning finishes a half-done clear.

**Screenshots** (Chat ⋮ → Screenshots).
- While the chat (or a photo/video opened from it) is on screen, a screenshot
  posts a "📸 Asha took a screenshot" line for both of you. Detection uses
  Android 14's screen-capture callback (`DETECT_SCREEN_CAPTURE`, granted at
  install), so it works on Android 14+; older phones can't detect it without
  reading the photo library.
- "Block screenshots of our chat" (`couples/{id}.blockScreenshots`) sets
  FLAG_SECURE on both phones while the chat is open, on every Android
  version: screenshots and recordings come out black.
- Native code: `android/.../ScreenPrivacy.kt`, wired in `MainActivity.kt`
  over the `couple_app/screen_privacy` channel.
- System lines (`chatCleared`, `screenshot`, `screenshotBlock`) are short
  text only; the rules forbid media, reactions and pins on them.

**App lock** (Us → App lock). Fingerprint, face or the phone's PIN/pattern
(local_auth, `biometricOnly: false`) to open Us. Per phone, stored with
shared_preferences: off by default; lock immediately or after 1, 5 or 15
minutes in the background, and on every cold start. It can only be turned on
after a successful unlock, and is unavailable when the phone has no screen
lock. Our own trips out of the app (photo picker, camera, Spotify/YouTube
links, share sheet, Maps) never lock (`AppLockController.suspendWhile`).
A call keeps running under the lock. Android: `MainActivity` is a
`FlutterFragmentActivity`, themes are AppCompat, `androidx.appcompat` is a
dependency and `USE_BIOMETRIC` is in the manifest.

**Calls.** Voice and video over Agora. Unanswered calls stop ringing after
45 seconds.

**Memories** (tab)
- A memory holds up to 20 photos and videos, with a title, caption, date,
  place and album
- Albums: First Date, Trips, Birthdays, Anniversaries, Random Moments, plus any
  you name
- Timeline grouped by month; favourites; search by title, caption, place or
  album; filter by album or date range
- "On this day" from earlier years, and an "Our Memories" recap for any month
  or year
- Share or save a memory's photos and videos through the phone's share sheet
- Either partner can edit a memory; only the person who added it can delete it

**Together** (tab)
- *Calendar*: month view with dots, day list and "Upcoming". Event types are
  date night, trip (multi-day), anniversary, birthday and other. Each event can
  have a time, location, notes, a ₹ budget, a yearly repeat and a reminder.
  *Private* events are visible only to their creator (enforced by the rules).
  Your anniversary, both birthdays and the next meetup appear automatically.
- *Love notes*: a letter delivered now or on a chosen date and time, or an
  "Open when…" envelope (miss me, bad day, can't sleep, need a smile,
  birthday, anniversary). An optional voice letter can be recorded. A
  scheduled note shows your partner a sealed envelope ("arrives in 3 days"),
  and the rules keep its words unreadable until then. The sender can unsend.

**Plans** (third sub-tab of Together)
- *Date planner*: ideas, planned dates and done dates. Plan an idea for a day
  and time, then mark it done with 1–5 hearts and a note on how it went.
  "Surprise me" picks a random idea. Planned dates appear on the calendar and
  in Home's "Coming up", with a reminder an hour before.
- *Bucket list*: things to do together, by category, with progress, a target
  year and who ticked each one off.
- *Wishlist*: "My wishes" and your partner's. Tap "I'll get this" on one of
  theirs to claim it secretly; the rules make claims readable only by the
  person who made them, so the surprise is safe. Mark it bought, or unclaim.
- *Places*: want-to-go and been-there lists with categories, favourites,
  ratings, "Open in Maps" and "Plan a date here".
- *Shared expenses*: who paid, split equally, fully or by custom amounts.
  The header says in plain words who owes whom; "Settle up" records the
  payment. Includes monthly totals and a this-month-by-category breakdown.
  Currency is per couple (₹ by default).

**Play** (tab)
- A hub with invites and games waiting on you (the tab shows a badge),
  games waiting on your partner, a "start a game" card per game, a
  head-to-head tally and recent results. A snack bar tells you when your
  partner invites you while you're elsewhere in the app.
- *How well do you know me?*: one of you answers 7 questions about
  yourself; the other guesses. Answers stay hidden (by the rules) until the
  guesses are locked in, then both see the score and every answer.
- *Truth or Dare*: 10 rounds, taking turns; your partner judges whether you
  did it. 110 sweet, PG cards that work long-distance (voice notes, selfies,
  calls). Ends with "most daring", not a winner.
- *Tic-tac-toe* and *Connect Four*: live turn-based board games with win
  highlighting, a win tally and Play again.
- *Snakes & Ladders*: the classic 100-square board (9 ladders, 10 snakes),
  your avatars as tokens. Exact roll to 100 (overshoot bounces back), a 6
  rolls again, three 6s forfeit the roll. One write per roll.
- *Ludo for two*: opposite colours, Classic (4 tokens) or Quick (2 tokens,
  leave the yard on 1 or 6). A 6 to leave the yard, captures send tokens
  home except on the 8 safe squares, an exact roll into home, an extra roll
  for a 6 or a capture, three 6s forfeit. A roll and a move are separate
  writes; with no legal move the turn passes.
- Dice are rolled on the phone whose turn it is; the rules check turns, not
  randomness.

**Reminders.** Each phone schedules its own local notifications (no push
server needed): event reminders, the day before and the day of birthdays and
the anniversary, and when a love note arrives. They follow the notification
preferences, and quiet hours move late reminders to 21:30 the evening before.
They are re-planned whenever events change and each time the app opens, 60 days
ahead.

Home adds quick actions (Message, Memory, Event, Note), "Recent memories", and
calendar events and incoming notes in "Coming up".

Light and dark themes follow the system setting.

## Nicknames

Nicknames are one-directional on purpose. `nicknames` on the couple document is
keyed by the uid of the person who *set* the name, and the value is what that
person calls their partner. So you can call her "Bubu" while she calls you
"Chotu", and neither has to agree with the other's choice. Clearing a nickname
falls back to the partner's own display name.

Set both from the **Us** tab, under Names.

## Voice and video calls

Calling uses [Agora](https://console.agora.io) for the media and Firestore for
the signalling, so there is no call server to run.

### Setup

1. Sign up at <https://console.agora.io> and create a project.
2. Set its authentication mode to **Testing mode: APP ID**. This is what lets
   the app connect without a token server.
3. Copy the App ID.
4. Pass it at run or build time:

```bash
flutter run --dart-define=AGORA_APP_ID=your_app_id_here
flutter build apk --release --dart-define=AGORA_APP_ID=your_app_id_here
```

The `--dart-define` keeps the id out of version control. Without it the call
buttons explain that calling is not configured rather than failing obscurely.

The free tier is 10,000 minutes a month, which two people will not exhaust.
Video minutes count more heavily than voice.

### How it works

`couples/{coupleId}/call/current` is the signalling document. The caller writes
`status: ringing`; the callee's `MainShell` listener sees it and pushes the
incoming-call screen; accepting flips the status to `accepted` and both sides
join the same Agora channel. Either side writing `ended` closes both screens.

Channel names are random UUIDs generated per call, so testing mode's lack of
tokens is not a practical exposure — nobody can guess a live channel.

### The limitation

There are no push notifications yet, so **a call only rings if the other
person has the app open.** Android freezes background apps, so a closed app
will not ring. Fixing that needs FCM plus a Cloud Function to send the push on
call creation, which requires the Blaze plan. The call code itself would not
change — only the delivery of the ring.
