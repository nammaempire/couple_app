// Port of functions/test/billing.test.js, plus the Pub/Sub push webhook.
import { after, afterEach, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { startApp } from "./helpers.js";

const h = await import("./functions-helpers.js");
const { setPlayVerifier, PlayApiError } = await import("../src/functions/play.js");
const { hashToken, addMonths, PACKAGE_NAME, handlePlayNotification } = await import("../src/functions/billing.js");
const { endCouple } = await import("../src/functions/endCouple.js");
const { setRtdnPushCheckForTests } = await import("../src/functions/webhooks.js");
const { config } = await import("../src/config.js");

process.env.FUNCTIONS_LOG = "off";
const DAY = h.DAY;
const iso = (ms: number) => new Date(ms).toISOString();

/** In-memory Play: tokens -> purchases; records acknowledgements. */
class FakePlay {
  products = new Map<string, any>();
  subs = new Map<string, any>();
  acks: string[][] = [];
  failWith: Error | null = null;
  product(token: string, o: Record<string, unknown> = {}) {
    this.products.set(token, {
      purchaseState: 0, acknowledgementState: 0, consumptionState: 0, orderId: `GPA.${token}`,
      purchaseTimeMillis: String(Date.now() - 60000), ...o,
    });
  }
  sub(token: string, productId: string, expiryMs: number, o: Record<string, unknown> = {}) {
    this.subs.set(token, {
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE", acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
      latestOrderId: `GPA.${token}`, startTime: iso(Date.now() - 60000),
      lineItems: [{ productId, expiryTime: iso(expiryMs), latestSuccessfulOrderId: `GPA.${token}..0` }], ...o,
    });
  }
  check() { if (this.failWith) throw this.failWith; }
  async getProduct(pkg: string, _productId: string, token: string) {
    this.check();
    assert.equal(pkg, PACKAGE_NAME);
    const p = this.products.get(token);
    if (!p) throw new PlayApiError("not found", 404);
    return { ...p };
  }
  async getSubscription(_pkg: string, token: string) {
    this.check();
    const s = this.subs.get(token);
    if (!s) throw new PlayApiError("not found", 404);
    return JSON.parse(JSON.stringify(s));
  }
  async acknowledgeProduct(_pkg: string, productId: string, token: string) {
    this.acks.push(["product", productId, token]);
    this.products.get(token).acknowledgementState = 1;
  }
  async acknowledgeSubscription(_pkg: string, subId: string, token: string) {
    this.acks.push(["subscription", subId, token]);
    this.subs.get(token).acknowledgementState = "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED";
  }
}

let s: Awaited<ReturnType<typeof startApp>>;
before(async () => {
  s = await startApp();
});
after(async () => {
  setPlayVerifier(undefined);
  await s.close();
});

let play: FakePlay;
const call = (uid: string | null, data: unknown) => h.fn(s.base, "verifyPurchase", uid, data);
const buy = (uid: string | null, productId: string, purchaseToken: string, extra: Record<string, unknown> = {}, cid = "c1") =>
  call(uid, { coupleId: cid, productId, purchaseToken, packageName: PACKAGE_NAME, ...extra });
const couple = (cid = "c1") => h.get(`couples/${cid}`);
const purchase = (token: string) => h.get(`purchases/${hashToken(token)}`);
const gifts = async (cid = "c1") => {
  const { adminQuery } = await import("../src/store.js");
  const { pool } = await import("../src/db.js");
  return adminQuery(pool, { collection: `couples/${cid}/gifts` });
};
const near = (a: number, b: number, tol = 10000) => assert.ok(Math.abs(a - b) <= tol, `${iso(a)} not within ${tol}ms of ${iso(b)}`);
const untilMs = async (cid = "c1") => h.millis((await couple(cid)).premium.until);

const rtdnSub = (token: string, notificationType: number, subscriptionId = "premium_monthly") =>
  handlePlayNotification({
    version: "1.0", packageName: PACKAGE_NAME, eventTimeMillis: String(Date.now()),
    subscriptionNotification: { version: "1.0", notificationType, purchaseToken: token, subscriptionId },
  });

/** POSTs a Pub/Sub push message to the webhook. */
async function push(notification: unknown, o: { publishTime?: string; auth?: string; raw?: string } = {}) {
  const data = o.raw ?? Buffer.from(JSON.stringify(notification)).toString("base64");
  const res = await fetch(`${s.base}/webhooks/play-rtdn`, {
    method: "POST",
    headers: { "content-type": "application/json", ...(o.auth ? { authorization: o.auth } : {}) },
    body: JSON.stringify({
      message: { data, messageId: "m1", publishTime: o.publishTime ?? new Date().toISOString() },
      subscription: "projects/p/subscriptions/play-billing-push",
    }),
  });
  return { status: res.status, json: (await res.json()) as any };
}

async function seedPair() {
  await h.set("couples/c1", { memberIds: ["alice", "bob"], inviteCode: "AAA" });
  await h.set("couples/c2", { memberIds: ["carol", "dave"], inviteCode: "BBB" });
}

describe("verifyPurchase", () => {
  beforeEach(async () => {
    await h.clearAll();
    play = new FakePlay();
    setPlayVerifier(play);
    await seedPair();
  });

  it("book_single: +1 credit, purchase doc, acknowledged", async () => {
    play.product("t-book");
    assert.deepEqual(await buy("alice", "book_single", "t-book"), { status: "granted", bookCredits: 1 });
    play.product("t-book2");
    assert.deepEqual(await buy("bob", "book_single", "t-book2"), { status: "granted", bookCredits: 2 });
    assert.equal((await couple()).bookCredits, 2);
    const p = await purchase("t-book");
    assert.equal(p.coupleId, "c1");
    assert.equal(p.uid, "alice");
    assert.equal(p.productId, "book_single");
    assert.equal(p.packageName, PACKAGE_NAME);
    assert.equal(p.kind, "book");
    assert.equal(p.orderId, "GPA.t-book");
    assert.equal(p.status, "granted");
    assert.equal(p.giftId, null);
    assert.ok(h.isTimestamp(p.grantedAt));
    assert.equal(typeof p.purchaseTimeMillis, "number");
    assert.ok(!("expiryTime" in p));
    assert.deepEqual(play.acks[0], ["product", "book_single", "t-book"]);
  });

  for (const [productId, plan] of [["premium_monthly", "monthly"], ["premium_yearly", "yearly"]]) {
    it(`${productId}: premium until = line item expiry, plan ${plan}, acknowledged`, async () => {
      const exp = Date.now() + (plan === "monthly" ? 30 : 365) * DAY;
      play.sub("t-sub", productId, exp);
      const r = await buy("alice", productId, "t-sub");
      assert.deepEqual(r, { status: "granted", premiumUntil: iso(exp) });
      const { premium } = await couple();
      assert.equal(h.millis(premium.until), exp);
      assert.equal(h.millis(premium.subscriptionUntil), exp);
      assert.equal(premium.giftUntil, null);
      assert.equal(premium.plan, plan);
      assert.equal(premium.source, "subscription");
      assert.ok(h.isTimestamp(premium.updatedAt));
      const p = await purchase("t-sub");
      assert.equal(p.kind, "subscription");
      assert.equal(h.millis(p.expiryTime), exp);
      assert.equal(p.subscriptionState, "SUBSCRIPTION_STATE_ACTIVE");
      assert.equal(p.orderId, "GPA.t-sub..0");
      assert.deepEqual(play.acks, [["subscription", productId, "t-sub"]]);
    });
  }

  it("a subscription never shortens existing (gifted) premium", async () => {
    const giftUntil = Date.now() + 200 * DAY;
    await h.update("couples/c1", {
      premium: { until: h.tsAt(giftUntil), giftUntil: h.tsAt(giftUntil), subscriptionUntil: null, plan: "gift", source: "gift" },
    });
    const exp = Date.now() + 30 * DAY;
    play.sub("t-sub", "premium_monthly", exp);
    const r = await buy("bob", "premium_monthly", "t-sub");
    assert.equal(r.premiumUntil, iso(giftUntil));
    const { premium } = await couple();
    assert.equal(h.millis(premium.until), giftUntil);
    assert.equal(h.millis(premium.subscriptionUntil), exp);
    assert.equal(h.millis(premium.giftUntil), giftUntil);
    assert.equal(premium.plan, "monthly");
  });

  for (const [productId, months] of [["gift_premium_1m", 1], ["gift_premium_3m", 3], ["gift_premium_12m", 12]] as const) {
    it(`${productId}: +${months} months from now, plan gift, gift doc to the partner`, async () => {
      play.product(`t-${productId}`);
      const before = Date.now();
      const r = await buy("alice", productId, `t-${productId}`, { gift: { message: "For us ❤" } });
      assert.equal(r.status, "granted");
      assert.equal(typeof r.giftId, "string");
      const until = Date.parse(r.premiumUntil);
      near(until, addMonths(before, months));
      const { premium } = await couple();
      assert.equal(h.millis(premium.until), until);
      assert.equal(h.millis(premium.giftUntil), until);
      assert.equal(premium.subscriptionUntil, null);
      assert.equal(premium.plan, "gift");
      assert.equal(premium.source, "gift");
      const g = await h.get(`couples/c1/gifts/${r.giftId}`);
      assert.deepEqual(Object.keys(g).sort(), ["createdAt", "fromUid", "kind", "message", "months", "openedAt", "toUid"]);
      assert.equal(g.fromUid, "alice");
      assert.equal(g.toUid, "bob");
      assert.equal(g.kind, "premium");
      assert.equal(g.months, months);
      assert.equal(g.message, "For us ❤");
      assert.equal(g.openedAt, null);
      assert.ok(h.isTimestamp(g.createdAt));
      assert.equal((await purchase(`t-${productId}`)).giftId, r.giftId);
    });
  }

  it("gift_premium stacks on current premium and keeps the plan", async () => {
    const exp = Date.now() + 20 * DAY;
    play.sub("t-sub", "premium_monthly", exp);
    await buy("alice", "premium_monthly", "t-sub");
    play.product("t-g");
    const r = await buy("bob", "gift_premium_3m", "t-g", { gift: { message: "" } });
    assert.equal(r.premiumUntil, iso(addMonths(exp, 3)));
    const { premium } = await couple();
    assert.equal(premium.plan, "monthly");
    assert.equal(premium.source, "subscription");
    assert.equal(h.millis(premium.subscriptionUntil), exp);
    assert.equal(h.millis(premium.giftUntil), addMonths(exp, 3));
  });

  it("gift_book: +1 credit and a book gift doc (empty message OK)", async () => {
    await h.update("couples/c1", { bookCredits: 4 });
    play.product("t-gb");
    const r = await buy("bob", "gift_book", "t-gb", { gift: { message: "" } });
    assert.equal(r.status, "granted");
    assert.equal(r.bookCredits, 5);
    const g = await h.get(`couples/c1/gifts/${r.giftId}`);
    assert.equal(g.kind, "book");
    assert.equal(g.months, null);
    assert.equal(g.fromUid, "bob");
    assert.equal(g.toUid, "alice");
    assert.equal(g.message, "");
    assert.equal((await purchase("t-gb")).kind, "giftBook");
  });

  it("is idempotent: the same token is granted once", async () => {
    play.product("t-gb");
    const first = await buy("alice", "gift_book", "t-gb", { gift: { message: "hi" } });
    const again = await buy("bob", "gift_book", "t-gb", { gift: { message: "different" } });
    assert.deepEqual(again, { status: "alreadyGranted", bookCredits: 1, giftId: first.giftId });
    assert.equal((await couple()).bookCredits, 1);
    assert.equal((await gifts()).length, 1);
    assert.equal(play.acks.length, 1, "already acknowledged, not re-acked");
  });

  it("concurrent calls with one token grant once", async () => {
    play.product("t-b");
    const rs = await Promise.all([1, 2, 3].map(() => buy("alice", "book_single", "t-b")));
    assert.deepEqual(rs.map((r) => r.status).sort(), ["alreadyGranted", "alreadyGranted", "granted"]);
    assert.equal((await couple()).bookCredits, 1);
  });

  it("concurrent calls with one token from two couples: one wins, the other is permission-denied", async () => {
    play.product("t-b");
    const rs = await Promise.allSettled([buy("alice", "book_single", "t-b"), buy("carol", "book_single", "t-b", {}, "c2")]);
    const ok = rs.filter((r) => r.status === "fulfilled");
    const bad = rs.filter((r) => r.status === "rejected") as PromiseRejectedResult[];
    assert.equal(ok.length, 1);
    assert.equal(bad.length, 1);
    assert.equal(bad[0].reason.code, "permission-denied");
    const p = await purchase("t-b");
    const winner = await couple(p.coupleId);
    assert.equal(winner.bookCredits, 1);
    assert.equal((await couple(p.coupleId === "c1" ? "c2" : "c1")).bookCredits, undefined);
  });

  it("alreadyGranted retries a failed acknowledgement", async () => {
    play.product("t-b");
    (play as any).acknowledgeProduct = async () => { throw new PlayApiError("boom", 503); };
    assert.equal((await buy("alice", "book_single", "t-b")).status, "granted");
    delete (play as any).acknowledgeProduct; // back to the prototype method
    assert.equal((await buy("alice", "book_single", "t-b")).status, "alreadyGranted");
    assert.deepEqual(play.acks, [["product", "book_single", "t-b"]]);
  });

  it("a token used by another couple is permission-denied", async () => {
    play.product("t-b");
    await buy("alice", "book_single", "t-b");
    await h.rejectsWith(buy("carol", "book_single", "t-b", {}, "c2"), "permission-denied", /another couple/);
    assert.equal((await couple("c2")).bookCredits, undefined);
  });

  it("auth and membership", async () => {
    play.product("t-b");
    await h.rejectsWith(buy(null, "book_single", "t-b"), "unauthenticated");
    await h.rejectsWith(buy("carol", "book_single", "t-b"), "permission-denied");
    await h.rejectsWith(buy("alice", "book_single", "t-b", {}, "missing"), "permission-denied");
    assert.equal(await purchase("t-b"), undefined);
  });

  it("input validation: unknown product, gift field, message length, package", async () => {
    play.product("t");
    await h.rejectsWith(buy("alice", "premium_weekly", "t"), "invalid-argument", /Unknown productId/);
    await h.rejectsWith(buy("alice", "gift_book", "t"), "invalid-argument", /gift/);
    await h.rejectsWith(buy("alice", "gift_premium_1m", "t", { gift: {} }), "invalid-argument", /gift/);
    await h.rejectsWith(buy("alice", "gift_premium_1m", "t", { gift: { message: "x".repeat(301) } }), "invalid-argument", /300/);
    await h.rejectsWith(buy("alice", "book_single", ""), "invalid-argument");
    await h.rejectsWith(
      call("alice", { coupleId: "c1", productId: "book_single", purchaseToken: "t", packageName: "com.evil" }),
      "invalid-argument",
      /packageName/,
    );
    assert.equal((await buy("alice", "gift_premium_1m", "t", { gift: { message: "x".repeat(300) } })).status, "granted");
  });

  it("Play states and errors map to failed-precondition / unavailable", async () => {
    play.product("pending", { purchaseState: 2 });
    const e = await h.rejectsWith(buy("alice", "book_single", "pending"), "failed-precondition", /pending/);
    assert.deepEqual(e.details, { purchaseState: 2 });
    play.product("cancelled", { purchaseState: 1 });
    await h.rejectsWith(buy("alice", "book_single", "cancelled"), "failed-precondition", /cancelled/);
    await h.rejectsWith(buy("alice", "book_single", "nope"), "failed-precondition", /not recognise/);
    play.sub("expired", "premium_monthly", Date.now() - DAY, { subscriptionState: "SUBSCRIPTION_STATE_EXPIRED" });
    const e2 = await h.rejectsWith(buy("alice", "premium_monthly", "expired"), "failed-precondition", /not active/);
    assert.deepEqual(e2.details, { state: "SUBSCRIPTION_STATE_EXPIRED" });
    play.sub("grace", "premium_monthly", Date.now() + DAY, { subscriptionState: "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" });
    assert.equal((await buy("alice", "premium_monthly", "grace")).status, "granted");
    play.sub("yearly", "premium_yearly", Date.now() + DAY);
    await h.rejectsWith(buy("alice", "premium_monthly", "yearly"), "failed-precondition", /different product/);
    play.product("t-ok");
    play.failWith = new PlayApiError("backend", 503);
    const e3 = await h.rejectsWith(buy("alice", "book_single", "t-ok"), "unavailable");
    assert.equal(e3.status, 503);
    play.failWith = new PlayApiError("forbidden", 401);
    await h.rejectsWith(buy("alice", "book_single", "t-ok"), "unavailable");
    assert.equal((await couple()).bookCredits, undefined);
  });

  it("refuses a couple that is ending", async () => {
    await h.update("couples/c1", { ending: { how: "leftNow" } });
    play.product("t");
    await h.rejectsWith(buy("alice", "book_single", "t"), "failed-precondition", /ending/);
  });
});

describe("playBillingNotifications (RTDN)", () => {
  beforeEach(async () => {
    await h.clearAll();
    play = new FakePlay();
    setPlayVerifier(play);
    await h.set("couples/c1", { memberIds: ["alice", "bob"], inviteCode: "AAA" });
  });
  afterEach(() => setRtdnPushCheckForTests(undefined));

  it("RENEWED moves until and subscriptionUntil forward (through the Pub/Sub push webhook)", async () => {
    const exp1 = Date.now() + 2 * DAY;
    play.sub("t", "premium_monthly", exp1);
    await buy("alice", "premium_monthly", "t");
    const exp2 = exp1 + 30 * DAY;
    play.sub("t", "premium_monthly", exp2, { acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED" });
    const n = {
      version: "1.0", packageName: PACKAGE_NAME, eventTimeMillis: String(Date.now()),
      subscriptionNotification: { version: "1.0", notificationType: 2, purchaseToken: "t", subscriptionId: "premium_monthly" },
    };
    const seen: Array<string | undefined> = [];
    setRtdnPushCheckForTests(async (a) => (seen.push(a), a === "Bearer good" ? "ok" : "unauthorized"));
    assert.equal((await push(n, { auth: "Bearer bad" })).status, 401);
    const r = await push(n, { auth: "Bearer good" });
    assert.equal(r.status, 200);
    assert.equal(r.json.outcome, "updated");
    assert.deepEqual(seen, ["Bearer bad", "Bearer good"]);
    const { premium } = await couple();
    assert.equal(h.millis(premium.until), exp2);
    assert.equal(h.millis(premium.subscriptionUntil), exp2);
    assert.equal(premium.source, "subscription");
    assert.equal(h.millis((await purchase("t")).expiryTime), exp2);
  });

  it("webhook: 503 when not configured, 401 without a token, 2xx for bad data, 5xx on transient errors until 24h", async () => {
    // RTDN_AUDIENCE is empty in tests.
    assert.equal((await push({ testNotification: {} })).status, 503);
    const saved = { a: config.rtdnAudience, e: config.rtdnServiceAccountEmail };
    try {
      config.rtdnAudience = "https://test.local/webhooks/play-rtdn";
      config.rtdnServiceAccountEmail = "push@p.iam.gserviceaccount.com";
      assert.equal((await push({ testNotification: {} })).status, 401);
    } finally {
      config.rtdnAudience = saved.a;
      config.rtdnServiceAccountEmail = saved.e;
    }

    setRtdnPushCheckForTests(async () => "ok");
    const t = await push({ packageName: PACKAGE_NAME, testNotification: { version: "1.0" } });
    assert.deepEqual([t.status, t.json.outcome], [200, "test"]);
    const bad = await push(null, { raw: Buffer.from("not json").toString("base64") });
    assert.deepEqual([bad.status, bad.json.outcome], [200, "badMessage"]);

    play.sub("t", "premium_monthly", Date.now() + DAY);
    await buy("alice", "premium_monthly", "t");
    play.failWith = new PlayApiError("busy", 503);
    const n = { packageName: PACKAGE_NAME, subscriptionNotification: { notificationType: 2, purchaseToken: "t" } };
    assert.equal((await push(n)).status, 503, "young message: retry");
    const old = await push(n, { publishTime: new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString() });
    assert.deepEqual([old.status, old.json.outcome], [200, "dropped"]);
  });

  it("CANCELED keeps access until expiry; EXPIRED without gift ends at or before now", async () => {
    const exp = Date.now() + 10 * DAY;
    play.sub("t", "premium_monthly", exp);
    await buy("alice", "premium_monthly", "t");
    play.sub("t", "premium_monthly", exp, { subscriptionState: "SUBSCRIPTION_STATE_CANCELED" });
    assert.equal(await rtdnSub("t", 3), "updated");
    assert.equal(await untilMs(), exp);
    const past = Date.now() - 1000;
    play.sub("t", "premium_monthly", past, { subscriptionState: "SUBSCRIPTION_STATE_EXPIRED" });
    assert.equal(await rtdnSub("t", 13), "updated");
    const { premium } = await couple();
    assert.ok(h.millis(premium.until) <= Date.now());
    assert.equal(h.millis(premium.subscriptionUntil), past);
    assert.equal(premium.giftUntil, null);
  });

  it("REVOKED cuts a future expiry to now", async () => {
    const exp = Date.now() + 25 * DAY;
    play.sub("t", "premium_yearly", exp);
    await buy("alice", "premium_yearly", "t");
    // Play may still report the old expiry right after a revoke.
    const before = Date.now();
    assert.equal(await rtdnSub("t", 12, "premium_yearly"), "updated");
    const { premium } = await couple();
    near(h.millis(premium.until), before);
    near(h.millis(premium.subscriptionUntil), before);
    assert.equal((await purchase("t")).status, "voided");
  });

  it("gift time survives subscription renewal, expiry and revoke", async () => {
    const exp = Date.now() + 5 * DAY;
    play.sub("t", "premium_monthly", exp);
    await buy("alice", "premium_monthly", "t");
    play.product("g");
    await buy("bob", "gift_premium_1m", "g", { gift: { message: "more" } });
    const giftUntil = addMonths(exp, 1);
    assert.equal(await untilMs(), giftUntil);

    // Renewal past the gift end: subscription wins.
    const renewed = giftUntil + 3 * DAY;
    play.sub("t", "premium_monthly", renewed);
    await rtdnSub("t", 2);
    let { premium } = await couple();
    assert.equal(h.millis(premium.until), renewed);
    assert.equal(h.millis(premium.giftUntil), giftUntil);

    // Revoke: back to the gift time, plan becomes gift.
    await rtdnSub("t", 12);
    ({ premium } = await couple());
    assert.equal(h.millis(premium.until), giftUntil);
    assert.equal(premium.plan, "gift");
    assert.equal(premium.source, "gift");
  });

  it("a renewal shorter than the gift keeps the gift end", async () => {
    const exp = Date.now() + 5 * DAY;
    play.sub("t", "premium_monthly", exp);
    await buy("alice", "premium_monthly", "t");
    play.product("g");
    await buy("bob", "gift_premium_3m", "g", { gift: { message: "" } });
    const giftUntil = addMonths(exp, 3);
    play.sub("t", "premium_monthly", exp + 30 * DAY);
    await rtdnSub("t", 2);
    assert.equal(await untilMs(), giftUntil);
    play.sub("t", "premium_monthly", Date.now() - 1, { subscriptionState: "SUBSCRIPTION_STATE_EXPIRED" });
    await rtdnSub("t", 13);
    assert.equal(await untilMs(), giftUntil);
  });

  it("unknown tokens, other packages and test notifications are ignored", async () => {
    assert.equal(await rtdnSub("never-verified", 4), "unknownToken");
    assert.equal(
      await handlePlayNotification({ packageName: "com.other", subscriptionNotification: { notificationType: 2, purchaseToken: "x" } }),
      "otherPackage",
    );
    assert.equal(await handlePlayNotification({ packageName: PACKAGE_NAME, testNotification: { version: "1.0" } }), "test");
  });

  it("transient Play errors are thrown (so Pub/Sub retries)", async () => {
    play.sub("t", "premium_monthly", Date.now() + DAY);
    await buy("alice", "premium_monthly", "t");
    play.failWith = new PlayApiError("busy", 503);
    await assert.rejects(rtdnSub("t", 2), /busy/);
    play.failWith = new PlayApiError("gone", 410);
    assert.equal(await rtdnSub("t", 2), "lookupFailed");
  });

  it("voided book: removes an unused credit once; with none left only marks voided", async () => {
    play.product("b1");
    play.product("b2");
    await buy("alice", "book_single", "b1");
    await buy("alice", "gift_book", "b2", { gift: { message: "" } });
    assert.equal((await couple()).bookCredits, 2);
    const voided = (token: string) =>
      handlePlayNotification({
        packageName: PACKAGE_NAME,
        voidedPurchaseNotification: { purchaseToken: token, orderId: `GPA.${token}`, productType: 2, refundType: 1 },
      });

    assert.equal(await voided("b1"), "voidedCreditRemoved");
    assert.equal((await couple()).bookCredits, 1);
    const p = await purchase("b1");
    assert.equal(p.status, "voided");
    assert.equal(p.creditRemoved, true);
    assert.equal(p.refundType, 1);
    assert.ok(h.isTimestamp(p.voidedAt));
    assert.equal(await voided("b1"), "alreadyVoided");
    assert.equal((await couple()).bookCredits, 1);

    await h.update("couples/c1", { bookCredits: 0 }); // the credit was used
    assert.equal(await voided("b2"), "voided");
    assert.equal((await couple()).bookCredits, 0);
    assert.equal((await purchase("b2")).creditRemoved, false);
    assert.equal(await voided("unknown"), "unknownToken");
  });

  it("a voided subscription is treated as revoked", async () => {
    play.sub("t", "premium_monthly", Date.now() + 20 * DAY);
    await buy("alice", "premium_monthly", "t");
    const before = Date.now();
    assert.equal(
      await handlePlayNotification({ packageName: PACKAGE_NAME, voidedPurchaseNotification: { purchaseToken: "t", productType: 1 } }),
      "updated",
    );
    near(await untilMs(), before);
  });
});

describe("endCouple and purchases", () => {
  beforeEach(async () => {
    await h.clearAll();
    play = new FakePlay();
    setPlayVerifier(play);
  });

  it("deletes couples/{cid}/books/ files and gifts, keeps purchases for audit, ignores later RTDNs", async () => {
    await h.seedCouple("c1");
    await h.putFile("couples/c1/books/b1/book.pdf");
    await h.putFile("couples/c1/books/b1/pages/1.jpg");
    play.product("g");
    await buy("alice", "gift_book", "g", { gift: { message: "" } });
    play.sub("t", "premium_monthly", Date.now() + DAY);
    await buy("alice", "premium_monthly", "t");

    const r = await endCouple("c1", "leftNow");
    assert.equal(r.counts!.storageFiles, 8);
    assert.equal(r.counts!.subcollectionDocs.gifts, 1);
    assert.deepEqual(await h.listFiles("couples/c1/books/"), []);
    assert.equal((await purchase("g")).coupleId, "c1");
    assert.equal((await purchase("t")).coupleId, "c1");
    assert.equal(await rtdnSub("t", 2), "coupleGone");
    assert.equal(await h.exists("couples/c1"), false, "RTDN does not recreate the couple");
  });
});
