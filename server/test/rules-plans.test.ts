// Port of firestore-tests/test/plans.rules.test.js: date plans, bucket list,
// wishlist (+ secret claims), places and expenses.
import { describe, it } from "node:test";
import { admin, as, assert, denied, hidden, ok, ts, useDb } from "./rules-helpers.js";

type O = Record<string, unknown>;
const C = "couple1";
const T = () => ts("2026-10-15T10:00:00Z");
const base = `couples/${C}`;

useDb(async () => {
  await admin.set(base, { memberIds: ["alice", "bob"], inviteCode: "ABC234" });
  await admin.set(`${base}/wishlist/w1`, {
    title: "Kindle", notes: "", url: "", priceMinor: 1299900, priority: "love",
    occasion: "birthday", received: false, createdBy: "bob",
  });
});

describe("date plans", () => {
  const plan = (o: O = {}) => ({
    title: "Sunset picnic", notes: "", status: "idea", scheduledAt: null,
    location: "Cubbon Park", estimatedCostMinor: 50000, vibe: "outdoors",
    rating: null, reflection: "", createdBy: "alice", completedAt: null, ...o,
  });
  it("members create, read, edit and delete", async () => {
    await ok(as("alice").set(`${base}/datePlans/p1`, plan()));
    await ok(as("bob").get(`${base}/datePlans/p1`));
    await ok(as("bob").update(`${base}/datePlans/p1`, { status: "planned", scheduledAt: T() }));
    await ok(as("bob").delete(`${base}/datePlans/p1`));
  });
  it("strangers are refused", async () => {
    await denied(as("eve").set(`${base}/datePlans/p1`, plan({ createdBy: "eve" })));
    await admin.set(`${base}/datePlans/p1`, plan());
    await denied(as("eve").get(`${base}/datePlans/p1`));
  });
  it("rejects bad shapes", async () => {
    const r = (o: O) => as("alice").set(`${base}/datePlans/x`, plan(o));
    await denied(r({ title: "" }));
    await denied(r({ status: "planned", scheduledAt: null }));
    await denied(r({ rating: 6 }));
    await denied(r({ vibe: "weird" }));
    await denied(r({ createdBy: "bob" }));
    await denied(r({ estimatedCostMinor: -1 }));
  });
  it("cannot change who added it", async () => {
    await ok(as("alice").set(`${base}/datePlans/p1`, plan()));
    await denied(as("bob").update(`${base}/datePlans/p1`, { createdBy: "bob" }));
  });
});

describe("bucket list", () => {
  const item = (o: O = {}) => ({
    title: "See the northern lights", notes: "", category: "travel", done: false,
    doneAt: null, doneBy: null, targetYear: 2027, createdBy: "alice", ...o,
  });
  it("members add and tick items", async () => {
    await ok(as("alice").set(`${base}/bucketList/b1`, item()));
    await ok(as("bob").update(`${base}/bucketList/b1`, { done: true, doneAt: T(), doneBy: "bob" }));
  });
  it("doneBy must be a member; category must be known", async () => {
    await denied(as("alice").set(`${base}/bucketList/b2`, item({ done: true, doneBy: "eve" })));
    await denied(as("alice").set(`${base}/bucketList/b3`, item({ category: "nope" })));
  });
});

describe("wishlist", () => {
  const wish = (o: O = {}) => ({
    title: "Film camera", notes: "", url: "https://example.com/cam", priceMinor: 2500000,
    priority: "like", occasion: "any", received: false, createdBy: "alice", ...o,
  });
  it("only the owner edits their wishes; both can read", async () => {
    await ok(as("alice").set(`${base}/wishlist/a1`, wish()));
    await ok(as("bob").get(`${base}/wishlist/a1`));
    await denied(as("bob").update(`${base}/wishlist/a1`, { title: "Changed" }));
    await denied(as("bob").delete(`${base}/wishlist/a1`));
    await ok(as("alice").update(`${base}/wishlist/a1`, { received: true }));
  });
  it("cannot add a wish for someone else; links must be http(s)", async () => {
    await denied(as("alice").set(`${base}/wishlist/a2`, wish({ createdBy: "bob" })));
    await denied(as("alice").set(`${base}/wishlist/a3`, wish({ url: "javascript:alert(1)" })));
  });
});

