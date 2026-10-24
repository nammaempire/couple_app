// Port of firestore-tests/test/music.rules.test.js: saved songs, the shared
// "listening together" session and watch-together, using the writes the app
// makes (lib/features/music/data/music_service.dart).
import { describe, it } from "node:test";
import { DEL, ST, admin, as, denied, inc, ok, ts, useDb } from "./rules-helpers.js";

type O = Record<string, unknown>;
const C = "couple1";

const song = (o: O = {}) => ({
  url: "https://www.youtube.com/watch?v=BddP6PYo2gs", source: "youtube",
  kind: "video", mediaId: "BddP6PYo2gs", title: "Tum Hi Ho",
  artist: "Arijit Singh", thumbnailUrl: "https://i.ytimg.com/vi/BddP6PYo2gs/hqdefault.jpg",
  note: "Our first dance", moment: "ourSong", addedBy: "alice",
  lovedBy: { alice: true }, playCount: 0, createdAt: ST, ...o,
});

const session = (o: O = {}) => ({
  songId: "s1", url: "https://www.youtube.com/watch?v=BddP6PYo2gs",
  source: "youtube", mediaId: "BddP6PYo2gs", title: "Tum Hi Ho",
  artist: "Arijit Singh", thumbnailUrl: "", status: "countdown",
  positionMs: 0, at: 1760000004000, queue: ["s2"], hostUid: "alice",
  updatedBy: "alice", listeners: { alice: 1760000000000 }, version: 1,
  updatedAt: ST, ...o,
});

useDb(async () => {
  await admin.set(`couples/${C}`, { memberIds: ["alice", "bob"], inviteCode: "ABC234" });
  await admin.set("couples/other", { memberIds: ["carol"], inviteCode: "XYZ234" });
  await admin.set(`couples/${C}/songs/s1`, song({ createdAt: ts(Date.now()) }));
});

describe("songs", () => {
  const songs = `couples/${C}/songs`;
  it("either partner adds a song; both can read it", async () => {
    await ok(as("bob").add(songs, song({ addedBy: "bob", lovedBy: { bob: true } })));
    await ok(as("alice").get(`${songs}/s1`));
  });

  it("strangers cannot read or add songs", async () => {
    await denied(as("carol").get(`${songs}/s1`));
    await denied(as("carol").add(songs, song({ addedBy: "carol", lovedBy: {} })));
  });

  it("rejects bad songs", async () => {
    const add = (o: O) => as("alice").add(songs, song(o));
    await denied(add({ addedBy: "bob" }));
    await denied(add({ url: "http://insecure.example/x" }));
    await denied(add({ url: "javascript:alert(1)" }));
    await denied(add({ source: "napster" }));
    await denied(add({ moment: "angry" }));
    await denied(add({ note: "x".repeat(501) }));
    await denied(add({ title: "x".repeat(201) }));
    await denied(add({ playCount: 5 }));
    await denied(add({ lovedBy: { carol: true } }));
    await ok(add({ thumbnailUrl: "" }));
  });

  it("edits details, love and plays, but never the link or who added it", async () => {
    const ref = `${songs}/s1`;
    const bob = as("bob");
    await ok(bob.update(ref, { title: "Tum Hi Ho (Aashiqui 2)", note: "Still ours", moment: "romantic", updatedAt: ST }));
    await ok(bob.update(ref, { "lovedBy.bob": true }));
    await ok(bob.update(ref, { "lovedBy.alice": DEL }));
    await ok(bob.update(ref, { playCount: inc(1), lastPlayedAt: ST }));
    await denied(bob.update(ref, { playCount: 50 }));
    await denied(bob.update(ref, { url: "https://youtu.be/AAAAAAAAAAA" }));
    await denied(bob.update(ref, { mediaId: "AAAAAAAAAAA" }));
    await denied(bob.update(ref, { addedBy: "bob" }));
    await denied(bob.update(ref, { "lovedBy.carol": true }));
  });

  it("either partner deletes; strangers cannot", async () => {
    await denied(as("carol").delete(`${songs}/s1`));
    await ok(as("bob").delete(`${songs}/s1`));
  });
});

