// Port of firestore-tests/test/premium-books.rules.test.js: Premium
// (server-granted), gifts and Memory books (one credit each). The book-PDF
// storage case belongs to the storage rules suite.
import { describe, it } from "node:test";
import { ST, admin, as, denied, fromNow, inc, ok, ts, useDb } from "./rules-helpers.js";

type O = Record<string, unknown>;
const C = "couple1";
const couple = `couples/${C}`;
const book = (uid: string, id = "b1", o: O = {}) => ({
  createdBy: uid, title: "Asha & Ravi · 2026",
  fromDate: ts("2026-01-01"), toDate: ts("2026-12-31"),
  pageCount: 34, storagePath: `couples/${C}/books/${id}.pdf`, createdAt: ST, ...o,
});
const spend = (uid: string, id = "b1", o: O = {}, step = -1) =>
  as(uid).batch()
    .update(couple, { bookCredits: inc(step) })
    .set(`couples/${C}/books/${id}`, book(uid, id, o))
    .commit();

useDb(async () => {
  await admin.set(couple, { memberIds: ["alice", "bob"], inviteCode: "ABC234", bookCredits: 1 });
  await admin.set(`couples/${C}/gifts/g1`, { fromUid: "alice", toUid: "bob", kind: "premium", months: 3, message: "For you", createdAt: ts(Date.now()), openedAt: null });
  await admin.set("purchases/h1", { coupleId: C, uid: "alice" });
});

describe("premium, gifts and books rules", () => {
  it("Premium can only come from the server", async () => {
    await denied(as("alice").update(couple, { premium: { until: fromNow(1e10), plan: "yearly" } }));
    await denied(as("alice").update(couple, { bookCredits: 5 }));
    await denied(as("alice").update(couple, { bookCredits: inc(1) }));
    await denied(as("alice").get("purchases/h1"));
    await denied(as("alice").set("purchases/h2", { coupleId: C }));
  });

  it("a book costs exactly one credit, in the same batch", async () => {
    await denied(as("alice").set(`couples/${C}/books/b1`, book("alice"))); // no credit spent
    await denied(spend("alice", "b1", {}, -2));
    await denied(spend("alice", "b1", { createdBy: "bob" }));
    await denied(spend("alice", "b1", { storagePath: `couples/${C}/books/other.pdf` }));
    await denied(spend("alice", "b1", { title: "" }));
    await ok(spend("alice"));
    await ok(as("bob").get(`couples/${C}/books/b1`));
    await denied(spend("alice", "b2")); // no credits left
    await denied(as("alice").update(couple, { bookCredits: inc(-1) })); // never below zero
  });

  it("the maker renames; either deletes; strangers see nothing", async () => {
    await ok(spend("alice"));
    const b = `couples/${C}/books/b1`;
    await ok(as("alice").update(b, { title: "Our first year" }));
    await denied(as("bob").update(b, { title: "Mine" }));
    await denied(as("alice").update(b, { pageCount: 99 }));
    await denied(as("carol").get(b));
    await ok(as("bob").delete(b));
  });

  it("a gift is opened once, by the partner it is for", async () => {
    const g = `couples/${C}/gifts/g1`;
    await ok(as("alice").get(g));
    await denied(as("alice").set(`couples/${C}/gifts/g2`, { fromUid: "alice", toUid: "bob", kind: "premium" }));
    await denied(as("alice").update(g, { openedAt: ST }));
    await denied(as("bob").update(g, { openedAt: ST, months: 12 }));
    await ok(as("bob").update(g, { openedAt: ST }));
    await denied(as("bob").update(g, { openedAt: ST }));
    await denied(as("bob").delete(g));
  });
});
