/**
 * Regression tests for the independent security review (real rules, real
 * Postgres): query oracles, prototype pollution, regex blow-up, realtime
 * robustness, transaction-read and precondition oracles, concurrent creates,
 * file-delete oracle.
 */
import { after, before, describe, it } from "node:test";
import assert from "node:assert/strict";
import WebSocket from "ws";
import { call, startApp } from "./helpers.js";

let s: Awaited<ReturnType<typeof startApp>>;
before(async () => {
  s = await startApp();
  const { commit, ADMIN } = await import("../src/store.js");
  await commit(ADMIN, {
    writes: [
      { op: "set", path: "couples/victimC", data: { memberIds: ["vic"], inviteCode: "K7Q2", lastMessage: { text: "secret" } } },
      { op: "set", path: "users/vic", data: { name: "Victim", email: "victim@example.com", coupleId: "victimC" } },
      { op: "set", path: "couples/attC", data: { memberIds: ["att"], inviteCode: "￿", lastMessage: { text: "￿" } } },
      { op: "set", path: "users/att", data: { name: "A", email: "￿", coupleId: "attC" } },
    ],
  });
});
after(async () => {
  await s.close();
});

describe("query oracle", () => {
  it("hidden documents don't affect results, ordering or limits", async () => {
    // With the old 'limit then filter', an empty answer meant a hidden doc sorted first.
    for (const x of [" ", "A", "K", "K7Q2", "Z"]) {
      const q = await call(s.base, "/v1/db/query", {
        collection: "couples",
        where: [["inviteCode", ">=", x]],
        orderBy: [["inviteCode", "asc"]],
        limit: 1,
      }, "att");
      assert.equal(q.status, 200, JSON.stringify(q.json));
      assert.deepEqual(q.json.docs.map((d: any) => d.id), ["attC"], `probe ${x}`);
    }
    const u = await call(s.base, "/v1/db/query", { collection: "users", orderBy: [["email", "asc"]], limit: 1 }, "att");
    assert.deepEqual(u.json.docs.map((d: any) => d.id), ["att"]);
  });
});

describe("prototype pollution", () => {
  it("rejects __proto__ / constructor / prototype in field paths and keys", async () => {
    for (const data of [{ "__proto__.phone_number": "+919999999999" }, { "a.constructor.x": 1 }, { "prototype": 1 }]) {
      const r = await call(s.base, "/v1/db/commit", { writes: [{ op: "update", path: "users/att", data }] }, "att");
      assert.equal(r.json.error?.code, "invalid-argument", JSON.stringify(data));
    }
    const raw = await fetch(s.base + "/v1/db/commit", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: "Bearer test:att" },
      body: '{"writes":[{"op":"set","path":"users/att","merge":true,"data":{"x":{"__proto__":{"polluted":1}}}}]}',
    });
    assert.notEqual(raw.status, 200);
    assert.equal(({} as Record<string, unknown>).polluted, undefined);
    assert.equal(({} as Record<string, unknown>).phone_number, undefined);
  });
});

describe("regex blow-up", () => {
  it("a crafted couple id can't hang the vault path check", async () => {
    const cid = "a+".repeat(20) + "b";
    const t = Date.now();
    await call(s.base, "/v1/db/commit", {
      writes: [{ op: "create", path: `couples/${cid}/vaultItems/i1`, data: { photoPath: "couples/" + "a".repeat(60) } }],
    }, "att");
    assert.ok(Date.now() - t < 2000, "took too long");
  });
});

describe("transaction reads and preconditions", () => {
  it("can't probe existence or versions of unreadable docs", async () => {
    const r1 = await call(s.base, "/v1/db/commit", { writes: [], reads: [{ path: "couples/victimC", version: 0 }] }, "att");
    const r2 = await call(s.base, "/v1/db/commit", { writes: [], reads: [{ path: "couples/nope", version: 0 }] }, "att");
    assert.equal(r1.json.error?.code, "permission-denied");
    assert.equal(r2.json.error?.code, r1.json.error?.code);
    const c1 = await call(s.base, "/v1/db/commit", { writes: [{ op: "create", path: "couples/victimC", data: {} }] }, "att");
    const c2 = await call(s.base, "/v1/db/commit", { writes: [{ op: "update", path: "couples/nope", data: {} }] }, "att");
    assert.equal(c1.json.error?.code, "permission-denied");
    assert.equal(c2.json.error?.code, "permission-denied");
  });

  it("concurrent creates of the same doc: exactly one wins", async () => {
    const { setRules, commit } = await import("../src/store.js");
    const { firestoreRules } = await import("../src/rules/firestore.js");
    setRules([{ pattern: "couples/{c}/nudges/{n}", create: (c) => !!c.auth }, ...firestoreRules]);
    try {
      for (let round = 0; round < 5; round++) {
        const path = `couples/attC/nudges/race${round}`;
        const results = await Promise.allSettled(
          Array.from({ length: 8 }, (_, i) =>
            commit({ kind: "user", auth: { uid: "att", token: {} } }, { writes: [{ op: "create", path, data: { i } }] }),
          ),
        );
        assert.equal(results.filter((r) => r.status === "fulfilled").length, 1, `round ${round}`);
      }
    } finally {
      setRules(firestoreRules);
    }
  });
});

describe("realtime robustness", () => {
  it("survives junk messages and bad subscriptions", async () => {
    const ws = new WebSocket(s.ws);
    await new Promise((r) => ws.on("open", r));
    const msgs: any[] = [];
    ws.on("message", (raw) => msgs.push(JSON.parse(String(raw))));
    for (const junk of ["null", "42", "[]", '"x"', "{", '{"t":"sub","id":"a","query":{}}', '{"t":"sub","id":"b","doc":123}']) ws.send(junk);
    ws.send(JSON.stringify({ t: "auth", token: "test:att" }));
    await new Promise((r) => setTimeout(r, 300));
    assert.ok(msgs.some((m) => m.t === "ready"));
    assert.ok(msgs.filter((m) => m.t === "error" && (m.id === "a" || m.id === "b")).length === 2);
    // Still serving: a real subscription works.
    ws.send(JSON.stringify({ t: "sub", id: "ok", doc: "users/att" }));
    await new Promise((r) => setTimeout(r, 300));
    assert.ok(msgs.some((m) => m.t === "snap" && m.id === "ok"));
    ws.close();
    const health = await fetch(s.base + "/health");
    assert.equal(health.status, 200);
  });
});

describe("files", () => {
  it("delete of a missing file in someone else's couple is permission-denied, not not-found", async () => {
    const r = await fetch(s.base + "/v1/files/couples/victimC/photos/nope.jpg", {
      method: "DELETE",
      headers: { authorization: "Bearer test:att" },
    });
    assert.equal(r.status, 403);
  });

  it("unknown server functions don't resolve inherited names", async () => {
    const r = await call(s.base, "/v1/fn/constructor", { data: null }, "att");
    assert.equal(r.json.error?.code, "not-found");
  });
});
