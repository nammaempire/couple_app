// Port of firestore-tests/test/chat-privacy.rules.test.js: "Clear chat for
// both", system messages and the shared screenshot-blocking switch.
import { describe, it } from "node:test";
import { ST, admin, as, denied, fromNow, ok, useDb } from "./rules-helpers.js";

const C = "couple1";
const couple = `couples/${C}`;
const messages = `couples/${C}/messages`;
const msg = (id: string) => `${messages}/${id}`;

useDb(async () => {
  await admin.set(couple, { memberIds: ["alice", "bob"], inviteCode: "ABC234" });
  const old = fromNow(-60000);
  await admin.set(msg("a1"), { senderId: "alice", type: "text", text: "hi", sentAt: old });
  await admin.set(msg("b1"), { senderId: "bob", type: "text", text: "hey", sentAt: old });
  await admin.set(msg("b2"), { senderId: "bob", type: "text", text: "later", sentAt: fromNow(3600000) });
});

describe("chat privacy rules", () => {
  it("without a clear, you can't delete your partner's messages", async () => {
    await denied(as("alice").delete(msg("b1")));
    await ok(as("alice").delete(msg("a1")));
  });

  it("clear for both: stamp server time, then either deletes up to it", async () => {
    await ok(as("alice").update(couple, { chatClearedAt: ST, chatClearedBy: "alice" }));
    await ok(as("alice").delete(msg("b1")));
    await ok(as("alice").delete(msg("a1")));
    // A message sent after the clear is still protected.
    await denied(as("alice").delete(msg("b2")));
  });

  it("the clear stamp must be server time and your own uid", async () => {
    await denied(as("alice").update(couple, { chatClearedAt: fromNow(86400000) }));
    await denied(as("alice").update(couple, { chatClearedAt: ST, chatClearedBy: "bob" }));
    await denied(as("carol").update(couple, { chatClearedAt: ST }));
  });

  it("system messages: sent as yourself; partner cannot delete them", async () => {
    const id = await ok(as("alice").add(messages,
      { senderId: "alice", type: "screenshot", text: "📸 Alice took a screenshot", sentAt: ST }));
    await denied(as("alice").add(messages, { senderId: "bob", type: "screenshot", text: "fake", sentAt: ST }));
    await denied(as("bob").delete(msg(id)));
    await denied(as("bob").update(msg(id), { text: "edited" }));
  });

  it("system messages are short text only and cannot be reacted to or pinned", async () => {
    const send = (o: Record<string, unknown>) => as("alice").add(messages,
      { senderId: "alice", type: "chatCleared", text: "Alice cleared the chat", sentAt: ST, seen: true, ...o });
    await denied(send({ text: "x".repeat(201) }));
    await denied(send({ imageUrl: "https://x/y.jpg" }));
    await denied(send({ reactions: { bob: "❤️" } }));
    const id = await ok(send({}));
    await denied(as("bob").update(msg(id), { reactions: { bob: "❤️" } }));
    await denied(as("bob").update(msg(id), { pinned: true }));
    await ok(as("bob").update(msg(id), { seen: true }));
  });

  it("clear for both deletes 400 messages in one batch", async () => {
    const old = fromNow(-60000);
    const seed = admin.batch();
    for (let i = 0; i < 400; i++) {
      seed.set(msg(`m${i}`), { senderId: i % 2 ? "bob" : "alice", type: "text", text: `${i}`, sentAt: old });
    }
    await seed.commit();
    await ok(as("alice").update(couple, { chatClearedAt: ST, chatClearedBy: "alice" }));
    const batch = as("alice").batch();
    for (let i = 0; i < 400; i++) batch.delete(msg(`m${i}`));
    await ok(batch.commit());
  });

  it("either partner flips the shared screenshot switch; it must be a bool", async () => {
    await ok(as("bob").update(couple, { blockScreenshots: true }));
    await ok(as("alice").update(couple, { blockScreenshots: false }));
    await denied(as("alice").update(couple, { blockScreenshots: "yes" }));
    await denied(as("carol").update(couple, { blockScreenshots: true }));
  });

  it("clear for me is just your own profile field", async () => {
    await admin.set("users/alice", { displayName: "Alice", coupleId: C });
    await ok(as("alice").update("users/alice", { chatClearedAt: ST }));
    await denied(as("bob").update("users/alice", { chatClearedAt: ST }));
  });
});
