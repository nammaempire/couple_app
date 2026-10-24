// Port of firestore-tests/test/vault.rules.test.js: the end-to-end encrypted
// vault — shape and membership only, since the server never sees anything
// readable. The vault storage case belongs to the storage rules suite.
import { describe, it } from "node:test";
import { ST, admin, as, denied, fromNow, ok, ts, useDb } from "./rules-helpers.js";

type O = Record<string, unknown>;
const C = "couple1";
const meta = `couples/${C}/vault/meta`;
const items = `couples/${C}/vaultItems`;

const metaDoc = (o: O = {}) => ({
  version: 1, createdBy: "alice", createdAt: ST,
  devices: { d1: { uid: "alice", publicKey: "cHVi", name: "Pixel 8", approved: true, addedAt: ts(Date.now()) } },
  keys: { d1: { vmk: "d3JhcA==", dk: "d3JhcA==" } },
  verifier: "Y2lwaGVy", updatedBy: "alice", updatedAt: ST, ...o,
});
const item = (o: O = {}) => ({
  senderId: "alice", kind: "message", shelf: "a", ct: "Y2lwaGVy",
  photoPath: null, thumbPath: null, policy: "keep", expiresAt: null,
  viewedBy: {}, createdAt: ST, ...o,
});

useDb(async () => {
  await admin.set(`couples/${C}`, { memberIds: ["alice", "bob"], inviteCode: "ABC234" });
});

describe("vault meta", () => {
  it("a member sets it up; the partner reads, registers a phone and gets approved", async () => {
    await ok(as("alice").set(meta, metaDoc()));
    await ok(as("bob").get(meta));
    await ok(as("bob").update(meta, {
      "devices.d2": { uid: "bob", publicKey: "cHViMg==", name: "Galaxy", approved: false, addedAt: ts(Date.now()) },
      updatedBy: "bob", updatedAt: ST,
    }));
    await ok(as("alice").update(meta, {
      "devices.d2.approved": true, "keys.d2": { vmk: "eA==", dk: "eA==" },
      updatedBy: "alice", updatedAt: ST,
    }));
  });

  it("strangers cannot read or write it; shape is checked", async () => {
    await denied(as("carol").set(meta, metaDoc({ createdBy: "carol", updatedBy: "carol" })));
    await ok(as("alice").set(meta, metaDoc()));
    await denied(as("carol").get(meta));
    await denied(as("alice").update(meta, { verifier: "x".repeat(4001), updatedBy: "alice", updatedAt: ST }));
    await denied(as("alice").update(meta, { verifier: "y", updatedBy: "bob", updatedAt: ST }));
    await denied(as("alice").update(meta, { verifier: "y", updatedBy: "alice" }));
    await denied(as("bob").update(meta, { createdBy: "bob", updatedBy: "bob", updatedAt: ST }));
    await denied(as("alice").set(`couples/${C}/vault/other`, metaDoc()));
  });

  it("either partner can wipe it", async () => {
    await ok(as("alice").set(meta, metaDoc()));
    await denied(as("carol").delete(meta));
    await ok(as("bob").delete(meta));
  });
});

describe("vault items", () => {
  it("messages and photos: sent as yourself, shape checked", async () => {
    await ok(as("alice").add(items, item()));
    await ok(as("alice").add(items, item({
      kind: "photo", shelf: "b",
      photoPath: `couples/${C}/vault/p1`, thumbPath: `couples/${C}/vault/t1`,
    })));
    await denied(as("alice").add(items, item({ senderId: "bob" })));
    await denied(as("alice").add(items, item({ shelf: "real" })));
    await denied(as("alice").add(items, item({ kind: "video" })));
    await denied(as("alice").add(items, item({ ct: "" })));
    await denied(as("alice").add(items, item({ ct: "x".repeat(20001) })));
    await denied(as("alice").add(items, item({ photoPath: "couples/other/vault/p1" })));
    await denied(as("alice").add(items, item({ viewedBy: { bob: ts(Date.now()) } })));
    await denied(as("carol").add(items, item({ senderId: "carol" })));
  });

  it("24-hour items need a sensible expiry; others none", async () => {
    const in24h = fromNow(24 * 3600 * 1000);
    await ok(as("alice").add(items, item({ policy: "day", expiresAt: in24h })));
    await denied(as("alice").add(items, item({ policy: "day", expiresAt: null })));
    await denied(as("alice").add(items, item({ policy: "day", expiresAt: fromNow(30 * 86400000) })));
    await denied(as("alice").add(items, item({ policy: "keep", expiresAt: in24h })));
    await ok(as("alice").add(items, item({ policy: "once" })));
  });

  it('only your own "viewed" mark can change; either partner deletes', async () => {
    const id = await as("alice").add(items, item({ policy: "once" }));
    const bobRef = `${items}/${id}`;
    await ok(as("bob").update(bobRef, { "viewedBy.bob": ST }));
    await denied(as("bob").update(bobRef, { "viewedBy.alice": ST }));
    await denied(as("bob").update(bobRef, { ct: "dGFtcGVy" }));
    await denied(as("carol").get(bobRef));
    await ok(as("bob").delete(bobRef));
  });
});

describe("vault events", () => {
  it("alerts are written as yourself; partner reads and dismisses", async () => {
    const events = `couples/${C}/vaultEvents`;
    const ev = { type: "wrongCode", uid: "alice", deviceName: "Pixel 8", at: ST };
    const id = await ok(as("alice").add(events, ev));
    await denied(as("alice").add(events, { ...ev, uid: "bob" }));
    await denied(as("alice").add(events, { ...ev, type: "opened" }));
    await denied(as("bob").update(`${events}/${id}`, { type: "cooldown" }));
    await ok(as("bob").get(`${events}/${id}`));
    await ok(as("bob").delete(`${events}/${id}`));
  });
});
