// Rules with no emulator suite: pairing by invite code (couple + invite +
// profile written together), love notes and their sealed words, calendar
// events, and the simple shared collections. Not a port; checks the ported
// rules against firestore.rules directly.
import { describe, it } from "node:test";
import { DAY, ST, DEL, admin, ts, as, denied, fromNow, hidden, ok, useDb } from "./rules-helpers.js";

const C = "couple1";

useDb(async () => {
  await admin.set(`couples/${C}`, { memberIds: ["alice", "bob"], inviteCode: "ABC234" });
  await admin.set("users/alice", { displayName: "Alice", coupleId: C });
  await admin.set("users/bob", { displayName: "Bob", coupleId: C });
});

describe("profiles", () => {
  it("strangers cannot read a profile; new profiles start unpaired", async () => {
    await ok(as("bob").get("users/alice"));
    await denied(as("carol").get("users/alice"));
    await denied(as("carol").set("users/carol", { displayName: "Carol", coupleId: C }));
    await denied(as("carol").set("users/carol", { displayName: "Carol", pairingEndedAt: null }));
    await ok(as("carol").set("users/carol", { displayName: "Carol", coupleId: null }));
    await denied(as("alice").delete("users/alice"));
  });
  it("coupleId can only point at a couple you are in", async () => {
    await admin.set("couples/other", { memberIds: ["dave"], inviteCode: "OTHER2" });
    await denied(as("alice").update("users/alice", { coupleId: "other" }));
    await ok(as("alice").update("users/alice", { coupleId: null }));
    await ok(as("alice").update("users/alice", { coupleId: C }));
  });
});

