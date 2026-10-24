// Port of firestore-tests/test/app-writes.rules.test.js: the exact writes the
// Dart services make (server timestamps, merges and null fields), so a rules
// change can't silently break the app.
import { describe, it } from "node:test";
import { ST, admin, as, assert, denied, ok, ts, useDb } from "./rules-helpers.js";

const C = "couple1";
const T = () => ts("2026-10-18T14:00:00Z");
const col = (name: string) => `couples/${C}/${name}`;
const d = (name: string, id: string) => `couples/${C}/${name}/${id}`;
const merge = { merge: true };

useDb(async () => {
  await admin.set(`couples/${C}`, { memberIds: ["alice", "bob"], inviteCode: "ABC234" });
});

describe("exact: date plans", () => {
  // DatePlan.toMap() for a new idea + createdAt only (no updatedAt).
  const idea = {
    title: "Sunset picnic", notes: "", status: "idea", scheduledAt: null, location: "",
    estimatedCostMinor: null, vibe: "cozy", rating: null, reflection: "",
    createdBy: "alice", completedAt: null,
  };
  it("add idea / place->date idea", async () => {
    await ok(as("alice").add(col("datePlans"), { ...idea, createdAt: ST }));
    await ok(as("bob").add(col("datePlans"), { ...idea, title: "Date at Toit", location: "Toit, Indiranagar", vibe: "fancy", createdBy: "bob", createdAt: ST }));
  });
  it("add planned via editor", async () => {
    await ok(as("alice").add(col("datePlans"), { ...idea, status: "planned", scheduledAt: T(), estimatedCostMinor: 0, createdAt: ST }));
  });
  it("schedule / markDone / moveToIdeas / edit by partner / delete", async () => {
    await ok(as("alice").set(d("datePlans", "p1"), { ...idea, createdAt: ST }));
    await ok(as("bob").update(d("datePlans", "p1"), { status: "planned", scheduledAt: T(), completedAt: null, updatedAt: ST }));
    await ok(as("bob").update(d("datePlans", "p1"), { status: "done", rating: null, reflection: "", completedAt: ST, updatedAt: ST }));
    await ok(as("alice").update(d("datePlans", "p1"), { status: "done", rating: 5, reflection: "Lovely", completedAt: ST, updatedAt: ST }));
    await ok(as("bob").set(d("datePlans", "p1"), { ...idea, status: "done", scheduledAt: T(), rating: 4, reflection: "x", completedAt: T(), updatedAt: ST }, merge));
    await ok(as("alice").update(d("datePlans", "p1"), { status: "idea", scheduledAt: null, rating: null, completedAt: null, updatedAt: ST }));
    await ok(as("bob").delete(d("datePlans", "p1")));
  });
  it("overflowed cost (DatePlanCost.parseMinor of 17 digits) is denied", async () => {
    await denied(as("alice").add(col("datePlans"), { ...idea, estimatedCostMinor: -8446744073709551716, createdAt: ST }));
  });
});

describe("exact: bucket list", () => {
  const item = { title: "Salsa", notes: "", category: "learn", done: false, doneAt: null, doneBy: null, targetYear: null, createdBy: "alice" };
  it("add, edit merge by partner, setDone on/off", async () => {
    const id = await ok(as("alice").add(col("bucketList"), { ...item, createdAt: ST, updatedAt: ST }));
    await ok(as("bob").set(d("bucketList", id), { title: "Salsa!", notes: "n", category: "romance", targetYear: 2027, updatedAt: ST }, merge));
    await ok(as("bob").update(d("bucketList", id), { done: true, doneAt: ST, doneBy: "bob", updatedAt: ST }));
    await ok(as("alice").update(d("bucketList", id), { done: false, doneAt: null, doneBy: null, updatedAt: ST }));
    await ok(as("bob").delete(d("bucketList", id)));
  });
});

