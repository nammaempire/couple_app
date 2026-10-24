// Port of firestore-tests/test/chat-look.rules.test.js:
// couples/{id}/settings/chatLook and the chat-look fields on profiles.
import { describe, it } from "node:test";
import { ST, admin, as, denied, ok, useDb } from "./rules-helpers.js";

const C = "couple1";
const look = (id = "chatLook") => `couples/${C}/settings/${id}`;
const data = (o: Record<string, unknown> = {}) => ({
  color: 0xff3f6ad8,
  background: { kind: "pattern", patternId: "hearts", photoUrl: null, storagePath: null, dim: 0.25, blur: 0 },
  updatedBy: "alice", updatedAt: ST, ...o,
});

useDb(async () => {
  await admin.set(`couples/${C}`, { memberIds: ["alice", "bob"], inviteCode: "ABC234" });
  await admin.set("users/alice", { displayName: "Alice", coupleId: C });
});

describe("chat look rules", () => {
  it("either partner sets the shared look; both read it", async () => {
    await ok(as("alice").set(look(), data()));
    await ok(as("bob").get(look()));
    await ok(as("bob").set(look(), data({ color: null, updatedBy: "bob",
      background: { kind: "photo", photoUrl: "https://firebasestorage.googleapis.com/x", storagePath: `couples/${C}/backgrounds/a.jpg`, dim: 0.4, blur: 6 } })));
  });
  it("strangers cannot read or write it", async () => {
    await admin.set(look(), data());
    await denied(as("eve").get(look()));
    await denied(as("eve").set(look(), data({ updatedBy: "eve" })));
  });
  it("rejects bad values", async () => {
    const bg = (o: Record<string, unknown>) => ({ kind: "photo", photoUrl: "https://x.y/z", dim: 0.2, blur: 2, ...o });
    await denied(as("alice").set(look(), data({ updatedBy: "bob" })));
    await denied(as("alice").set(look(), data({ color: "red" })));
    await denied(as("alice").set(look(), data({ background: bg({ kind: "video" }) })));
    await denied(as("alice").set(look(), data({ background: bg({ dim: 0.95 }) })));
    await denied(as("alice").set(look(), data({ background: bg({ blur: 40 }) })));
    await denied(as("alice").set(look(), data({ background: bg({ photoUrl: "http://insecure/x" }) })));
    await denied(as("alice").set(look("other"), data()));
  });
  it("nobody deletes it", async () => {
    await ok(as("alice").set(look(), data()));
    await denied(as("alice").delete(look()));
  });
  it("a person saves their own personal look on their profile", async () => {
    await ok(as("alice").set("users/alice",
      { chatLookMode: "personal", chatLook: { color: 1, background: { kind: "none" } } }, { merge: true }));
    await denied(as("bob").set("users/alice", { chatLookMode: "shared" }, { merge: true }));
  });
});