describe("pairing by invite code", () => {
  it("create a couple of one with its invite and link the profile in one batch", async () => {
    await ok(as("carol").set("users/carol", { displayName: "Carol", coupleId: null }));
    await ok(as("carol").batch()
      .set("couples/c2", { memberIds: ["carol"], inviteCode: "CODE22" })
      .set("invites/CODE22", { coupleId: "c2", createdBy: "carol", used: false, createdAt: ST })
      .update("users/carol", { coupleId: "c2" })
      .commit());
    // The invite id must be the couple's code; the couple must be yours.
    await denied(as("carol").set("invites/WRONG2", { coupleId: "c2", createdBy: "carol", used: false }));
    await denied(as("carol").set("invites/ABC234", { coupleId: C, createdBy: "carol", used: false }));
    // Codes can be fetched but not listed.
    await ok(as("dave").get("invites/CODE22"));
    await hidden(as("dave").query({ collection: "invites" }));
  });

  it("joining consumes the invite in the same transaction; nobody else can be added", async () => {
    await admin.set("couples/c2", { memberIds: ["carol"], inviteCode: "CODE22" });
    await admin.set("invites/CODE22", { coupleId: "c2", createdBy: "carol", used: false, createdAt: fromNow(-DAY) });
    await admin.set("users/dave", { displayName: "Dave", coupleId: null });
    // Not without using the invite.
    await denied(as("dave").update("couples/c2", { memberIds: ["carol", "dave"], activatedAt: ST }));
    // Not adding someone else.
    await denied(as("dave").batch()
      .update("couples/c2", { memberIds: ["carol", "erin"] })
      .update("invites/CODE22", { used: true, usedBy: "dave", usedAt: ST })
      .commit());
    // Not touching other couple fields while joining.
    await denied(as("dave").batch()
      .update("couples/c2", { memberIds: ["carol", "dave"], premium: true })
      .update("invites/CODE22", { used: true, usedBy: "dave", usedAt: ST })
      .commit());
    await ok(as("dave").batch()
      .update("couples/c2", { memberIds: ["carol", "dave"], activatedAt: ST })
      .update("invites/CODE22", { used: true, usedBy: "dave", usedAt: ST })
      .update("users/dave", { coupleId: "c2" })
      .commit());
    await ok(as("carol").get("users/dave"));
    // A full couple can't be joined, and a used invite can't be reused.
    await denied(as("erin").batch()
      .update("couples/c2", { memberIds: ["carol", "dave", "erin"] })
      .update("invites/CODE22", { used: true, usedBy: "erin", usedAt: ST })
      .commit());
  });

  it("members can leave but not add; a couple of one can be cancelled by its creator", async () => {
    await denied(as("alice").update(`couples/${C}`, { memberIds: ["alice", "bob", "carol"] }));
    await denied(as("alice").update(`couples/${C}`, { memberIds: ["alice"] }));
    await denied(as("bob").delete(`couples/${C}`));
    await ok(as("alice").update(`couples/${C}`, { memberIds: ["bob"] }));
    await denied(as("alice").get(`couples/${C}`));
    await admin.set("couples/c3", { memberIds: ["carol"], inviteCode: "C3C3C3" });
    await denied(as("dave").delete("couples/c3"));
    await ok(as("carol").delete("couples/c3"));
    await denied(as("carol").set("couples/c4", { memberIds: ["carol", "dave"], inviteCode: "C4C4C4" }));
    await ok(as("carol").set("couples/c4", { memberIds: ["carol"], inviteCode: "C4C4C4" }));
  });

  it("invites expire after a week; the creator renews the same code", async () => {
    await admin.set("couples/c5", { memberIds: ["carol"], inviteCode: "OLD555" });
    await admin.set("invites/OLD555", { coupleId: "c5", createdBy: "carol", used: false, createdAt: fromNow(-8 * DAY) });
    await admin.set("users/dave", { displayName: "Dave", coupleId: null });
    const join = () =>
      as("dave").batch()
        .update("couples/c5", { memberIds: ["carol", "dave"], activatedAt: ST })
        .update("invites/OLD555", { used: true, usedBy: "dave", usedAt: ST })
        .update("users/dave", { coupleId: "c5" })
        .commit();
    await denied(join());
    // Only the creator renews, only the time, and only to now.
    await denied(as("dave").update("invites/OLD555", { createdAt: ST }));
    await denied(as("carol").update("invites/OLD555", { createdAt: fromNow(30 * DAY) }));
    await denied(as("carol").update("invites/OLD555", { createdAt: ST, coupleId: "c2" }));
    await ok(as("carol").update("invites/OLD555", { createdAt: ST }));
    await ok(join());
    // A new invite can't be back- or forward-dated.
    await admin.set("couples/c6", { memberIds: ["erin"], inviteCode: "NEW666" });
    await denied(as("erin").set("invites/NEW666", { coupleId: "c6", createdBy: "erin", used: false, createdAt: fromNow(30 * DAY) }));
  });

  it("the invite creator withdraws it; only the joiner marks it used", async () => {
    await admin.set("invites/ABC234", { coupleId: C, createdBy: "alice", used: false });
    await denied(as("bob").update("invites/ABC234", { used: true, usedBy: "carol" }));
    await denied(as("bob").delete("invites/ABC234"));
    await ok(as("alice").delete("invites/ABC234"));
  });
});

