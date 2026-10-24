import { after, before, describe, it } from "node:test";
import assert from "node:assert/strict";
import WebSocket from "ws";
import { call, startApp } from "./helpers.js";

// A simple rule set for exercising the engine: users may read/write their own
// profile; couple members may read/write couple messages; nothing else.
const { setRules } = await import("../src/store.js");
const E = await import("../src/rules/engine.js");
setRules([
  {
    pattern: "users/{userId}",
    read: (c) => E.uid(c) === c.params.userId,
    write: (c) => E.uid(c) === c.params.userId,
  },
  {
    pattern: "couples/{coupleId}",
    read: async (c) => E.inList(E.uid(c), (await E.getData(c, c.path)).memberIds),
    create: (c) => E.inList(E.uid(c), E.newData(c).memberIds),
    update: (c) => E.inList(E.uid(c), E.oldData(c).memberIds),
  },
  {
    pattern: "couples/{coupleId}/messages/{messageId}",
    read: async (c) => E.inList(E.uid(c), (await E.getData(c, `couples/${c.params.coupleId}`)).memberIds),
    create: async (c) =>
      E.inList(E.uid(c), (await E.getAfterData(c, `couples/${c.params.coupleId}`)).memberIds) &&
      E.newData(c).senderId === E.uid(c) &&
      E.isRequestTime(c, E.newData(c).sentAt),
    update: async (c) =>
      E.inList(E.uid(c), (await E.getData(c, `couples/${c.params.coupleId}`)).memberIds) &&
      E.hasOnly(E.changedKeys(c), ["reactions", "pinned", "count"]),
    delete: async (c) => E.oldData(c).senderId === E.uid(c),
  },
]);

let s: Awaited<ReturnType<typeof startApp>>;
before(async () => {
  s = await startApp();
});
after(async () => {
  await s.close();
});

const SV = (k: string, extra: object = {}) => ({ $sv: k, ...extra });

describe("documents", () => {
  it("creates a couple and its first message in one commit (getAfter)", async () => {
    const r = await call(s.base, "/v1/db/commit", {
      writes: [
        { op: "set", path: "couples/c1", data: { memberIds: ["a", "b"], name: "Us" } },
        { op: "create", path: "couples/c1/messages/m1", data: { senderId: "a", text: "hi", sentAt: SV("serverTimestamp") } },
      ],
    }, "a");
    assert.equal(r.status, 200, JSON.stringify(r.json));
    const g = await call(s.base, "/v1/db/get", { paths: ["couples/c1/messages/m1"] }, "b");
    assert.equal(g.status, 200);
    const doc = g.json.docs[0];
    assert.equal(doc.exists, true);
    assert.equal(doc.data.text, "hi");
    assert.equal(doc.data.sentAt.$ts, r.json.commitTime);
  });

  it("denies outsiders and wrong senders", async () => {
    const g = await call(s.base, "/v1/db/get", { paths: ["couples/c1/messages/m1"] }, "z");
    assert.equal(g.status, 403);
    assert.equal(g.json.error.code, "permission-denied");
    const w = await call(s.base, "/v1/db/commit", {
      writes: [{ op: "create", path: "couples/c1/messages/m2", data: { senderId: "a", text: "x", sentAt: SV("serverTimestamp") } }],
    }, "b");
    assert.equal(w.status, 403);
    const noAuth = await call(s.base, "/v1/db/get", { paths: ["users/a"] });
    assert.equal(noAuth.status, 401);
  });

  it("merge, dotted update, increment, arrayUnion, delete sentinel", async () => {
    let r = await call(s.base, "/v1/db/commit", { writes: [{ op: "set", path: "users/a", data: { name: "A", prefs: { x: 1, y: 2 }, tags: ["p"] } }] }, "a");
    assert.equal(r.status, 200, JSON.stringify(r.json));
    r = await call(s.base, "/v1/db/commit", { writes: [{ op: "set", path: "users/a", merge: true, data: { prefs: { y: 3, z: 4 }, n: SV("increment", { by: 2 }) } }] }, "a");
    assert.equal(r.status, 200);
    r = await call(s.base, "/v1/db/commit", {
      writes: [{ op: "update", path: "users/a", data: { "prefs.x": SV("delete"), tags: SV("arrayUnion", { values: ["p", "q"] }), n: SV("increment", { by: 1 }) } }],
    }, "a");
    assert.equal(r.status, 200);
    const g = await call(s.base, "/v1/db/get", { paths: ["users/a"] }, "a");
    assert.deepEqual(g.json.docs[0].data, { name: "A", prefs: { y: 3, z: 4 }, tags: ["p", "q"], n: 3 });
  });

  it("update of a missing doc is not-found; create of an existing doc is already-exists", async () => {
    let r = await call(s.base, "/v1/db/commit", { writes: [{ op: "update", path: "users/nope", data: { a: 1 } }] }, "nope");
    assert.equal(r.json.error.code, "not-found");
    r = await call(s.base, "/v1/db/commit", { writes: [{ op: "create", path: "users/a", data: {} }] }, "a");
    assert.equal(r.json.error.code, "already-exists");
  });

  it("queries with where / orderBy / limit, hiding unreadable docs", async () => {
    for (let i = 0; i < 5; i++) {
      const r = await call(s.base, "/v1/db/commit", {
        writes: [{ op: "create", path: `couples/c1/messages/q${i}`, data: { senderId: "a", n: i, kind: i % 2 ? "odd" : "even", sentAt: SV("serverTimestamp") } }],
      }, "a");
      assert.equal(r.status, 200);
    }
    const q = await call(s.base, "/v1/db/query", {
      collection: "couples/c1/messages",
      where: [["kind", "==", "even"]],
      orderBy: [["n", "desc"]],
      limit: 2,
    }, "b");
    assert.equal(q.status, 200, JSON.stringify(q.json));
    assert.deepEqual(q.json.docs.map((d: any) => d.data.n), [4, 2]);
    const inQ = await call(s.base, "/v1/db/query", { collection: "couples/c1/messages", where: [["n", "in", [1, 3]]] }, "a");
    assert.equal(inQ.json.docs.length, 2);
    const le = await call(s.base, "/v1/db/query", { collection: "couples/c1/messages", where: [["n", "<=", 1]] }, "a");
    assert.equal(le.json.docs.length, 2);
    const byTime = await call(s.base, "/v1/db/query", { collection: "couples/c1/messages", orderBy: [["sentAt", "desc"]], limit: 1 }, "a");
    assert.equal(byTime.json.docs[0].id, "q4");
    const outsider = await call(s.base, "/v1/db/query", { collection: "couples/c1/messages" }, "z");
    assert.equal(outsider.json.docs.length, 0);
    const n = await call(s.base, "/v1/db/count", { collection: "couples/c1/messages", where: [["kind", "==", "odd"]] }, "a");
    assert.equal(n.json.count, 2);
  });

  it("transactions abort when a read document changed", async () => {
    const g = await call(s.base, "/v1/db/get", { paths: ["couples/c1/messages/q0"] }, "a");
    const v = g.json.docs[0].version;
    let r = await call(s.base, "/v1/db/commit", {
      reads: [{ path: "couples/c1/messages/q0", version: v }],
      writes: [{ op: "update", path: "couples/c1/messages/q0", data: { count: 1 } }],
    }, "a");
    assert.equal(r.status, 200, JSON.stringify(r.json));
    r = await call(s.base, "/v1/db/commit", {
      reads: [{ path: "couples/c1/messages/q0", version: v }],
      writes: [{ op: "update", path: "couples/c1/messages/q0", data: { count: 2 } }],
    }, "a");
    assert.equal(r.json.error.code, "aborted");
    // Reading a missing doc (version 0) then creating it.
    r = await call(s.base, "/v1/db/commit", {
      reads: [{ path: "couples/c1/messages/new1", version: 0 }],
      writes: [{ op: "set", path: "couples/c1/messages/new1", data: { senderId: "a", sentAt: SV("serverTimestamp") } }],
    }, "a");
    assert.equal(r.status, 200, JSON.stringify(r.json));
  });

  it("rejects unknown paths and bad values", async () => {
    let r = await call(s.base, "/v1/db/get", { paths: ["nope/x"] }, "a");
    assert.equal(r.json.error.code, "invalid-argument");
    r = await call(s.base, "/v1/db/commit", { writes: [{ op: "set", path: "users/a", data: { $bad: 1 } }] }, "a");
    assert.equal(r.json.error.code, "invalid-argument");
  });
});

