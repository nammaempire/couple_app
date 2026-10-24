// Port of functions/test/functions.test.js: processSeparations, finalizeSeparation, leaveNow.
import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { startApp } from "./helpers.js";

const h = await import("./functions-helpers.js");
const { processSeparations } = await import("../src/functions/separations.js");
const { runSeparationsTick, startScheduler, SEPARATIONS_LOCK_KEY } = await import("../src/functions/scheduler.js");
const { pool } = await import("../src/db.js");

process.env.FUNCTIONS_LOG = "off";
let s: Awaited<ReturnType<typeof startApp>>;
before(async () => {
  s = await startApp();
});
after(async () => {
  await s.close();
});

const call = (name: string, uid: string | null, data: unknown) => h.fn(s.base, name, uid, data);
const tick = () => processSeparations();

const sep = (o: Record<string, unknown> = {}) => ({
  separation: {
    requestedBy: "alice",
    requestedAt: h.ts(-20 * h.DAY),
    status: "requested",
    agreedAt: null,
    declinedAt: null,
    effectiveAt: h.ts(-h.DAY),
    ...o,
  },
});
const exists = (cid: string) => h.exists(`couples/${cid}`);
const how = async (uid: string) => (await h.get(`users/${uid}`)).pairingEndedHow;

describe("processSeparations (schedule)", () => {
  beforeEach(h.clearAll);

  it("ends only due couples, with how from the status", async () => {
    await h.seedCouple("dueAgreed", ["a1", "a2"], sep({ status: "agreed", agreedAt: h.ts(-8 * h.DAY), effectiveAt: h.ts(-h.DAY) }));
    await h.seedCouple("dueRequested", ["r1", "r2"], sep({ effectiveAt: h.ts(-60 * 1000) }));
    await h.seedCouple("dueDeclined", ["d1", "d2"], sep({ status: "declined", declinedAt: h.ts(-10 * h.DAY) }));
    await h.seedCouple("future", ["f1", "f2"], sep({ effectiveAt: h.ts(h.DAY) }));
    await h.seedCouple("noSeparation", ["n1", "n2"]);

    const t = await tick();
    assert.equal(t.due, 3);
    assert.equal(t.ended, 3);

    assert.equal(await exists("dueAgreed"), false);
    assert.equal(await exists("dueRequested"), false);
    assert.equal(await exists("dueDeclined"), false);
    assert.equal(await how("a1"), "agreed");
    assert.equal(await how("r2"), "oneSided");
    assert.equal(await how("d1"), "oneSided");

    assert.equal(await exists("future"), true);
    assert.equal(await exists("noSeparation"), true);
    assert.equal((await h.get("users/f1")).coupleId, "future");
    assert.equal((await h.get("users/n1")).coupleId, "noSeparation");
    assert.equal((await h.listFiles("couples/future/")).length, 6);

    await tick(); // idempotent second tick
    assert.equal(await exists("future"), true);
  });

  it("takes at most 100 couples per tick, earliest first", async () => {
    for (let i = 0; i < 102; i++) {
      await h.set(`couples/b${String(i).padStart(3, "0")}`, { memberIds: [`u${i}`], ...sep({ effectiveAt: h.ts(-(200 - i) * 60_000) }) });
    }
    const t = await tick();
    assert.equal(t.due, 100);
    assert.equal(t.ended, 100);
    assert.equal(await exists("b000"), false);
    assert.equal(await exists("b100"), true);
    assert.equal(await exists("b101"), true);
    assert.equal((await tick()).ended, 2);
  });

  it("only one instance runs a tick (advisory lock); startScheduler returns a stop function", async () => {
    await h.seedCouple("c1", ["alice", "bob"], sep());
    const other = await pool.connect();
    try {
      await other.query("SELECT pg_advisory_lock($1)", [SEPARATIONS_LOCK_KEY]);
      assert.equal(await runSeparationsTick(), false);
      assert.equal(await exists("c1"), true);
    } finally {
      await other.query("SELECT pg_advisory_unlock($1)", [SEPARATIONS_LOCK_KEY]);
      other.release();
    }
    assert.equal(await runSeparationsTick(), true);
    assert.equal(await exists("c1"), false);

    await h.seedCouple("c2", ["carol", "dave"], sep());
    const stop = startScheduler(50);
    try {
      for (let i = 0; i < 100 && (await exists("c2")); i++) await new Promise((r) => setTimeout(r, 50));
    } finally {
      await stop();
    }
    assert.equal(await exists("c2"), false);
  });
});

