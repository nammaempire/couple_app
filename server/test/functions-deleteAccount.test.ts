/** deleteAccount: "Delete my account" in the app. */
import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { startApp } from "./helpers.js";

const h = await import("./functions-helpers.js");
const { setSignInDeleter, RECENT_SIGN_IN_MS } = await import("../src/functions/deleteAccount.js");

process.env.FUNCTIONS_LOG = "off";
let s: Awaited<ReturnType<typeof startApp>>;
const deletedSignIns: string[] = [];

before(async () => {
  s = await startApp();
  setSignInDeleter(async (uid) => {
    deletedSignIns.push(uid);
    return true;
  });
});
after(async () => {
  setSignInDeleter(null);
  await s.close();
});

/** A caller who signed in [agoMs] ago. */
const signedIn = (uid: string, agoMs = 60_000) =>
  `${uid}:${Buffer.from(JSON.stringify({ auth_time: Math.floor((Date.now() - agoMs) / 1000) })).toString("base64url")}`;

describe("deleteAccount", () => {
  beforeEach(async () => {
    await h.clearAll();
    deletedSignIns.length = 0;
  });

  it("ends the pairing, deletes the person's data, files and sign-in", async () => {
    await h.seedCouple("c1");
    await h.seedCouple("other", ["carol", "dave"]);
    await h.set("users/alice/devices/d1", { name: "Phone" });
    await h.set("users/alice/pushTokens/t1", { token: "x" });
    await h.set("users/alice/securityEvents/e1", { kind: "newPhone" });
    await h.set("phoneIndex/+919000000001", { uid: "alice" });
    await h.set("phoneIndex/+919000000002", { uid: "bob" });
    await h.set("pairRequests/toAlice", { fromUid: "erin", toUid: "alice", coupleId: "c9" });
    await h.set("purchases/p1", { coupleId: "c1", uid: "alice", productId: "premium_monthly" });

    const r = await h.fn(s.base, "deleteAccount", signedIn("alice"), { confirm: "DELETE" });
    assert.deepEqual(r, { status: "deleted", signInDeleted: true });
    assert.deepEqual(deletedSignIns, ["alice"]);

    // Shared data is gone for both; the partner sees the pairing ended.
    assert.equal(await h.exists("couples/c1"), false);
    assert.equal(await h.countDocsUnder("c1"), 0);
    assert.deepEqual(await h.listFiles("couples/c1/"), []);
    const bob = await h.get("users/bob");
    assert.equal(bob.coupleId, null);
    assert.equal(bob.pairingEndedHow, "leftNow");

    // Alice's own records and files.
    for (const p of ["users/alice", "users/alice/devices/d1", "users/alice/pushTokens/t1", "users/alice/securityEvents/e1", "phoneIndex/+919000000001", "pairRequests/toAlice"]) {
      assert.equal(await h.exists(p), false, p);
    }
    assert.deepEqual(await h.listFiles("users/alice/"), []);

    // Not anyone else's, and purchase records are kept.
    assert.equal(await h.exists("phoneIndex/+919000000002"), true);
    assert.deepEqual(await h.listFiles("users/bob/profile/"), ["users/bob/profile/me.jpg"]);
    assert.equal(await h.exists("couples/other"), true);
    assert.equal(await h.exists("purchases/p1"), true);
  });

  it("works for someone not paired yet (a couple of one) and is safe to repeat", async () => {
    await h.seedCouple("solo", ["carol"]);
    await h.fn(s.base, "deleteAccount", signedIn("carol"), { confirm: "DELETE" });
    assert.equal(await h.exists("couples/solo"), false);
    assert.equal(await h.exists("invites/INVsolo"), false);
    assert.equal(await h.exists("users/carol"), false);
    // A retry after a dropped connection finds nothing left and still succeeds.
    await h.fn(s.base, "deleteAccount", signedIn("carol"), { confirm: "DELETE" });
  });

  it("needs a fresh sign-in and the explicit confirmation", async () => {
    await h.seedCouple("c1");
    await h.rejectsWith(h.fn(s.base, "deleteAccount", signedIn("alice", RECENT_SIGN_IN_MS + 60_000), { confirm: "DELETE" }), "failed-precondition");
    await h.rejectsWith(h.fn(s.base, "deleteAccount", "alice", { confirm: "DELETE" }), "failed-precondition");
    await h.rejectsWith(h.fn(s.base, "deleteAccount", signedIn("alice"), {}), "invalid-argument");
    await h.rejectsWith(h.fn(s.base, "deleteAccount", null, { confirm: "DELETE" }), "unauthenticated");
    assert.equal(await h.exists("users/alice"), true);
    assert.equal(await h.exists("couples/c1"), true);
  });

  it("still deletes the data if the sign-in can't be deleted here", async () => {
    setSignInDeleter(async () => false);
    try {
      await h.seedCouple("c1");
      const r = await h.fn(s.base, "deleteAccount", signedIn("bob"), { confirm: "DELETE" });
      assert.deepEqual(r, { status: "deleted", signInDeleted: false });
      assert.equal(await h.exists("users/bob"), false);
    } finally {
      setSignInDeleter(async (uid) => {
        deletedSignIns.push(uid);
        return true;
      });
    }
  });
});

describe("/delete-account page", () => {
  it("explains deleting in the app, what goes and what stays", async () => {
    const res = await fetch(`${s.base}/delete-account`);
    assert.equal(res.status, 200);
    assert.match(res.headers.get("content-type") ?? "", /text\/html/);
    const html = await res.text();
    assert.match(html, /Delete my account/);
    assert.match(html, /What is kept/);
  });

  it("shows the support email when one is set", async () => {
    const { deletePageHtml } = await import("../src/deletePage.js");
    assert.match(deletePageHtml("help@example.com"), /mailto:help@example.com/);
    assert.doesNotMatch(deletePageHtml(""), /mailto:/);
    assert.doesNotMatch(deletePageHtml('"><script>'), /<script>/);
  });
});

describe("/privacy and /terms", () => {
  it("are served as HTML pages, linked to each other", async () => {
    for (const path of ["/privacy", "/terms"]) {
      const res = await fetch(`${s.base}${path}`);
      assert.equal(res.status, 200, path);
      assert.match(res.headers.get("content-type") ?? "", /text\/html/);
      const html = await res.text();
      assert.match(html, /Reset95 Private Limited/);
      assert.match(html, /href="\/delete-account"/);
    }
  });

  it("show the contact details that are set", async () => {
    const { privacyHtml, termsHtml } = await import("../src/legal.js");
    const c = { email: "help@example.com", address: "12 MG Road, Bengaluru", grievanceOfficer: "A. Kumar" };
    const p = privacyHtml(c);
    assert.match(p, /mailto:help@example.com/);
    assert.match(p, /12 MG Road, Bengaluru/);
    assert.match(p, /Grievance Officer: A\. Kumar/);
    assert.match(termsHtml(c), /mailto:help@example.com/);
    // Nothing set: no empty mailto links.
    const bare = privacyHtml({ email: "", address: "", grievanceOfficer: "" });
    assert.doesNotMatch(bare, /mailto:/);
    assert.doesNotMatch(privacyHtml({ ...c, address: "<script>" }), /<script>/);
  });
});
