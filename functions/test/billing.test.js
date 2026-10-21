const assert = require('node:assert/strict');
const h = require('./helpers.js');
const { Timestamp } = require('firebase-admin/firestore');
const { setPlayVerifier, PlayApiError } = require('../lib/play.js');
const { hashToken, addMonths, PACKAGE_NAME, handlePlayNotification } = require('../lib/billing.js');
const { verifyPurchase, playBillingNotifications } = require('../lib/index.js');
const { endCouple } = require('../lib/endCouple.js');

const DAY = h.DAY;
const iso = (ms) => new Date(ms).toISOString();

/** In-memory Play: tokens -> purchases; records acknowledgements. */
class FakePlay {
  constructor() { this.products = new Map(); this.subs = new Map(); this.acks = []; this.failWith = null; }
  product(token, o = {}) {
    this.products.set(token, { purchaseState: 0, acknowledgementState: 0, consumptionState: 0, orderId: `GPA.${token}`, purchaseTimeMillis: String(Date.now() - 60000), ...o });
  }
  sub(token, productId, expiryMs, o = {}) {
    this.subs.set(token, {
      subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE', acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING',
      latestOrderId: `GPA.${token}`, startTime: iso(Date.now() - 60000),
      lineItems: [{ productId, expiryTime: iso(expiryMs), latestSuccessfulOrderId: `GPA.${token}..0` }], ...o,
    });
  }
  check() { if (this.failWith) throw this.failWith; }
  async getProduct(pkg, productId, token) {
    this.check();
    assert.equal(pkg, PACKAGE_NAME);
    const p = this.products.get(token);
    if (!p) throw new PlayApiError('not found', 404);
    return { ...p };
  }
  async getSubscription(pkg, token) {
    this.check();
    const s = this.subs.get(token);
    if (!s) throw new PlayApiError('not found', 404);
    return JSON.parse(JSON.stringify(s));
  }
  async acknowledgeProduct(pkg, productId, token) { this.acks.push(['product', productId, token]); this.products.get(token).acknowledgementState = 1; }
  async acknowledgeSubscription(pkg, subId, token) { this.acks.push(['subscription', subId, token]); this.subs.get(token).acknowledgementState = 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'; }
}

let play;
const call = (uid, data) => verifyPurchase.run({ data, auth: uid ? { uid, token: { uid } } : undefined, rawRequest: {} });
const buy = (uid, productId, purchaseToken, extra = {}, cid = 'c1') =>
  call(uid, { coupleId: cid, productId, purchaseToken, packageName: PACKAGE_NAME, ...extra });
const couple = async (cid = 'c1') => (await h.db().doc(`couples/${cid}`).get()).data();
const purchase = async (token) => (await h.db().doc(`purchases/${hashToken(token)}`).get()).data();
const gifts = async (cid = 'c1') => (await h.db().collection(`couples/${cid}/gifts`).get()).docs;
const near = (a, b, tol = 10000) => assert.ok(Math.abs(a - b) <= tol, `${iso(a)} not within ${tol}ms of ${iso(b)}`);
const untilMs = async (cid = 'c1') => (await couple(cid)).premium.until.toMillis();

async function rejectsWith(promise, code, re) {
  await assert.rejects(promise, (e) => {
    assert.equal(e.code, code, `expected ${code}, got ${e.code}: ${e.message}`);
    if (re) assert.match(e.message, re);
    return true;
  });
}

const rtdnSub = (token, notificationType, subscriptionId = 'premium_monthly') =>
  handlePlayNotification({ version: '1.0', packageName: PACKAGE_NAME, eventTimeMillis: String(Date.now()), subscriptionNotification: { version: '1.0', notificationType, purchaseToken: token, subscriptionId } });

describe('verifyPurchase', () => {
  beforeEach(async () => {
    await h.clearAll();
    play = new FakePlay();
    setPlayVerifier(play);
    await h.db().doc('couples/c1').set({ memberIds: ['alice', 'bob'], inviteCode: 'AAA' });
    await h.db().doc('couples/c2').set({ memberIds: ['carol', 'dave'], inviteCode: 'BBB' });
  });
  after(() => setPlayVerifier(undefined));

  it('book_single: +1 credit, purchase doc, acknowledged', async () => {
    play.product('t-book');
    assert.deepEqual(await buy('alice', 'book_single', 't-book'), { status: 'granted', bookCredits: 1 });
    play.product('t-book2');
    assert.deepEqual(await buy('bob', 'book_single', 't-book2'), { status: 'granted', bookCredits: 2 });
    assert.equal((await couple()).bookCredits, 2);
    const p = await purchase('t-book');
    assert.equal(p.coupleId, 'c1');
    assert.equal(p.uid, 'alice');
    assert.equal(p.productId, 'book_single');
    assert.equal(p.kind, 'book');
    assert.equal(p.orderId, 'GPA.t-book');
    assert.equal(p.status, 'granted');
    assert.equal(p.giftId, null);
    assert.ok(p.grantedAt instanceof Timestamp);
    assert.equal(typeof p.purchaseTimeMillis, 'number');
    assert.ok(!('expiryTime' in p));
    assert.deepEqual(play.acks[0], ['product', 'book_single', 't-book']);
  });

  for (const [productId, plan] of [['premium_monthly', 'monthly'], ['premium_yearly', 'yearly']]) {
    it(`${productId}: premium until = line item expiry, plan ${plan}, acknowledged`, async () => {
      const exp = Date.now() + (plan === 'monthly' ? 30 : 365) * DAY;
      play.sub('t-sub', productId, exp);
      const r = await buy('alice', productId, 't-sub');
      assert.deepEqual(r, { status: 'granted', premiumUntil: iso(exp) });
      const { premium } = await couple();
      assert.equal(premium.until.toMillis(), exp);
      assert.equal(premium.subscriptionUntil.toMillis(), exp);
      assert.equal(premium.giftUntil, null);
      assert.equal(premium.plan, plan);
      assert.equal(premium.source, 'subscription');
      assert.ok(premium.updatedAt instanceof Timestamp);
      const p = await purchase('t-sub');
      assert.equal(p.kind, 'subscription');
      assert.equal(p.expiryTime.toMillis(), exp);
      assert.equal(p.orderId, 'GPA.t-sub..0');
      assert.deepEqual(play.acks, [['subscription', productId, 't-sub']]);
    });
  }

  it('a subscription never shortens existing (gifted) premium', async () => {
    const giftUntil = Date.now() + 200 * DAY;
    await h.db().doc('couples/c1').update({ premium: { until: Timestamp.fromMillis(giftUntil), giftUntil: Timestamp.fromMillis(giftUntil), subscriptionUntil: null, plan: 'gift', source: 'gift' } });
    const exp = Date.now() + 30 * DAY;
    play.sub('t-sub', 'premium_monthly', exp);
    const r = await buy('bob', 'premium_monthly', 't-sub');
    assert.equal(r.premiumUntil, iso(giftUntil));
    const { premium } = await couple();
    assert.equal(premium.until.toMillis(), giftUntil);
    assert.equal(premium.subscriptionUntil.toMillis(), exp);
    assert.equal(premium.giftUntil.toMillis(), giftUntil);
    assert.equal(premium.plan, 'monthly');
  });

  for (const [productId, months] of [['gift_premium_1m', 1], ['gift_premium_3m', 3], ['gift_premium_12m', 12]]) {
    it(`${productId}: +${months} months from now, plan gift, gift doc to the partner`, async () => {
      play.product(`t-${productId}`);
      const before = Date.now();
      const r = await buy('alice', productId, `t-${productId}`, { gift: { message: 'For us ❤' } });
      assert.equal(r.status, 'granted');
      assert.equal(typeof r.giftId, 'string');
      const until = Date.parse(r.premiumUntil);
      near(until, addMonths(before, months));
      const { premium } = await couple();
      assert.equal(premium.until.toMillis(), until);
      assert.equal(premium.giftUntil.toMillis(), until);
      assert.equal(premium.subscriptionUntil, null);
      assert.equal(premium.plan, 'gift');
      assert.equal(premium.source, 'gift');
      const g = (await h.db().doc(`couples/c1/gifts/${r.giftId}`).get()).data();
      assert.deepEqual(Object.keys(g).sort(), ['createdAt', 'fromUid', 'kind', 'message', 'months', 'openedAt', 'toUid']);
      assert.equal(g.fromUid, 'alice');
      assert.equal(g.toUid, 'bob');
      assert.equal(g.kind, 'premium');
      assert.equal(g.months, months);
      assert.equal(g.message, 'For us ❤');
      assert.equal(g.openedAt, null);
      assert.ok(g.createdAt instanceof Timestamp);
      assert.equal((await purchase(`t-${productId}`)).giftId, r.giftId);
    });
  }

  it('gift_premium stacks on current premium and keeps the plan', async () => {
    const exp = Date.now() + 20 * DAY;
    play.sub('t-sub', 'premium_monthly', exp);
    await buy('alice', 'premium_monthly', 't-sub');
    play.product('t-g');
    const r = await buy('bob', 'gift_premium_3m', 't-g', { gift: { message: '' } });
    assert.equal(r.premiumUntil, iso(addMonths(exp, 3)));
    const { premium } = await couple();
    assert.equal(premium.plan, 'monthly');
    assert.equal(premium.source, 'subscription');
    assert.equal(premium.subscriptionUntil.toMillis(), exp);
    assert.equal(premium.giftUntil.toMillis(), addMonths(exp, 3));
  });

  it('gift_book: +1 credit and a book gift doc (empty message OK)', async () => {
    await h.db().doc('couples/c1').update({ bookCredits: 4 });
    play.product('t-gb');
    const r = await buy('bob', 'gift_book', 't-gb', { gift: { message: '' } });
    assert.equal(r.status, 'granted');
    assert.equal(r.bookCredits, 5);
    const g = (await h.db().doc(`couples/c1/gifts/${r.giftId}`).get()).data();
    assert.equal(g.kind, 'book');
    assert.equal(g.months, null);
    assert.equal(g.fromUid, 'bob');
    assert.equal(g.toUid, 'alice');
    assert.equal(g.message, '');
    assert.equal((await purchase('t-gb')).kind, 'giftBook');
  });

  it('is idempotent: the same token is granted once', async () => {
    play.product('t-gb');
    const first = await buy('alice', 'gift_book', 't-gb', { gift: { message: 'hi' } });
    const again = await buy('bob', 'gift_book', 't-gb', { gift: { message: 'different' } });
    assert.deepEqual(again, { status: 'alreadyGranted', bookCredits: 1, giftId: first.giftId });
    assert.equal((await couple()).bookCredits, 1);
    assert.equal((await gifts()).length, 1);
    assert.equal(play.acks.length, 1, 'already acknowledged, not re-acked');
  });

  it('concurrent calls with one token grant once', async () => {
    play.product('t-b');
    const rs = await Promise.all([1, 2, 3].map(() => buy('alice', 'book_single', 't-b')));
    assert.deepEqual(rs.map((r) => r.status).sort(), ['alreadyGranted', 'alreadyGranted', 'granted']);
    assert.equal((await couple()).bookCredits, 1);
  });

  it('alreadyGranted retries a failed acknowledgement', async () => {
    play.product('t-b');
    play.acknowledgeProduct = async () => { throw new PlayApiError('boom', 503); };
    assert.equal((await buy('alice', 'book_single', 't-b')).status, 'granted');
    delete play.acknowledgeProduct; // back to the prototype method
    assert.equal((await buy('alice', 'book_single', 't-b')).status, 'alreadyGranted');
    assert.deepEqual(play.acks, [['product', 'book_single', 't-b']]);
  });

  it('a token used by another couple is permission-denied', async () => {
    play.product('t-b');
    await buy('alice', 'book_single', 't-b');
    await rejectsWith(buy('carol', 'book_single', 't-b', {}, 'c2'), 'permission-denied', /another couple/);
    assert.equal((await couple('c2')).bookCredits, undefined);
  });

  it('auth and membership', async () => {
    play.product('t-b');
    await rejectsWith(buy(null, 'book_single', 't-b'), 'unauthenticated');
    await rejectsWith(buy('carol', 'book_single', 't-b'), 'permission-denied');
    await rejectsWith(buy('alice', 'book_single', 't-b', {}, 'missing'), 'permission-denied');
    assert.equal(await purchase('t-b'), undefined);
  });

  it('input validation: unknown product, gift field, message length, package', async () => {
    play.product('t');
    await rejectsWith(buy('alice', 'premium_weekly', 't'), 'invalid-argument', /Unknown productId/);
    await rejectsWith(buy('alice', 'gift_book', 't'), 'invalid-argument', /gift/);
    await rejectsWith(buy('alice', 'gift_premium_1m', 't', { gift: {} }), 'invalid-argument', /gift/);
    await rejectsWith(buy('alice', 'gift_premium_1m', 't', { gift: { message: 'x'.repeat(301) } }), 'invalid-argument', /300/);
    await rejectsWith(buy('alice', 'book_single', ''), 'invalid-argument');
    await rejectsWith(call('alice', { coupleId: 'c1', productId: 'book_single', purchaseToken: 't', packageName: 'com.evil' }), 'invalid-argument', /packageName/);
    assert.equal((await buy('alice', 'gift_premium_1m', 't', { gift: { message: 'x'.repeat(300) } })).status, 'granted');
  });

  it('Play states and errors map to failed-precondition / unavailable', async () => {
    play.product('pending', { purchaseState: 2 });
    await rejectsWith(buy('alice', 'book_single', 'pending'), 'failed-precondition', /pending/);
    play.product('cancelled', { purchaseState: 1 });
    await rejectsWith(buy('alice', 'book_single', 'cancelled'), 'failed-precondition', /cancelled/);
    await rejectsWith(buy('alice', 'book_single', 'nope'), 'failed-precondition', /not recognise/);
    play.sub('expired', 'premium_monthly', Date.now() - DAY, { subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED' });
    await rejectsWith(buy('alice', 'premium_monthly', 'expired'), 'failed-precondition', /not active/);
    play.sub('grace', 'premium_monthly', Date.now() + DAY, { subscriptionState: 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD' });
    assert.equal((await buy('alice', 'premium_monthly', 'grace')).status, 'granted');
    play.sub('yearly', 'premium_yearly', Date.now() + DAY);
    await rejectsWith(buy('alice', 'premium_monthly', 'yearly'), 'failed-precondition', /different product/);
    play.product('t-ok');
    play.failWith = new PlayApiError('backend', 503);
    await rejectsWith(buy('alice', 'book_single', 't-ok'), 'unavailable');
    play.failWith = new PlayApiError('forbidden', 401);
    await rejectsWith(buy('alice', 'book_single', 't-ok'), 'unavailable');
    assert.equal((await couple()).bookCredits, undefined);
  });

  it('refuses a couple that is ending', async () => {
    await h.db().doc('couples/c1').update({ ending: { how: 'leftNow' } });
    play.product('t');
    await rejectsWith(buy('alice', 'book_single', 't'), 'failed-precondition', /ending/);
  });
});

describe('playBillingNotifications (RTDN)', () => {
  beforeEach(async () => {
    await h.clearAll();
    play = new FakePlay();
    setPlayVerifier(play);
    await h.db().doc('couples/c1').set({ memberIds: ['alice', 'bob'], inviteCode: 'AAA' });
  });
  after(() => setPlayVerifier(undefined));

  it('RENEWED moves until and subscriptionUntil forward (through the Pub/Sub function)', async () => {
    const exp1 = Date.now() + 2 * DAY;
    play.sub('t', 'premium_monthly', exp1);
    await buy('alice', 'premium_monthly', 't');
    const exp2 = exp1 + 30 * DAY;
    play.sub('t', 'premium_monthly', exp2, { acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED' });
    const n = { version: '1.0', packageName: PACKAGE_NAME, eventTimeMillis: String(Date.now()), subscriptionNotification: { version: '1.0', notificationType: 2, purchaseToken: 't', subscriptionId: 'premium_monthly' } };
    await playBillingNotifications({
      specversion: '1.0', id: 'e1', type: 'google.cloud.pubsub.topic.v1.messagePublished',
      source: '//pubsub.googleapis.com/projects/demo-couple/topics/play-billing', time: new Date().toISOString(),
      data: { message: { data: Buffer.from(JSON.stringify(n)).toString('base64'), messageId: 'm1', publishTime: new Date().toISOString() }, subscription: 's' },
    });
    const { premium } = await couple();
    assert.equal(premium.until.toMillis(), exp2);
    assert.equal(premium.subscriptionUntil.toMillis(), exp2);
    assert.equal(premium.source, 'subscription');
    assert.equal((await purchase('t')).expiryTime.toMillis(), exp2);
  });

  it('CANCELED keeps access until expiry; EXPIRED without gift ends at or before now', async () => {
    const exp = Date.now() + 10 * DAY;
    play.sub('t', 'premium_monthly', exp);
    await buy('alice', 'premium_monthly', 't');
    play.sub('t', 'premium_monthly', exp, { subscriptionState: 'SUBSCRIPTION_STATE_CANCELED' });
    assert.equal(await rtdnSub('t', 3), 'updated');
    assert.equal(await untilMs(), exp);
    const past = Date.now() - 1000;
    play.sub('t', 'premium_monthly', past, { subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED' });
    assert.equal(await rtdnSub('t', 13), 'updated');
    const { premium } = await couple();
    assert.ok(premium.until.toMillis() <= Date.now());
    assert.equal(premium.subscriptionUntil.toMillis(), past);
    assert.equal(premium.giftUntil, null);
  });

  it('REVOKED cuts a future expiry to now', async () => {
    const exp = Date.now() + 25 * DAY;
    play.sub('t', 'premium_yearly', exp);
    await buy('alice', 'premium_yearly', 't');
    // Play may still report the old expiry right after a revoke.
    const before = Date.now();
    assert.equal(await rtdnSub('t', 12, 'premium_yearly'), 'updated');
    const { premium } = await couple();
    near(premium.until.toMillis(), before);
    near(premium.subscriptionUntil.toMillis(), before);
    assert.equal((await purchase('t')).status, 'voided');
  });

  it('gift time survives subscription renewal, expiry and revoke', async () => {
    const exp = Date.now() + 5 * DAY;
    play.sub('t', 'premium_monthly', exp);
    await buy('alice', 'premium_monthly', 't');
    play.product('g');
    await buy('bob', 'gift_premium_1m', 'g', { gift: { message: 'more' } });
    const giftUntil = addMonths(exp, 1);
    assert.equal(await untilMs(), giftUntil);

    // Renewal past the gift end: subscription wins.
    const renewed = giftUntil + 3 * DAY;
    play.sub('t', 'premium_monthly', renewed);
    await rtdnSub('t', 2);
    let { premium } = await couple();
    assert.equal(premium.until.toMillis(), renewed);
    assert.equal(premium.giftUntil.toMillis(), giftUntil);

    // Revoke: back to the gift time, plan becomes gift.
    await rtdnSub('t', 12);
    ({ premium } = await couple());
    assert.equal(premium.until.toMillis(), giftUntil);
    assert.equal(premium.plan, 'gift');
    assert.equal(premium.source, 'gift');
  });

  it('a renewal shorter than the gift keeps the gift end', async () => {
    const exp = Date.now() + 5 * DAY;
    play.sub('t', 'premium_monthly', exp);
    await buy('alice', 'premium_monthly', 't');
    play.product('g');
    await buy('bob', 'gift_premium_3m', 'g', { gift: { message: '' } });
    const giftUntil = addMonths(exp, 3);
    play.sub('t', 'premium_monthly', exp + 30 * DAY);
    await rtdnSub('t', 2);
    assert.equal(await untilMs(), giftUntil);
    play.sub('t', 'premium_monthly', Date.now() - 1, { subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED' });
    await rtdnSub('t', 13);
    assert.equal(await untilMs(), giftUntil);
  });

  it('unknown tokens, other packages and test notifications are ignored', async () => {
    assert.equal(await rtdnSub('never-verified', 4), 'unknownToken');
    assert.equal(await handlePlayNotification({ packageName: 'com.other', subscriptionNotification: { notificationType: 2, purchaseToken: 'x' } }), 'otherPackage');
    assert.equal(await handlePlayNotification({ packageName: PACKAGE_NAME, testNotification: { version: '1.0' } }), 'test');
  });

  it('transient Play errors are thrown (so Pub/Sub retries)', async () => {
    play.sub('t', 'premium_monthly', Date.now() + DAY);
    await buy('alice', 'premium_monthly', 't');
    play.failWith = new PlayApiError('busy', 503);
    await assert.rejects(rtdnSub('t', 2), /busy/);
    play.failWith = new PlayApiError('gone', 410);
    assert.equal(await rtdnSub('t', 2), 'lookupFailed');
  });

  it('voided book: removes an unused credit once; with none left only marks voided', async () => {
    play.product('b1');
    play.product('b2');
    await buy('alice', 'book_single', 'b1');
    await buy('alice', 'gift_book', 'b2', { gift: { message: '' } });
    assert.equal((await couple()).bookCredits, 2);
    const voided = (token) => handlePlayNotification({ packageName: PACKAGE_NAME, voidedPurchaseNotification: { purchaseToken: token, orderId: `GPA.${token}`, productType: 2, refundType: 1 } });

    assert.equal(await voided('b1'), 'voidedCreditRemoved');
    assert.equal((await couple()).bookCredits, 1);
    const p = await purchase('b1');
    assert.equal(p.status, 'voided');
    assert.equal(p.creditRemoved, true);
    assert.ok(p.voidedAt instanceof Timestamp);
    assert.equal(await voided('b1'), 'alreadyVoided');
    assert.equal((await couple()).bookCredits, 1);

    await h.db().doc('couples/c1').update({ bookCredits: 0 }); // the credit was used
    assert.equal(await voided('b2'), 'voided');
    assert.equal((await couple()).bookCredits, 0);
    assert.equal((await purchase('b2')).creditRemoved, false);
    assert.equal(await voided('unknown'), 'unknownToken');
  });

  it('a voided subscription is treated as revoked', async () => {
    play.sub('t', 'premium_monthly', Date.now() + 20 * DAY);
    await buy('alice', 'premium_monthly', 't');
    const before = Date.now();
    assert.equal(await handlePlayNotification({ packageName: PACKAGE_NAME, voidedPurchaseNotification: { purchaseToken: 't', productType: 1 } }), 'updated');
    near(await untilMs(), before);
  });
});

describe('endCouple and purchases', () => {
  beforeEach(async () => {
    await h.clearAll();
    play = new FakePlay();
    setPlayVerifier(play);
  });
  after(() => setPlayVerifier(undefined));

  it('deletes couples/{cid}/books/ files and gifts, keeps purchases for audit, ignores later RTDNs', async () => {
    await h.seedCouple('c1');
    await h.putFile('couples/c1/books/b1/book.pdf');
    await h.putFile('couples/c1/books/b1/pages/1.jpg');
    play.product('g');
    await buy('alice', 'gift_book', 'g', { gift: { message: '' } });
    play.sub('t', 'premium_monthly', Date.now() + DAY);
    await buy('alice', 'premium_monthly', 't');

    const r = await endCouple('c1', 'leftNow');
    assert.equal(r.counts.storageFiles, 8);
    assert.equal(r.counts.subcollectionDocs.gifts, 1);
    assert.deepEqual(await h.listFiles('couples/c1/books/'), []);
    assert.equal((await purchase('g')).coupleId, 'c1');
    assert.equal((await purchase('t')).coupleId, 'c1');
    assert.equal(await rtdnSub('t', 2), 'coupleGone');
    assert.equal((await h.db().doc('couples/c1').get()).exists, false, 'RTDN does not recreate the couple');
  });
});