describe("love notes", () => {
  const notes = `couples/${C}/notes`;
  it("the envelope and sealed words are written together; words unlock at delivery", async () => {
    const later = fromNow(3 * DAY);
    await ok(as("alice").batch()
      .set(`${notes}/n1`, { senderId: "alice", recipientId: "bob", deliverAt: later, openedAt: null })
      .set(`${notes}/n1/sealed/content`, { senderId: "alice", recipientId: "bob", deliverAt: later, text: "hi" })
      .commit());
    await ok(as("bob").get(`${notes}/n1`));
    await ok(as("alice").get(`${notes}/n1/sealed/content`));
    await denied(as("bob").get(`${notes}/n1/sealed/content`));
    await hidden(as("alice").query({ collection: `${notes}/n1/sealed` }));
    // Not openable before delivery; sealed words are never rewritten.
    await denied(as("bob").update(`${notes}/n1`, { openedAt: ST }));
    await denied(as("alice").set(`${notes}/n1/sealed/content`, { senderId: "alice", recipientId: "bob", deliverAt: later, text: "x" }));
    // Bob can't unsend Alice's note.
    await denied(as("bob").delete(`${notes}/n1`));
  });

  it("delivered notes: recipient reads and opens; bad envelopes are refused", async () => {
    const past = fromNow(-DAY);
    await admin.set(`${notes}/n2`, { senderId: "alice", recipientId: "bob", deliverAt: past, openedAt: null });
    await admin.set(`${notes}/n2/sealed/content`, { senderId: "alice", recipientId: "bob", deliverAt: past, text: "hi" });
    await ok(as("bob").get(`${notes}/n2/sealed/content`));
    await denied(as("bob").update(`${notes}/n2`, { openedAt: ST, text: "x" }));
    await ok(as("bob").update(`${notes}/n2`, { openedAt: ST }));
    await denied(as("alice").set(`${notes}/n3`, { senderId: "alice", recipientId: "alice", deliverAt: past, openedAt: null }));
    await denied(as("alice").set(`${notes}/n3`, { senderId: "alice", recipientId: "carol", deliverAt: past, openedAt: null }));
    await denied(as("alice").set(`${notes}/n3`, { senderId: "alice", recipientId: "bob", deliverAt: past }));
    // Sealed words must match an envelope you sent, under the id 'content'.
    await denied(as("alice").set(`${notes}/n2/sealed/other`, { senderId: "alice", recipientId: "bob", deliverAt: past }));
    await denied(as("bob").set(`${notes}/n2/sealed/content`, { senderId: "bob", recipientId: "bob", deliverAt: past }));
    await ok(as("alice").delete(`${notes}/n2/sealed/content`));
    await ok(as("alice").delete(`${notes}/n2`));
  });
});

describe("calendar events", () => {
  const events = `couples/${C}/events`;
  it("a private event is visible only to its creator; only they change visibility", async () => {
    await ok(as("alice").set(`${events}/e1`, { title: "Surprise", private: true, createdBy: "alice" }));
    await ok(as("alice").set(`${events}/e2`, { title: "Dinner", private: false, createdBy: "alice" }));
    await denied(as("alice").set(`${events}/e3`, { title: "x", createdBy: "alice" }));
    await denied(as("bob").set(`${events}/e3`, { title: "x", private: false, createdBy: "alice" }));
    await denied(as("bob").get(`${events}/e1`));
    await ok(as("bob").get(`${events}/e2`));
    const seen = await as("bob").query({ collection: events });
    if (seen.length !== 1 || seen[0].id !== "e2") throw new Error("bob should see only the shared event");
    await ok(as("bob").update(`${events}/e2`, { title: "Dinner at 8" }));
    await denied(as("bob").update(`${events}/e2`, { private: true }));
    await denied(as("bob").update(`${events}/e2`, { createdBy: "bob" }));
    await ok(as("alice").update(`${events}/e2`, { private: true }));
    await denied(as("bob").delete(`${events}/e1`));
    await ok(as("alice").delete(`${events}/e1`));
  });
});

