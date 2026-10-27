/** WebRTC call setup: callSignals rules and the iceServers function. */
import { after, before, describe, it } from "node:test";
import assert from "node:assert/strict";
import { call, startApp } from "./helpers.js";

let s: Awaited<ReturnType<typeof startApp>>;
const SV = (k: string) => ({ $sv: k });

before(async () => {
  s = await startApp();
  const { commit, ADMIN } = await import("../src/store.js");
  await commit(ADMIN, {
    writes: [
      { op: "set", path: "couples/c1", data: { memberIds: ["ann", "bob"] } },
      { op: "set", path: "couples/c2", data: { memberIds: ["eve", "zed"] } },
    ],
  });
});
after(async () => {
  await s.close();
});

const signal = (from: string, to: string, extra: object = {}) => ({
  from,
  to,
  callId: "call1",
  kind: "offer",
  payload: JSON.stringify({ type: "offer", sdp: "v=0..." }),
  createdAt: SV("serverTimestamp"),
  ...extra,
});

describe("callSignals", () => {
  it("members exchange signals; the partner reads them live", async () => {
    let r = await call(s.base, "/v1/db/commit", { writes: [{ op: "create", path: "couples/c1/callSignals/s1", data: signal("ann", "bob") }] }, "ann");
    assert.equal(r.status, 200, JSON.stringify(r.json));
    r = await call(s.base, "/v1/db/commit", {
      writes: [{ op: "create", path: "couples/c1/callSignals/s2", data: signal("bob", "ann", { kind: "answer" }) }],
    }, "bob");
    assert.equal(r.status, 200, JSON.stringify(r.json));
    const q = await call(s.base, "/v1/db/query", {
      collection: "couples/c1/callSignals",
      where: [["callId", "==", "call1"], ["to", "==", "bob"]],
      orderBy: [["createdAt", "asc"]],
    }, "bob");
    assert.deepEqual(q.json.docs.map((d: any) => d.id), ["s1"]);
  });

  it("refuses spoofed senders, strangers, third parties, edits and bad kinds", async () => {
    const tries: [string, string, object][] = [
      ["bob", "s3", signal("ann", "bob")], // pretends to be ann
      ["eve", "s4", signal("eve", "ann")], // not a member
      ["ann", "s5", signal("ann", "eve")], // to someone outside the couple
      ["ann", "s6", signal("ann", "ann")], // to herself
      ["ann", "s7", signal("ann", "bob", { kind: "hack" })],
      ["ann", "s8", signal("ann", "bob", { extra: 1 })],
      ["ann", "s9", signal("ann", "bob", { payload: "x".repeat(70_000) })],
    ];
    for (const [uid, id, data] of tries) {
      const r = await call(s.base, "/v1/db/commit", { writes: [{ op: "create", path: `couples/c1/callSignals/${id}`, data }] }, uid);
      assert.equal(r.json.error?.code, "permission-denied", `${id} should be refused`);
    }
    const edit = await call(s.base, "/v1/db/commit", { writes: [{ op: "update", path: "couples/c1/callSignals/s1", data: { payload: "x" } }] }, "ann");
    assert.equal(edit.json.error?.code, "permission-denied");
    const outsider = await call(s.base, "/v1/db/query", { collection: "couples/c1/callSignals" }, "eve");
    assert.equal(outsider.json.docs.length, 0);
  });

  it("either partner can clear old signals", async () => {
    const r = await call(s.base, "/v1/db/commit", {
      writes: [
        { op: "delete", path: "couples/c1/callSignals/s1" },
        { op: "delete", path: "couples/c1/callSignals/s2" },
      ],
    }, "bob");
    assert.equal(r.status, 200, JSON.stringify(r.json));
  });
});

describe("iceServers", () => {
  it("returns STUN only when no TURN is configured", async () => {
    const r = await call(s.base, "/v1/fn/iceServers", { data: null }, "ann");
    assert.equal(r.status, 200);
    assert.equal(r.json.result.iceServers.length, 1);
    assert.match(r.json.result.iceServers[0].urls[0], /^stun:/);
  });

  it("adds short-lived TURN credentials when configured", async () => {
    const { config } = await import("../src/config.js");
    const { iceServersFor } = await import("../src/functions/ice.js");
    const { createHmac } = await import("node:crypto");
    config.turn.urls = ["turn:turn.example.com:3478"];
    config.turn.secret = "s3cret";
    try {
      const list = iceServersFor("ann", 1_000_000_000);
      assert.equal(list.length, 2);
      const t = list[1];
      assert.equal(t.username, `${1_000_000 + config.turn.ttlSeconds}:ann`);
      assert.equal(t.credential, createHmac("sha1", "s3cret").update(t.username!).digest("base64"));
    } finally {
      config.turn.urls = [];
      config.turn.secret = "";
    }
  });

  it("needs sign-in", async () => {
    const r = await call(s.base, "/v1/fn/iceServers", { data: null });
    assert.equal(r.json.error?.code, "unauthenticated");
  });
});
