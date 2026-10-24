// Port of firestore-tests/test/device-checks.rules.test.js: new-phone sign-in
// protection — known phones, partner checks and security notices.
import { describe, it } from "node:test";
import { ST, admin, as, assert, denied, fromNow, hidden, ok, ts, useDb } from "./rules-helpers.js";

const C = "couple1";
const device = (o: Record<string, unknown> = {}) => ({ name: "Pixel 9", addedAt: ST, lastSeenAt: ST, via: "partner", ...o });

useDb(async () => {
  await admin.set(`couples/${C}`, { memberIds: ["alice", "bob"], inviteCode: "ABC234" });
  await admin.set("users/alice", { displayName: "Alice", coupleId: C });
  await admin.set("users/bob", { displayName: "Bob", coupleId: C });
  await admin.set("users/carol", { displayName: "Carol", coupleId: null });
});

describe("device check rules", () => {
  it("known phones: the owner records them, only lastSeenAt moves", async () => {
    const d = "users/alice/devices/dev1";
    await ok(as("alice").set(d, device({ via: "first" })));
    await denied(as("alice").set("users/alice/devices/dev2", device({ via: "trustme" })));
    await denied(as("bob").set("users/alice/devices/dev3", device()));
    await ok(as("alice").update(d, { lastSeenAt: ST }));
    await denied(as("alice").update(d, { via: "email" }));
    await ok(as("bob").get(d));
    await denied(as("carol").get(d));
    await denied(as("bob").delete(d));
    await ok(as("alice").delete(d));
  });

  it("a new-phone check: the other partner decides, once", async () => {
    const checks = `couples/${C}/deviceChecks`;
    const id = await ok(as("alice").add(checks, {
      uid: "alice", deviceId: "dev9", deviceName: "Pixel 9", createdAt: ST, status: "pending", code: 47,
    }));
    await denied(as("alice").add(checks, {
      uid: "alice", deviceId: "dev9", deviceName: "Pixel 9", createdAt: ST, status: "approved", code: 47,
    }));
    await denied(as("alice").add(checks, {
      uid: "bob", deviceId: "dev9", deviceName: "Pixel 9", createdAt: ST, status: "pending", code: 47,
    }));
    const check = `${checks}/${id}`;
    // The person on the new phone can't approve themselves.
    await denied(as("alice").update(check, { status: "approved", decidedBy: "alice", decidedAt: ST }));
    await denied(as("bob").update(check, { status: "approved", decidedBy: "alice", decidedAt: ST }));
    await denied(as("carol").get(check));
    await ok(as("bob").update(check, { status: "approved", decidedBy: "bob", decidedAt: ST }));
    await denied(as("bob").update(check, { status: "rejected", decidedBy: "bob", decidedAt: ST }));
    await denied(as("bob").delete(check));
    await ok(as("alice").delete(check));
  });

  it("security notices: the owner, or the partner saying they turned a phone down", async () => {
    const events = "users/alice/securityEvents";
    const ev = (o: Record<string, unknown> = {}) => ({ type: "newPhoneRejected", deviceName: "Pixel 9", at: ST, ...o });
    await ok(as("alice").add(events, ev({ type: "newPhoneWaiting" })));
    await ok(as("bob").add(events, ev()));
    await denied(as("bob").add(events, ev({ type: "newPhoneApproved" })));
    await denied(as("carol").add(events, ev()));
    const own = await ok(as("alice").query({ collection: events }));
    assert.equal(own.length, 2);
    // Firestore refuses bob's whole query; here it returns none of the notices.
    await hidden(as("bob").query({ collection: events }));
  });

  it("the owner can pause new-phone sign-ins", async () => {
    await ok(as("alice").update("users/alice", { blockNewPhoneUntil: fromNow(30 * 86400000) }));
    await denied(as("alice").update("users/alice", { blockNewPhoneUntil: "forever" }));
    await denied(as("bob").update("users/alice", { blockNewPhoneUntil: ts(Date.now()) }));
  });
});
