// Port of firestore-tests/test/pairing-separation.rules.test.js: mobile-number
// pairing (phoneIndex, pairRequests) and ending a pairing
// (couples/{id}.separation), with the vault closed while it ends.
import { describe, it } from "node:test";
import { DAY, DEL, ST, admin, as, assert, denied, fromNow, hidden, ok, ts, useDb } from "./rules-helpers.js";

type O = Record<string, unknown>;
const C = "couple1";
const couple = `couples/${C}`;
const at = fromNow;
const phone = (uid: string, n: string) => as(uid, { phone_number: n });

const request = (o: O = {}) => ({
  requestedBy: "alice", requestedAt: ST, status: "requested",
  agreedAt: null, declinedAt: null, effectiveAt: at(14 * DAY), ...o,
});

useDb(async () => {
  await admin.set(couple, { memberIds: ["alice", "bob"], inviteCode: "ABC234" });
  await admin.set("couples/solo", { memberIds: ["carol"], inviteCode: "SOLO23" });
  await admin.set("users/alice", { displayName: "Alice", coupleId: C });
  await admin.set("users/carol", { displayName: "Carol", coupleId: "solo" });
  await admin.set(`couples/${C}/vault/meta`, { version: 1 });
});

describe("phone numbers", () => {
  it("only the verified owner claims a number; anyone signed in can look one up, nobody can list", async () => {
    await ok(phone("alice", "+919876543210").set("phoneIndex/+919876543210", { uid: "alice", createdAt: ST }));
    await denied(phone("bob", "+919000000001").set("phoneIndex/+919876543210", { uid: "bob", createdAt: ST }));
    await denied(as("dave").set("phoneIndex/+919111111111", { uid: "dave", createdAt: ST }));
    await denied(phone("alice", "+919876543210").set("phoneIndex/+919876543210", { uid: "bob", createdAt: ST }));
    await ok(as("carol").get("phoneIndex/+919876543210"));
    // Firestore refuses the list; here it returns no documents.
    await hidden(as("carol").query({ collection: "phoneIndex" }));
  });

  it("a recycled number moves to whoever verifies it now", async () => {
    await ok(phone("alice", "+919876543210").set("phoneIndex/+919876543210", { uid: "alice", createdAt: ST }));
    await ok(phone("erin", "+919876543210").set("phoneIndex/+919876543210", { uid: "erin", createdAt: ST }));
  });

  it("a profile phone must be the verified one; mute is a bool; ended-markers can only be cleared", async () => {
    await ok(phone("alice", "+919876543210").update("users/alice", { phone: "+919876543210", mutePartner: true }));
    await denied(phone("alice", "+919876543210").update("users/alice", { phone: "+919000000000" }));
    await denied(as("alice").update("users/alice", { mutePartner: "yes" }));
    await denied(as("alice").update("users/alice", { pairingEndedAt: ST }));
    await admin.update("users/alice", { pairingEndedAt: ts(Date.now()), pairingEndedHow: "agreed" });
    await denied(as("alice").update("users/alice", { pairingEndedHow: "leftNow" }));
    await ok(as("alice").update("users/alice", { pairingEndedAt: DEL, pairingEndedHow: DEL }));
  });
});

describe("pair requests", () => {
  const req = (o: O = {}) => ({
    fromUid: "carol", fromName: "Carol", fromPhone: "+919000000003", toUid: "dave",
    toPhone: "+919000000004", coupleId: "solo", inviteCode: "SOLO23",
    status: "pending", createdAt: ST, ...o,
  });

  it("sent from your own couple of one, with its real code", async () => {
    await ok(as("carol").add("pairRequests", req()));
    await ok(as("carol").add("pairRequests", req({ fromPhone: "" })));
    await denied(as("carol").add("pairRequests", req({ inviteCode: "WRONG1" })));
    await denied(as("carol").add("pairRequests", req({ fromUid: "dave" })));
    await denied(as("carol").add("pairRequests", req({ toUid: "carol" })));
    await denied(as("carol").add("pairRequests", req({ status: "accepted" })));
    await denied(as("carol").add("pairRequests", req({ toPhone: "98765" })));
    // Alice is already in a couple of two: she can't offer it.
    await denied(as("alice").add("pairRequests", req({ fromUid: "alice", coupleId: C, inviteCode: "ABC234" })));
  });

  it("only the two people involved see it; the receiver answers, the sender cancels, once", async () => {
    const r = await as("carol").add("pairRequests", req());
    const inbox = await ok(as("dave").query({ collection: "pairRequests", where: [["toUid", "==", "dave"], ["status", "==", "pending"]] }));
    assert.equal(inbox.length, 1);
    await denied(as("erin").get(`pairRequests/${r}`));
    await denied(as("carol").update(`pairRequests/${r}`, { status: "accepted" }));
    await denied(as("dave").update(`pairRequests/${r}`, { status: "accepted", toUid: "erin" }));
    await ok(as("dave").update(`pairRequests/${r}`, { status: "declined" }));
    await denied(as("dave").update(`pairRequests/${r}`, { status: "accepted" }));
    const r2 = await as("carol").add("pairRequests", req());
    await ok(as("carol").update(`pairRequests/${r2}`, { status: "cancelled" }));
    await denied(as("dave").delete(`pairRequests/${r2}`));
    await ok(as("carol").delete(`pairRequests/${r2}`));
  });
});