describe("wishlist claims (secret)", () => {
  const claims = `${base}/wishlistClaims`;
  const claim = (o: O = {}) => ({ claimedBy: "alice", itemOwner: "bob", claimedAt: T(), purchased: false, ...o });
  it("alice can claim bob's wish and see her claim", async () => {
    await ok(as("alice").set(`${claims}/w1`, claim()));
    await ok(as("alice").get(`${claims}/w1`));
    const mine = await ok(as("alice").query({ collection: claims, where: [["claimedBy", "==", "alice"]] }));
    assert.equal(mine.length, 1);
    await ok(as("alice").update(`${claims}/w1`, { purchased: true }));
  });
  it("bob (the owner) can never see claims on his wishes", async () => {
    await admin.set(`${claims}/w1`, claim());
    await denied(as("bob").get(`${claims}/w1`));
    // Firestore refuses these queries; here they return none of the claims.
    await hidden(as("bob").query({ collection: claims }));
    await hidden(as("bob").query({ collection: claims, where: [["itemOwner", "==", "bob"]] }));
    await denied(as("bob").delete(`${claims}/w1`));
  });
  it("cannot claim your own wish or fake the owner", async () => {
    await denied(as("bob").set(`${claims}/w1`, claim({ claimedBy: "bob", itemOwner: "bob" })));
    await denied(as("alice").set(`${claims}/w1`, claim({ itemOwner: "alice" })));
    await denied(as("alice").set(`${claims}/w1`, claim({ claimedBy: "bob" })));
  });
  it("the claimer cannot reassign a claim", async () => {
    await ok(as("alice").set(`${claims}/w1`, claim()));
    await denied(as("alice").update(`${claims}/w1`, { claimedBy: "bob" }));
    await ok(as("alice").delete(`${claims}/w1`));
  });
});

describe("places", () => {
  const place = (o: O = {}) => ({
    name: "Toit", area: "Indiranagar", mapsUrl: "", category: "bar", status: "wantToGo",
    rating: null, visitedAt: null, notes: "", favourite: false, createdBy: "bob", ...o,
  });
  it("members add and mark as been", async () => {
    await ok(as("bob").set(`${base}/places/p1`, place()));
    await ok(as("alice").update(`${base}/places/p1`, { status: "been", rating: 5, visitedAt: T() }));
  });
  it("rejects unknown status and bad maps links", async () => {
    await denied(as("bob").set(`${base}/places/p2`, place({ status: "maybe" })));
    await denied(as("bob").set(`${base}/places/p3`, place({ mapsUrl: "ftp://x" })));
  });
});

describe("expenses", () => {
  const exp = (o: O = {}) => ({
    kind: "expense", title: "Dinner", amountMinor: 250000, paidBy: "alice", split: "equal",
    shares: null, category: "food", spentOn: T(), note: "", createdBy: "alice", ...o,
  });
  it("members add; either edits; only the creator deletes", async () => {
    await ok(as("alice").set(`${base}/expenses/e1`, exp()));
    await ok(as("bob").update(`${base}/expenses/e1`, { amountMinor: 260000 }));
    await denied(as("bob").delete(`${base}/expenses/e1`));
    await ok(as("alice").delete(`${base}/expenses/e1`));
  });
  it("custom splits and settlements", async () => {
    await ok(as("bob").set(`${base}/expenses/e2`, exp({ split: "custom", shares: { alice: 100000, bob: 150000 }, createdBy: "bob" })));
    await ok(as("bob").set(`${base}/expenses/s1`, exp({ kind: "settlement", title: "Settle up", split: "full", paidBy: "bob", category: "other", createdBy: "bob" })));
    await denied(as("bob").set(`${base}/expenses/s2`, exp({ kind: "settlement", split: "equal", createdBy: "bob" })));
  });
  it("rejects floats, zero, non-members and missing shares", async () => {
    const r = (o: O) => as("alice").set(`${base}/expenses/x`, exp(o));
    await denied(r({ amountMinor: 12.5 }));
    await denied(r({ amountMinor: 0 }));
    await denied(r({ paidBy: "eve" }));
    await denied(r({ split: "custom", shares: null }));
    await denied(r({ category: "crypto" }));
  });
  it("strangers cannot read the ledger", async () => {
    await admin.set(`${base}/expenses/e1`, exp());
    await denied(as("eve").get(`${base}/expenses/e1`));
  });
});