describe("exact: wishlist + claims", () => {
  const wish = { title: "Kindle", notes: "", url: "", priceMinor: null, priority: "like", occasion: "any", createdBy: "bob", received: false };
  const claim = { claimedBy: "alice", itemOwner: "bob", purchased: false, claimedAt: ST };
  it("add / edit merge / received / delete", async () => {
    const id = await ok(as("bob").add(col("wishlist"), { ...wish, createdAt: ST, updatedAt: ST }));
    await ok(as("bob").set(d("wishlist", id), { title: "Kindle", notes: "", url: "https://amazon.in/x", priceMinor: 1299900, priority: "love", occasion: "birthday", updatedAt: ST }, merge));
    await ok(as("bob").update(d("wishlist", id), { received: true, updatedAt: ST }));
    await ok(as("bob").delete(d("wishlist", id)));
  });
  it("links with an uppercase scheme are accepted, like the app does", async () => {
    await ok(as("bob").add(col("wishlist"), { ...wish, url: "HTTPS://amazon.in/x", createdAt: ST, updatedAt: ST }));
    await ok(as("bob").add(col("wishlist"), { ...wish, url: "Https://amazon.in/x", createdAt: ST, updatedAt: ST }));
    await denied(as("bob").add(col("wishlist"), { ...wish, url: "javascript:alert(1)", createdAt: ST, updatedAt: ST }));
  });
  it("claim (set, serverTimestamp), list, purchased, unclaim", async () => {
    await admin.set(d("wishlist", "w1"), wish);
    await ok(as("alice").set(d("wishlistClaims", "w1"), claim));
    const mine = await ok(as("alice").query({ collection: col("wishlistClaims"), where: [["claimedBy", "==", "alice"]] }));
    assert.equal(mine.length, 1);
    await ok(as("alice").update(d("wishlistClaims", "w1"), { purchased: true }));
    await ok(as("alice").update(d("wishlistClaims", "w1"), { purchased: false }));
    await ok(as("alice").delete(d("wishlistClaims", "w1")));
  });
  // The app catches this and treats an existing claim of mine as done.
  it("claiming again while a claim exists (retry / second device) is denied", async () => {
    await admin.set(d("wishlist", "w1"), wish);
    await ok(as("alice").set(d("wishlistClaims", "w1"), claim));
    await denied(as("alice").set(d("wishlistClaims", "w1"), claim));
  });
  it("owner probing: get/create on missing and existing claim, delete on existing claim, all denied", async () => {
    await admin.set(d("wishlist", "w1"), wish);
    await denied(as("bob").get(d("wishlistClaims", "w1")));
    await denied(as("bob").set(d("wishlistClaims", "w1"), { claimedBy: "bob", itemOwner: "bob", purchased: false, claimedAt: ST }));
    await ok(as("alice").set(d("wishlistClaims", "w1"), claim));
    await denied(as("bob").get(d("wishlistClaims", "w1")));
    await denied(as("bob").delete(d("wishlistClaims", "w1")));
    await denied(as("bob").set(d("wishlistClaims", "w1"), { claimedBy: "bob", itemOwner: "bob", purchased: false, claimedAt: ST }));
    await denied(as("bob").update(d("wishlistClaims", "w1"), { purchased: true }));
  });
  // Firestore checks the delete rule even when the doc is missing (resource ==
  // null), so the owner's delete fails whether or not a claim exists. The store
  // skips rules for deleting a missing doc (a no-op that succeeds), which tells
  // the owner a claim exists when their delete is refused.
  it("owner probing: delete on a missing claim is denied", async () => {
    await admin.set(d("wishlist", "w1"), wish);
    await denied(as("bob").delete(d("wishlistClaims", "w1")));
  });
  it("owner can delete wish; orphan claim survives (claimer still lists it)", async () => {
    await admin.set(d("wishlist", "w1"), wish);
    await ok(as("alice").set(d("wishlistClaims", "w1"), claim));
    await ok(as("bob").delete(d("wishlist", "w1")));
    const snap = await as("alice").query({ collection: col("wishlistClaims"), where: [["claimedBy", "==", "alice"]] });
    assert.equal(snap.length, 1, "expected orphan");
  });
});

describe("exact: places", () => {
  const place = { name: "Toit", area: "Indiranagar", mapsUrl: "", category: "bar", status: "wantToGo", rating: null, visitedAt: null, notes: "", favourite: false, createdBy: "bob" };
  it("add / merge edit / favourite / markBeen / markWantToGo / delete", async () => {
    const id = await ok(as("bob").add(col("places"), { ...place, createdAt: ST }));
    await ok(as("alice").set(d("places", id), { ...place, mapsUrl: "https://maps.app.goo.gl/abc", updatedAt: ST }, merge));
    await ok(as("alice").update(d("places", id), { favourite: true, updatedAt: ST }));
    await ok(as("alice").update(d("places", id), { status: "been", visitedAt: T(), rating: null, notes: "", updatedAt: ST }));
    await ok(as("alice").update(d("places", id), { status: "wantToGo", visitedAt: null, rating: null, updatedAt: ST }));
    await ok(as("alice").delete(d("places", id)));
  });
  it("maps links with an uppercase scheme are accepted", async () => {
    await ok(as("bob").add(col("places"), { ...place, mapsUrl: "HTTPS://maps.google.com/x", createdAt: ST }));
  });
});

describe("exact: expenses + currency", () => {
  const base = { kind: "expense", title: "Dinner", amountMinor: 125050, paidBy: "alice", split: "equal", shares: null, category: "food", spentOn: T(), note: "", createdBy: "alice" };
  it("add equal/full/custom, partner edits via merge, settle, delete", async () => {
    const r1 = await ok(as("alice").add(col("expenses"), { ...base, createdAt: ST, updatedAt: ST }));
    await ok(as("alice").add(col("expenses"), { ...base, split: "full", paidBy: "bob", createdAt: ST, updatedAt: ST }));
    await ok(as("alice").add(col("expenses"), { ...base, split: "custom", shares: { alice: 25050, bob: 100000 }, createdAt: ST, updatedAt: ST }));
    await ok(as("bob").set(d("expenses", r1), { ...base, split: "custom", shares: { alice: 0, bob: 125050 }, updatedAt: ST }, merge));
    await ok(as("bob").set(d("expenses", r1), { ...base, split: "equal", shares: null, updatedAt: ST }, merge));
    await ok(as("bob").add(col("expenses"), { ...base, kind: "settlement", title: "Settle up", split: "full", paidBy: "alice", category: "other", createdBy: "bob", createdAt: ST, updatedAt: ST }));
    await ok(as("alice").add(col("expenses"), { ...base, amountMinor: 1000000000, createdAt: ST, updatedAt: ST }));
    await denied(as("bob").delete(d("expenses", r1)));
    await ok(as("alice").delete(d("expenses", r1)));
  });
  it("custom shares summing wrong are accepted by rules (no server check)", async () => {
    await ok(as("alice").add(col("expenses"), { ...base, split: "custom", shares: { alice: 1, bob: 1 }, createdAt: ST, updatedAt: ST }));
  });
  it("setCurrency merge", async () => {
    await ok(as("bob").set(`couples/${C}`, { currency: "USD" }, merge));
  });
});