describe("listening together", () => {
  const now = `couples/${C}/listening/now`;

  it("starts a session, then each change bumps the version by one", async () => {
    await ok(as("alice").set(now, session()));
    await ok(as("bob").get(now));
    // Bob pauses (version 2), Alice resumes (version 3).
    await ok(as("bob").update(now, { status: "paused", positionMs: 30000, at: 1760000034000, updatedBy: "bob", version: 2, updatedAt: ST }));
    await ok(as("alice").update(now, { status: "playing", at: 1760000040000, updatedBy: "alice", version: 3, updatedAt: ST }));
  });

  it("rejects stale or skipped versions and impersonation", async () => {
    await ok(as("alice").set(now, session()));
    await denied(as("bob").update(now, { status: "paused", updatedBy: "bob", version: 1, updatedAt: ST }));
    await denied(as("bob").update(now, { status: "paused", updatedBy: "bob", version: 5, updatedAt: ST }));
    await denied(as("bob").update(now, { status: "paused", updatedBy: "alice", version: 2, updatedAt: ST }));
    await denied(as("bob").update(now, { status: "paused", updatedBy: "bob", version: 2 }));
  });

  it("a fresh start replaces an ended session through a transaction", async () => {
    await admin.set(now, session({ status: "ended", version: 7, updatedAt: ts(Date.now()) }));
    await ok(as("bob").runTransaction(async (tx) => {
      const snap = await tx.get(now);
      tx.set(now, session({ songId: "s2", hostUid: "bob", updatedBy: "bob", listeners: { bob: 1 }, version: snap!.version + 1 }));
    }));
  });

  it("checking in touches only your own listener entry", async () => {
    await ok(as("alice").set(now, session()));
    await ok(as("bob").update(now, { "listeners.bob": 1760000001000 }));
    await ok(as("bob").update(now, { "listeners.bob": DEL }));
    await denied(as("bob").update(now, { "listeners.alice": DEL }));
    await denied(as("bob").update(now, { "listeners.bob": 1, status: "paused" }));
  });

  it("rejects malformed sessions", async () => {
    await denied(as("alice").set(now, session({ url: "http://x.y" })));
    await denied(as("alice").set(now, session({ status: "rewinding" })));
    await denied(as("alice").set(now, session({ positionMs: -5 })));
    await denied(as("alice").set(now, session({ hostUid: "carol" })));
    await denied(as("alice").set(now, session({ listeners: { carol: 1 } })));
    await denied(as("alice").set(now, session({ queue: Array.from({ length: 51 }, (_, i) => `s${i}`) })));
    await denied(as("alice").set(now, session({ songId: "" })));
  });

  it("strangers cannot read or control it; nobody deletes it", async () => {
    await ok(as("alice").set(now, session()));
    await denied(as("carol").get(now));
    await denied(as("carol").update(now, { status: "paused", updatedBy: "carol", version: 2, updatedAt: ST }));
    await denied(as("alice").delete(now));
  });

  it("clock docs: your own, server time only", async () => {
    const mine = `couples/${C}/listening/clock-alice`;
    await ok(as("alice").set(mine, { t: ST }));
    await ok(as("alice").get(mine));
    await denied(as("bob").get(mine));
    await denied(as("bob").set(mine, { t: ST }));
    await denied(as("alice").set(mine, { t: ts(0) }));
    await denied(as("alice").set(mine, { t: ST, extra: 1 }));
    await denied(as("alice").set(`couples/${C}/listening/other`, { t: ST }));
  });
});

describe("watch together", () => {
  const videos = `couples/${C}/videos`;
  const video = (o: O = {}) => song({ moment: "movieNight", ...o });
  const watching = `couples/${C}/watching/now`;

  it("saves YouTube videos only, single videos with an id", async () => {
    const add = (o: O = {}) => as("alice").add(videos, video(o));
    await ok(add());
    await ok(add({ source: "youtubeMusic", url: "https://music.youtube.com/watch?v=BddP6PYo2gs" }));
    await denied(add({ source: "spotify", url: "https://open.spotify.com/track/abc", kind: "track" }));
    await denied(add({ kind: "playlist" }));
    await denied(add({ mediaId: "" }));
    await denied(add({ addedBy: "bob" }));
    await denied(as("carol").add(videos, video({ addedBy: "carol", lovedBy: {} })));
  });

  it("edits and plays like songs; the link never changes", async () => {
    const id = await as("alice").add(videos, video());
    const bobRef = `${videos}/${id}`;
    await ok(as("bob").update(bobRef, { title: "Trailer", "lovedBy.bob": true }));
    await ok(as("bob").update(bobRef, { playCount: inc(1) }));
    await denied(as("bob").update(bobRef, { mediaId: "AAAAAAAAAAA" }));
    await ok(as("bob").delete(bobRef));
  });

  it("a watch session syncs like listening, for YouTube only", async () => {
    await denied(as("alice").set(watching, session({ source: "spotify" })));
    await denied(as("alice").set(watching, session({ mediaId: "" })));
    await ok(as("alice").set(watching, session()));
    await ok(as("bob").update(watching, { status: "paused", positionMs: 5000, updatedBy: "bob", version: 2, updatedAt: ST }));
    await denied(as("bob").update(watching, { status: "playing", updatedBy: "bob", version: 2, updatedAt: ST }));
    await ok(as("bob").update(watching, { "listeners.bob": 1 }));
    await denied(as("carol").get(watching));
    await denied(as("alice").delete(watching));
    await ok(as("bob").set(`couples/${C}/watching/clock-bob`, { t: ST }));
    await denied(as("bob").set(`couples/${C}/watching/clock-alice`, { t: ST }));
  });
});