describe("simple shared collections", () => {
  const p = (name: string) => `couples/${C}/${name}`;
  it("memories stay credited to who added them", async () => {
    await ok(as("alice").set(p("memories/m1"), { title: "Goa", createdBy: "alice" }));
    await denied(as("alice").set(p("memories/m2"), { title: "x", createdBy: "bob" }));
    await ok(as("bob").update(p("memories/m1"), { title: "Goa 2026" }));
    await denied(as("bob").update(p("memories/m1"), { createdBy: "bob" }));
    await denied(as("bob").delete(p("memories/m1")));
    await ok(as("alice").delete(p("memories/m1")));
    await denied(as("carol").get(p("memories/m1")));
  });
  it("moods: your own document only", async () => {
    await ok(as("alice").set(p("moods/alice"), { mood: "happy" }));
    await denied(as("alice").set(p("moods/bob"), { mood: "sad" }));
    await ok(as("bob").get(p("moods/alice")));
    await ok(as("alice").delete(p("moods/alice")));
  });
  it("daily questions: each writes only their own answer; nobody deletes", async () => {
    const day = p("dailyQuestions/2026-10-24");
    await ok(as("alice").set(day, { prompt: "Q?", date: "2026-10-24", answers: { alice: { text: "a" } } }));
    await ok(as("bob").set(day, { answers: { bob: { text: "b" } } }, { merge: true }));
    // Changing your own answer is fine; the partner's or the prompt is not.
    await ok(as("bob").set(day, { answers: { bob: { text: "b2" } } }, { merge: true }));
    await denied(as("bob").set(day, { answers: { alice: { text: "hacked" } } }, { merge: true }));
    await denied(as("bob").update(day, { "answers.alice": DEL }));
    await denied(as("bob").update(day, { prompt: "Other?" }));
    await denied(as("bob").set(day, { answers: { bob: { text: "b" } } }));
    // Creating: only your own answer, and the date must be the document's.
    await denied(as("alice").set(p("dailyQuestions/2026-10-25"), { answers: { bob: { text: "x" } } }));
    await denied(as("alice").set(p("dailyQuestions/2026-10-26"), { date: "2026-10-27", answers: {} }));
    await denied(as("alice").set(p("dailyQuestions/tomorrow"), { answers: { alice: { text: "x" } } }));
    await denied(as("alice").delete(day));
    await denied(as("carol").set(p("dailyQuestions/2026-10-25"), {}));
  });
  it("calls: ring as yourself to your partner; one call at a time", async () => {
    const callDoc = p("call/current");
    const ring = (from: string, to: string, channelName: string, extra: object = {}) => ({
      callerId: from,
      calleeId: to,
      type: "voice",
      status: "ringing",
      channelName,
      startedAt: ST,
      answeredAt: null,
      endedAt: null,
      ...extra,
    });
    await denied(as("alice").set(callDoc, ring("bob", "alice", "chan00001")));
    await denied(as("alice").set(callDoc, ring("alice", "carol", "chan00001")));
    await denied(as("alice").set(callDoc, ring("alice", "bob", "chan00001", { type: "fax" })));
    await ok(as("alice").set(callDoc, ring("alice", "bob", "chan00001")));
    // Bob calling at the same moment can't replace Alice's ringing call.
    await denied(as("bob").set(callDoc, ring("bob", "alice", "chan00002")));
    // Only the callee answers; the call's details can't be changed.
    await denied(as("alice").update(callDoc, { status: "accepted" }));
    await denied(as("bob").update(callDoc, { channelName: "chan99999" }));
    await ok(as("bob").update(callDoc, { status: "accepted", answeredAt: ST }));
    await denied(as("alice").set(callDoc, ring("alice", "bob", "chan00003")));
    await ok(as("alice").update(callDoc, { status: "ended", endedAt: ST }));
    await denied(as("bob").update(callDoc, { status: "accepted" }));
    // Once it's over, a new call may ring on the same document.
    await ok(as("bob").set(callDoc, ring("bob", "alice", "chan00004", { type: "video" })));
    await ok(as("alice").update(callDoc, { status: "declined", endedAt: ST }));
    await ok(as("bob").delete(callDoc));
  });
  it("calls: a ring nobody ended long ago doesn't block the next call", async () => {
    const callDoc = p("call/current");
    await admin.set(callDoc, {
      callerId: "alice",
      calleeId: "bob",
      type: "voice",
      status: "ringing",
      channelName: "chanStale1",
      startedAt: ts(Date.now() - 2 * 60_000),
    });
    await ok(
      as("bob").set(callDoc, {
        callerId: "bob",
        calleeId: "alice",
        type: "voice",
        status: "ringing",
        channelName: "chanFresh1",
        startedAt: ST,
      }),
    );
  });
  it("nudges are append-only, sent as yourself", async () => {
    const id = await ok(as("alice").add(p("nudges"), { senderId: "alice", sentAt: ST }));
    await denied(as("alice").add(p("nudges"), { senderId: "bob", sentAt: ST }));
    await denied(as("alice").update(p(`nudges/${id}`), { seen: true }));
    await denied(as("alice").delete(p(`nudges/${id}`)));
    await denied(as("carol").get(p(`nudges/${id}`)));
  });
});
