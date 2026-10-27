/**
 * Push notifications: who is notified, wording, prefs, mute, quiet hours,
 * dead tokens, and the pushTokens rules. FCM is replaced by a fake sender.
 */
import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { call, startApp } from "./helpers.js";

let s: Awaited<ReturnType<typeof startApp>>;
const sent: { tokens: string[]; message: any }[] = [];
let deadTokens: string[] = [];

const SV = (k: string) => ({ $sv: k });
const wait = () => new Promise((r) => setTimeout(r, 150));

before(async () => {
  s = await startApp();
  const { setPushSender } = await import("../src/push/fcm.js");
  setPushSender({
    async send(tokens, message) {
      sent.push({ tokens, message });
      return tokens.filter((t) => deadTokens.includes(t));
    },
  });
  const { commit, ADMIN } = await import("../src/store.js");
  await commit(ADMIN, {
    writes: [
      { op: "set", path: "couples/c1", data: { memberIds: ["ann", "bob"], nicknames: { bob: "Annu" } } },
      { op: "set", path: "users/ann", data: { displayName: "Ann", coupleId: "c1" } },
      { op: "set", path: "users/bob", data: { displayName: "Bob", coupleId: "c1" } },
    ],
  });
});
after(async () => {
  await s.close();
});
beforeEach(() => {
  sent.length = 0;
  deadTokens = [];
});

async function registerToken(uid: string, token: string, timeZone: string | null = "Asia/Kolkata") {
  const r = await call(s.base, "/v1/db/commit", {
    writes: [{ op: "set", path: `users/${uid}/pushTokens/${token}`, data: { token, platform: "android", timeZone, updatedAt: SV("serverTimestamp") } }],
  }, uid);
  assert.equal(r.status, 200, JSON.stringify(r.json));
}

describe("push tokens", () => {
  it("only the owner can write or read them", async () => {
    await registerToken("bob", "tok-bob");
    const other = await call(s.base, "/v1/db/commit", {
      writes: [{ op: "set", path: "users/bob/pushTokens/x", data: { token: "x", platform: "android", timeZone: null, updatedAt: SV("serverTimestamp") } }],
    }, "ann");
    assert.equal(other.json.error?.code, "permission-denied");
    const read = await call(s.base, "/v1/db/get", { paths: ["users/bob/pushTokens/tok-bob"] }, "ann");
    assert.equal(read.json.error?.code, "permission-denied");
    const bad = await call(s.base, "/v1/db/commit", {
      writes: [{ op: "set", path: "users/bob/pushTokens/y", data: { token: "y", platform: "android", extra: 1, updatedAt: SV("serverTimestamp") } }],
    }, "bob");
    assert.equal(bad.json.error?.code, "permission-denied");
  });
});

