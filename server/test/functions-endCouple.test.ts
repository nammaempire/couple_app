// Port of functions/test/endCouple.test.js.
import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { startApp } from "./helpers.js";

const h = await import("./functions-helpers.js");
const { endCouple, DEFAULT_LEASE_MS } = await import("../src/functions/endCouple.js");

process.env.FUNCTIONS_LOG = "off";
let s: Awaited<ReturnType<typeof startApp>>;
before(async () => {
  s = await startApp();
});
after(async () => {
  await s.close();
});

describe("endCouple", () => {
  beforeEach(h.clearAll);

  it("deletes every subcollection (nested + orphaned), storage, backgrounds, invites, pairRequests and the root", async () => {
    await h.seedCouple("c1");
    await h.seedCouple("other", ["carol", "dave"]);
    assert.ok((await h.countDocsUnder("c1")) > 15);

    const r = await endCouple("c1", "agreed");
    assert.equal(r.status, "ended");
    assert.equal(r.counts!.subcollectionDocs.games, 3); // g1, g1/secret/answers, missing/secret/k1
    assert.equal(r.counts!.subcollectionDocs.songs, 2);
    assert.equal(r.counts!.subcollectionDocs["(late writes)"], undefined);
    assert.equal(r.counts!.storageFiles, 6);
    assert.equal(r.counts!.backgroundFiles, 2);
    assert.equal(r.counts!.invites, 1);
    assert.equal(r.counts!.pairRequests, 1);
    assert.equal(r.counts!.usersUpdated, 2);

    assert.equal(await h.countDocsUnder("c1"), 0);
    assert.equal(await h.exists("couples/c1/games/g1/secret/answers"), false);
    assert.equal(await h.exists("couples/c1/games/missing/secret/k1"), false);
    assert.equal(await h.exists("couples/c1"), false);
    assert.equal(await h.exists("invites/INVc1"), false);
    assert.equal(await h.exists("pairRequests/pr_c1"), false);
    assert.deepEqual(await h.listFiles("couples/c1/"), []);
    assert.deepEqual(await h.listFiles("users/alice/backgrounds/"), []);
    assert.deepEqual(await h.listFiles("users/bob/backgrounds/"), []);
    // Kept: own profile photos.
    assert.deepEqual(await h.listFiles("users/alice/profile/"), ["users/alice/profile/me.jpg"]);
    assert.deepEqual(await h.listFiles("users/bob/profile/"), ["users/bob/profile/me.jpg"]);

    // The other couple is untouched.
    assert.ok((await h.countDocsUnder("other")) > 15);
    assert.equal((await h.listFiles("couples/other/")).length, 6);
    assert.equal(await h.exists("invites/INVother"), true);
    assert.equal(await h.exists("pairRequests/pr_other"), true);
    assert.deepEqual(await h.listFiles("users/carol/backgrounds/"), ["users/carol/backgrounds/bg.jpg"]);
    assert.equal((await h.get("users/carol")).coupleId, "other");
  });

  it("clears couple fields, keeps profile fields, sets pairingEndedAt/how", async () => {
    await h.seedCouple("c1");
    const before = Date.now();
    await endCouple("c1", "oneSided");
    for (const uid of ["alice", "bob"]) {
      const u = await h.get(`users/${uid}`);
      assert.equal(u.coupleId, null);
      assert.ok("coupleId" in u, "coupleId is set to null, not removed");
      for (const k of ["chatLookMode", "chatLook", "chatClearedAt", "mutePartner"]) assert.ok(!(k in u), `${k} removed`);
      assert.equal(u.pairingEndedHow, "oneSided");
      assert.ok(h.isTimestamp(u.pairingEndedAt));
      assert.ok(h.millis(u.pairingEndedAt) >= before - 5000);
      const { displayName: _d, ...profile } = h.PROFILE;
      assert.equal(u.displayName, uid);
      for (const [k, v] of Object.entries(profile)) assert.deepEqual(u[k], v, `${k} kept`);
    }
  });

  it("is idempotent: a second run is a no-op and does not reset pairingEndedAt", async () => {
    await h.seedCouple("c1");
    await endCouple("c1", "agreed");
    // The app clears pairingEndedAt after showing the notice.
    await h.update("users/alice", { pairingEndedAt: null });
    const r2 = await endCouple("c1", "leftNow");
    assert.equal(r2.status, "alreadyEnded");
    const a = await h.get("users/alice");
    assert.equal(a.pairingEndedAt, null);
    assert.equal(a.pairingEndedHow, "agreed");
  });

  it("resumes an interrupted run (expired lease) with the original how, skipping already-unpaired users", async () => {
    await h.seedCouple("c1");
    // Simulate a crash after alice was unpaired and some data was deleted.
    await h.update("couples/c1", {
      ending: { how: "agreed", startedAt: h.ts(-h.DAY), leaseExpiresAt: h.ts(-1000), attempts: 1 },
    });
    await h.del("couples/c1/messages/a");
    await h.update("users/alice", { coupleId: null, pairingEndedAt: null, pairingEndedHow: "agreed" });
    await h.del("invites/INVc1");

    const r = await endCouple("c1", "oneSided");
    assert.equal(r.status, "ended");
    assert.equal(r.how, "agreed");
    assert.equal(r.counts!.usersUpdated, 1);
    assert.equal(r.counts!.usersSkipped, 1);
    assert.equal(r.counts!.invites, 0);
    assert.equal(r.counts!.subcollectionDocs.messages, 1);
    assert.equal(await h.exists("couples/c1"), false);
    assert.equal((await h.get("users/alice")).pairingEndedAt, null); // not re-shown
    assert.equal((await h.get("users/bob")).pairingEndedHow, "agreed");
  });

  it("does not touch a member who already re-paired with someone else", async () => {
    await h.seedCouple("c1");
    await h.update("users/alice", { coupleId: "newCouple", chatLookMode: "mine" });
    await endCouple("c1", "agreed");
    const a = await h.get("users/alice");
    assert.equal(a.coupleId, "newCouple");
    assert.equal(a.chatLookMode, "mine");
    assert.ok(!("pairingEndedAt" in a));
    assert.deepEqual(await h.listFiles("users/alice/backgrounds/"), ["users/alice/backgrounds/bg.jpg"]);
  });

  it("handles a member whose user doc is missing", async () => {
    await h.seedCouple("c1");
    await h.del("users/bob");
    const r = await endCouple("c1", "agreed");
    assert.equal(r.status, "ended");
    assert.equal(r.counts!.usersUpdated, 1);
    assert.equal(r.counts!.usersMissing, 1);
    assert.equal(await h.exists("users/bob"), false, "no doc is created");
    assert.deepEqual(await h.listFiles("users/bob/backgrounds/"), []);
  });

  it("handles a couple that is already deleted", async () => {
    const r = await endCouple("nope", "agreed");
    assert.deepEqual(r, { status: "alreadyEnded", how: undefined });
  });

  it("concurrent runs on one couple: exactly one does the work", async () => {
    await h.seedCouple("c1");
    const results = await Promise.all([endCouple("c1", "agreed"), endCouple("c1", "leftNow"), endCouple("c1", "oneSided")]);
    const statuses = results.map((r) => r.status).sort();
    assert.equal(statuses.filter((x) => x === "ended").length, 1, JSON.stringify(statuses));
    const winner = results.find((r) => r.status === "ended")!;
    assert.equal((await h.get("users/alice")).pairingEndedHow, winner.how);
    assert.equal(await h.exists("couples/c1"), false);
  });

  it("a live lease makes other callers back off without changing anything", async () => {
    await h.seedCouple("c1");
    await h.update("couples/c1", {
      ending: { how: "oneSided", startedAt: h.ts(0), leaseExpiresAt: h.ts(DEFAULT_LEASE_MS), attempts: 1 },
    });
    const r = await endCouple("c1", "leftNow");
    assert.deepEqual(r, { status: "inProgress", how: "oneSided" });
    assert.ok((await h.countDocsUnder("c1")) > 15);
    assert.equal((await h.get("users/alice")).coupleId, "c1");
  });

  it("a refusing guard changes nothing; a later takeover keeps the first how", async () => {
    await h.seedCouple("c1");
    const started = h.ts(-h.DAY);
    await h.update("couples/c1", { ending: { how: "agreed", startedAt: started, leaseExpiresAt: h.ts(-1), attempts: 2 } });
    await assert.rejects(endCouple("c1", "leftNow", { guard: () => { throw new Error("no"); } }), /no/);
    assert.equal((await h.get("couples/c1")).ending.attempts, 2);
    const r = await endCouple("c1", "leftNow");
    assert.equal(r.how, "agreed");
  });
});