describe("ending a pairing", () => {
  it("either asks, with the 14-day date; only the asker can cancel", async () => {
    await denied(as("alice").update(couple, { separation: request({ effectiveAt: at(3 * DAY) }) }));
    await denied(as("alice").update(couple, { separation: request({ requestedBy: "bob" }) }));
    await denied(as("alice").update(couple, { separation: request({ status: "agreed" }) }));
    await denied(as("carol").update(couple, { separation: request({ requestedBy: "carol" }) }));
    await ok(as("alice").update(couple, { separation: request() }));
    await denied(as("alice").update(couple, { separation: request() })); // already asked
    await denied(as("bob").update(couple, { separation: DEL }));
    await ok(as("alice").update(couple, { separation: DEL }));
  });

  it("the partner agrees: 7 days from now, never later than the original date", async () => {
    await ok(as("alice").update(couple, { separation: request() }));
    await denied(as("alice").update(couple, { "separation.status": "agreed", "separation.agreedAt": ST, "separation.effectiveAt": at(7 * DAY) }));
    await denied(as("bob").update(couple, { "separation.status": "agreed", "separation.agreedAt": ST, "separation.effectiveAt": at(1 * DAY) }));
    await ok(as("bob").update(couple, { "separation.status": "agreed", "separation.agreedAt": ST, "separation.effectiveAt": at(7 * DAY) }));
  });

  it("agreeing late keeps the earlier original date", async () => {
    await admin.update(couple, {
      separation: { requestedBy: "alice", requestedAt: at(-12 * DAY), status: "requested", agreedAt: null, declinedAt: null, effectiveAt: at(2 * DAY) },
    });
    const orig = (await as("bob").data(couple))!.separation.effectiveAt;
    await denied(as("bob").update(couple, { "separation.status": "agreed", "separation.agreedAt": ST, "separation.effectiveAt": at(7 * DAY) }));
    await ok(as("bob").update(couple, { "separation.status": "agreed", "separation.agreedAt": ST, "separation.effectiveAt": orig }));
  });

  it("declining changes nothing else, can be followed by agreeing, and never stops it", async () => {
    await ok(as("alice").update(couple, { separation: request() }));
    await denied(as("bob").update(couple, { "separation.status": "declined", "separation.declinedAt": ST, "separation.effectiveAt": at(60 * DAY) }));
    await ok(as("bob").update(couple, { "separation.status": "declined", "separation.declinedAt": ST }));
    await denied(as("bob").update(couple, { separation: DEL }));
    await denied(as("bob").update(couple, { "separation.requestedBy": "bob" }));
    await ok(as("bob").update(couple, { "separation.status": "agreed", "separation.agreedAt": ST, "separation.effectiveAt": at(7 * DAY) }));
  });

  it("only the server's deletion lock may be written as `ending`", async () => {
    await denied(as("alice").update(couple, { ending: { how: "leftNow" } }));
  });

  it("other couple changes still work while it is ending", async () => {
    await ok(as("alice").update(couple, { separation: request() }));
    await ok(as("bob").update(couple, { coupleName: "Us", blockScreenshots: true }));
  });

  it("the vault is closed for both while it is ending", async () => {
    const meta = `couples/${C}/vault/meta`;
    await ok(as("bob").get(meta));
    await ok(as("alice").update(couple, { separation: request() }));
    await denied(as("bob").get(meta));
    await denied(as("alice").get(meta));
    await denied(as("alice").add(`couples/${C}/vaultItems`, {
      senderId: "alice", kind: "message", shelf: "a", ct: "eA==", photoPath: null, thumbPath: null,
      policy: "keep", expiresAt: null, viewedBy: {}, createdAt: ST,
    }));
    await denied(as("alice").add(`couples/${C}/vaultEvents`, { type: "wrongCode", uid: "alice", deviceName: "x", at: ST }));
    await ok(as("alice").update(couple, { separation: DEL }));
    await ok(as("bob").get(meta));
  });
});
