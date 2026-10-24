// Port of firestore-tests/test/avatar-stickers.rules.test.js: avatar fields on
// profiles and couple sticker messages.
import { describe, it } from "node:test";
import { ST, admin, as, denied, ok, useDb } from "./rules-helpers.js";

const C = "couple1";
const avatar = { skin: "skin4", face: "oval", hair: "long", hairColor: "black", eyes: "round", eyeColor: "brown", brows: "soft", facialHair: "none", glasses: "none", accessory: "earrings", faceAccessory: "bindi", outfit: "saree", outfitColor: "rose", background: "blush" };
const sticker = (o: Record<string, unknown> = {}) => ({
  senderId: "alice", type: "sticker", text: "Same moon, different windows.",
  sticker: { id: "miss-moon", category: "missYou" }, sentAt: ST,
  seen: false, reactions: {}, imageUrl: null, imageAspectRatio: null, ...o,
});
const messages = `couples/${C}/messages`;

useDb(async () => {
  await admin.set(`couples/${C}`, { memberIds: ["alice", "bob"], inviteCode: "ABC234" });
  await admin.set("users/alice", { displayName: "Alice", coupleId: C });
  await admin.set("users/bob", { displayName: "Bob", coupleId: C });
});

describe("avatar and sticker rules", () => {
  it("saves my avatar (merge) and my partner can see it", async () => {
    await ok(as("alice").set("users/alice", { avatar, avatarAsPhoto: true }, { merge: true }));
    await ok(as("bob").get("users/alice"));
  });
  it("a first-time profile can include an avatar", async () => {
    await ok(as("carol").set("users/carol", { displayName: "Carol", avatar }));
  });
  it("rejects malformed avatar fields", async () => {
    const big = Object.fromEntries(Array.from({ length: 30 }, (_, i) => [`k${i}`, "x"]));
    await denied(as("alice").set("users/alice", { avatar: "not a map" }, { merge: true }));
    await denied(as("alice").set("users/alice", { avatar: big }, { merge: true }));
    await denied(as("alice").set("users/alice", { avatarAsPhoto: "yes" }, { merge: true }));
  });
  it("nobody else edits my avatar", async () => {
    await denied(as("bob").set("users/alice", { avatar }, { merge: true }));
  });
  it("sends a sticker; partner can react but not change it", async () => {
    const id = await ok(as("alice").add(messages, sticker()));
    await ok(as("bob").update(`${messages}/${id}`, { reactions: { bob: "❤️" } }));
    await denied(as("bob").update(`${messages}/${id}`, { text: "changed" }));
  });
  it("rejects malformed stickers", async () => {
    const send = (o: Record<string, unknown>) => as("alice").add(messages, sticker(o));
    await denied(send({ sticker: "junk" }));
    await denied(send({ sticker: { id: "" } }));
    await denied(send({ text: "x".repeat(401) }));
    await denied(send({ senderId: "bob" }));
  });
  it("ordinary messages are unaffected", async () => {
    await ok(as("alice").add(messages, { senderId: "alice", type: "text", text: "hi", sentAt: ST }));
  });
});