describe("finalizeSeparation (callable)", () => {
  beforeEach(h.clearAll);

  it("requires auth", async () => {
    await h.seedCouple("c1", ["alice", "bob"], sep());
    const e = await h.rejectsWith(call("finalizeSeparation", null, { coupleId: "c1" }), "unauthenticated");
    assert.equal(e.status, 401);
  });

  it("rejects a bad coupleId", async () => {
    await h.rejectsWith(call("finalizeSeparation", "alice", {}), "invalid-argument");
    await h.rejectsWith(call("finalizeSeparation", "alice", { coupleId: "a/b" }), "invalid-argument");
    await h.rejectsWith(call("finalizeSeparation", "alice", null), "invalid-argument");
  });

  it("rejects a non-member", async () => {
    await h.seedCouple("c1", ["alice", "bob"], sep());
    const e = await h.rejectsWith(call("finalizeSeparation", "mallory", { coupleId: "c1" }), "permission-denied");
    assert.equal(e.status, 403);
    assert.equal(await exists("c1"), true);
  });

  it('rejects before effectiveAt ("not yet") with details.effectiveAt', async () => {
    const at = h.ts(3 * h.DAY);
    await h.seedCouple("c1", ["alice", "bob"], sep({ effectiveAt: at }));
    const e = await h.rejectsWith(call("finalizeSeparation", "alice", { coupleId: "c1" }), "failed-precondition", /not yet/i);
    assert.deepEqual(e.details, { effectiveAt: at.$ts });
    assert.equal(await exists("c1"), true);
    assert.equal((await h.get("couples/c1")).ending, undefined, "no lease left behind");
  });

  it("rejects when there is no separation", async () => {
    await h.seedCouple("c1");
    await h.rejectsWith(call("finalizeSeparation", "bob", { coupleId: "c1" }), "failed-precondition");
  });

  it("ends a due couple for a member, then reports alreadyEnded", async () => {
    await h.seedCouple("c1", ["alice", "bob"], sep({ status: "agreed", agreedAt: h.ts(-8 * h.DAY) }));
    assert.deepEqual(await call("finalizeSeparation", "bob", { coupleId: "c1" }), { status: "ended", how: "agreed" });
    assert.equal(await exists("c1"), false);
    assert.equal(await how("alice"), "agreed");
    assert.deepEqual(await call("finalizeSeparation", "bob", { coupleId: "c1" }), { status: "alreadyEnded", how: null });
  });
});

describe("leaveNow (callable)", () => {
  beforeEach(h.clearAll);

  it("requires auth", async () => {
    await h.seedCouple("c1");
    await h.rejectsWith(call("leaveNow", null, { coupleId: "c1", confirm: "LEAVE" }), "unauthenticated");
  });

  it('requires confirm === "LEAVE"', async () => {
    await h.seedCouple("c1");
    await h.rejectsWith(call("leaveNow", "alice", { coupleId: "c1" }), "invalid-argument");
    await h.rejectsWith(call("leaveNow", "alice", { coupleId: "c1", confirm: "leave" }), "invalid-argument");
    assert.equal(await exists("c1"), true);
  });

  it("rejects a non-member", async () => {
    await h.seedCouple("c1");
    await h.rejectsWith(call("leaveNow", "mallory", { coupleId: "c1", confirm: "LEAVE" }), "permission-denied");
    assert.equal(await exists("c1"), true);
  });

  it("ends immediately without any separation", async () => {
    await h.seedCouple("c1");
    assert.deepEqual(await call("leaveNow", "alice", { coupleId: "c1", confirm: "LEAVE" }), { status: "ended", how: "leftNow" });
    assert.equal(await exists("c1"), false);
    assert.equal(await how("alice"), "leftNow");
    assert.equal(await how("bob"), "leftNow");
  });

  it("ends immediately even when a separation is still in the future", async () => {
    await h.seedCouple("c1", ["alice", "bob"], sep({ effectiveAt: h.ts(10 * h.DAY) }));
    assert.equal((await call("leaveNow", "bob", { coupleId: "c1", confirm: "LEAVE" })).status, "ended");
    assert.equal(await how("alice"), "leftNow");
  });

  it("unknown function names are not-found", async () => {
    await h.rejectsWith(call("nope", "alice", {}), "not-found");
  });
});