describe("realtime", () => {
  it("pushes snapshots for queries and docs, and updates on change", async () => {
    const ws = new WebSocket(s.ws);
    const msgs: any[] = [];
    const waitFor = (pred: (m: any) => boolean, ms = 3000) =>
      new Promise<any>((resolve, reject) => {
        const found = msgs.find(pred);
        if (found) return resolve(found);
        const t = setTimeout(() => reject(new Error("timeout; got " + JSON.stringify(msgs))), ms);
        ws.on("message", function h(raw) {
          const m = JSON.parse(String(raw));
          if (pred(m)) {
            clearTimeout(t);
            ws.off("message", h);
            resolve(m);
          }
        });
      });
    ws.on("message", (raw) => msgs.push(JSON.parse(String(raw))));
    await new Promise((r) => ws.on("open", r));
    ws.send(JSON.stringify({ t: "auth", token: "test:b" }));
    await waitFor((m) => m.t === "ready");
    ws.send(JSON.stringify({ t: "sub", id: "q", query: { collection: "couples/c1/messages", orderBy: [["sentAt", "desc"]], limit: 3 } }));
    ws.send(JSON.stringify({ t: "sub", id: "d", doc: "couples/c1/messages/live1" }));
    const first = await waitFor((m) => m.t === "snap" && m.id === "q");
    assert.equal(first.docs.length, 3);
    const d0 = await waitFor((m) => m.t === "snap" && m.id === "d");
    assert.equal(d0.doc.exists, false);
    msgs.length = 0;
    const r = await call(s.base, "/v1/db/commit", {
      writes: [{ op: "create", path: "couples/c1/messages/live1", data: { senderId: "a", text: "live", sentAt: SV("serverTimestamp") } }],
    }, "a");
    assert.equal(r.status, 200);
    const q2 = await waitFor((m) => m.t === "snap" && m.id === "q");
    assert.equal(q2.docs[0].id, "live1");
    const d1 = await waitFor((m) => m.t === "snap" && m.id === "d");
    assert.equal(d1.doc.data.text, "live");
    // Outsider subscription gets an error.
    ws.send(JSON.stringify({ t: "sub", id: "bad", doc: "users/a" }));
    const err = await waitFor((m) => m.t === "error" && m.id === "bad");
    assert.equal(err.code, "permission-denied");
    ws.close();
  });
});