describe("triggers", () => {
  it("a love tap buzzes the partner, with the name they use", async () => {
    await registerToken("bob", "tok-bob");
    const r = await call(s.base, "/v1/db/commit", {
      writes: [{ op: "create", path: "couples/c1/nudges/n1", data: { senderId: "ann", sentAt: SV("serverTimestamp"), kind: "hug" } }],
    }, "ann");
    assert.equal(r.status, 200, JSON.stringify(r.json));
    await wait();
    assert.equal(sent.length, 1);
    assert.deepEqual(sent[0].tokens, ["tok-bob"]);
    assert.equal(sent[0].message.notification.title, "Annu sent you a hug 🤗");
    assert.equal(sent[0].message.android.notification.channelId, "love");
    assert.equal(sent[0].message.data.kind, "love");
  });

  it("the sender is never notified about their own action", async () => {
    await registerToken("ann", "tok-ann");
    const { pushAfterCommit } = await import("../src/push/triggers.js");
    await pushAfterCommit("ann", [{ path: "couples/c1/nudges/n2", before: null, after: { senderId: "ann", kind: "love" } }]);
    assert.ok(sent.every((x) => !x.tokens.includes("tok-ann")));
  });

  it("messages, calls, moods, notes and the daily question", async () => {
    const { pushAfterCommit } = await import("../src/push/triggers.js");
    await registerToken("bob", "tok-bob");
    const future = { $ts: new Date(Date.now() + 3 * 86400_000).toISOString() };
    await pushAfterCommit("ann", [
      { path: "couples/c1/messages/m1", before: null, after: { senderId: "ann", type: "text", text: "Dinner at 8?" } },
      { path: "couples/c1/messages/m2", before: null, after: { senderId: "ann", type: "image" } },
      { path: "couples/c1/messages/m3", before: null, after: { senderId: "ann", type: "call" } },
      { path: "couples/c1/call/k1", before: null, after: { callerId: "ann", status: "ringing", type: "video" } },
      { path: "couples/c1/moods/ann", before: { mood: "calm" }, after: { mood: "happy" } },
      { path: "couples/c1/notes/no1", before: null, after: { senderId: "ann", recipientId: "bob", deliverAt: future } },
      { path: "couples/c1/dailyQuestions/2026-10-26", before: null, after: { answers: { ann: { text: "x" } } } },
    ]);
    const titles = sent.map((x) => [x.message.notification.title, x.message.notification.body, x.message.android.notification.channelId]);
    assert.deepEqual(titles[0], ["Annu", "Dinner at 8?", "messages"]);
    assert.deepEqual(titles[1], ["Annu", "📷 Photo", "messages"]);
    // the call log line (m3) is not pushed
    assert.deepEqual(titles[2], ["Annu", "📹 Incoming video call", "calls"]);
    assert.equal(sent[2].message.android.ttl, 30_000);
    assert.deepEqual(titles[3].slice(0, 1), ["Annu is feeling happy 😊"]);
    assert.equal(titles[4][0], "💌 Annu sealed a love note for you");
    assert.match(titles[4][1], /^It opens /);
    assert.deepEqual(titles[5], ["Annu answered today's question", "Your turn! ✍️", "updates"]);
    assert.equal(sent.length, 6);
  });

  it("respects prefs, mute and quiet hours; calls still ring", async () => {
    const { pushAfterCommit } = await import("../src/push/triggers.js");
    const { commit, ADMIN } = await import("../src/store.js");
    // A time zone where it's night right now.
    const nightZone = ["Asia/Kolkata", "America/New_York", "Asia/Tokyo", "Europe/London", "America/Los_Angeles", "Australia/Sydney"].find((tz) => {
      const h = Number(new Intl.DateTimeFormat("en-GB", { hour: "numeric", hourCycle: "h23", timeZone: tz }).format(new Date()));
      return h >= 22 || h < 7;
    })!;
    await registerToken("bob", "tok-bob", nightZone);
    await commit(ADMIN, { writes: [{ op: "update", path: "users/bob", data: { notificationPrefs: { messages: false, quietHours: true } } }] });
    await pushAfterCommit("ann", [
      { path: "couples/c1/messages/m9", before: null, after: { senderId: "ann", type: "text", text: "hi" } },
      { path: "couples/c1/nudges/n9", before: null, after: { senderId: "ann", kind: "kiss" } },
      { path: "couples/c1/call/k9", before: null, after: { callerId: "ann", status: "ringing", type: "voice" } },
    ]);
    assert.equal(sent.length, 2, "message muted by prefs");
    assert.equal(sent[0].message.android.notification.channelId, "quiet");
    assert.equal(sent[1].message.android.notification.channelId, "calls");
    sent.length = 0;
    await commit(ADMIN, { writes: [{ op: "update", path: "users/bob", data: { mutePartner: true } }] });
    await pushAfterCommit("ann", [{ path: "couples/c1/nudges/n10", before: null, after: { senderId: "ann", kind: "kiss" } }]);
    assert.equal(sent.length, 0);
    await commit(ADMIN, { writes: [{ op: "update", path: "users/bob", data: { mutePartner: false, notificationPrefs: {} } }] });
  });

  it("every new call rings, even though the call document is reused", async () => {
    const { pushAfterCommit } = await import("../src/push/triggers.js");
    await registerToken("bob", "tok-bob");
    const ended = { callerId: "ann", status: "ended", type: "voice", channelName: "old" };
    await pushAfterCommit("ann", [
      { path: "couples/c1/call/current", before: ended, after: { callerId: "ann", status: "ringing", type: "voice", channelName: "new1" } },
      // the same ringing call written again: no second push
      { path: "couples/c1/call/current", before: { callerId: "ann", status: "ringing", channelName: "new1" }, after: { callerId: "ann", status: "ringing", channelName: "new1" } },
      // the callee answering: no push
      { path: "couples/c1/call/current", before: { callerId: "ann", status: "ringing", channelName: "new1" }, after: { callerId: "ann", status: "accepted", channelName: "new1" } },
    ]);
    assert.equal(sent.length, 1);
    assert.equal(sent[0].message.android.notification.channelId, "calls");
    assert.equal(sent[0].message.data.callId, "new1");
  });

  it("dead tokens are removed", async () => {
    const { pushAfterCommit } = await import("../src/push/triggers.js");
    await registerToken("bob", "tok-dead");
    deadTokens = ["tok-dead"];
    await pushAfterCommit("ann", [{ path: "couples/c1/nudges/n11", before: null, after: { senderId: "ann", kind: "love" } }]);
    const { adminGet } = await import("../src/store.js");
    const { pool } = await import("../src/db.js");
    assert.equal((await adminGet(pool, "users/bob/pushTokens/tok-dead")).exists, false);
  });
});
