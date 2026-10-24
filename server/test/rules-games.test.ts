// Port of firestore-tests/test/games.rules.test.js: couples/{id}/games —
// invites, turns, moveCount, frozen games and the hidden quiz answers.
import { describe, it } from "node:test";
import { ST, admin, as, denied, ok, useDb } from "./rules-helpers.js";

type O = Record<string, unknown>;
const C = "couple1";
const g = (id = "g1") => `couples/${C}/games/${id}`;
const secret = (id = "g1") => `couples/${C}/games/${id}/secret/answers`;

const invite = (o: O = {}) => ({
  type: "ticTacToe", status: "invited", createdBy: "alice", invitee: "bob",
  players: ["alice", "bob"], turn: null, state: {}, winner: null, moveCount: 0,
  createdAt: ST, updatedAt: ST, finishedAt: null, ...o,
});

const seed = (data: O) => admin.set(g(), data);
const active = (o: O = {}) => ({ ...invite(), status: "active", turn: "alice", moveCount: 1, createdAt: 1, state: { board: [] }, ...o });

useDb(async () => {
  await admin.set(`couples/${C}`, { memberIds: ["alice", "bob"], inviteCode: "ABC234" });
});

describe("games: invites", () => {
  it("a member invites their partner", async () => {
    await ok(as("alice").set(g(), invite()));
    await ok(as("bob").get(g()));
  });
  it("rejects bad invites", async () => {
    await denied(as("alice").set(g(), invite({ invitee: "alice", players: ["alice", "alice"] })));
    await denied(as("alice").set(g(), invite({ invitee: "eve", players: ["alice", "eve"] })));
    await denied(as("alice").set(g(), invite({ createdBy: "bob", invitee: "alice", players: ["bob", "alice"] })));
    await denied(as("alice").set(g(), invite({ status: "active" })));
    await denied(as("alice").set(g(), invite({ type: "poker" })));
    await denied(as("alice").set(g(), invite({ moveCount: 3 })));
    await denied(as("eve").set(g(), invite({ createdBy: "eve", invitee: "bob", players: ["eve", "bob"] })));
  });
  it("only the invitee accepts", async () => {
    await seed({ ...invite(), createdAt: 1 });
    await denied(as("alice").update(g(), { status: "active", turn: "alice", moveCount: 1 }));
    await ok(as("bob").update(g(), { status: "active", turn: "alice", moveCount: 1 }));
  });
  it("either player can decline or withdraw", async () => {
    await seed({ ...invite(), createdAt: 1 });
    await ok(as("alice").update(g(), { status: "cancelled", turn: null, moveCount: 1 }));
  });
  it("strangers cannot read or touch games", async () => {
    await seed({ ...invite(), createdAt: 1 });
    await denied(as("eve").get(g()));
    await denied(as("eve").update(g(), { status: "cancelled", turn: null, moveCount: 1 }));
  });
});

describe("games: turns", () => {
  it("only the player whose turn it is can move", async () => {
    await seed(active());
    await denied(as("bob").update(g(), { state: { board: ["X"] }, turn: "alice", moveCount: 2 }));
    await ok(as("alice").update(g(), { state: { board: ["X"] }, turn: "bob", moveCount: 2 }));
  });
  it("moveCount must go up by exactly one (no double moves)", async () => {
    await seed(active());
    await denied(as("alice").update(g(), { state: { board: ["X"] }, turn: "bob", moveCount: 1 }));
    await denied(as("alice").update(g(), { state: { board: ["X"] }, turn: "bob", moveCount: 3 }));
  });
  it("the next turn must be a player; no winner while active", async () => {
    await seed(active());
    await denied(as("alice").update(g(), { turn: "eve", moveCount: 2 }));
    await denied(as("alice").update(g(), { turn: "bob", winner: "alice", moveCount: 2 }));
  });
  it("the mover can finish with a winner or a draw", async () => {
    await seed(active());
    await ok(as("alice").update(g(), { status: "finished", turn: null, winner: "alice", moveCount: 2 }));
    await seed(active());
    await ok(as("alice").update(g(), { status: "finished", turn: null, winner: "draw", moveCount: 2 }));
    await seed(active());
    await denied(as("alice").update(g(), { status: "finished", turn: null, winner: "eve", moveCount: 2 }));
  });
  it("either player can leave an active game, even off-turn", async () => {
    await seed(active());
    await ok(as("bob").update(g(), { status: "cancelled", turn: null, moveCount: 2 }));
  });
  it("leaving cannot sneak in a board change", async () => {
    await seed(active());
    await denied(as("bob").update(g(), { status: "cancelled", turn: null, moveCount: 2, state: { board: ["O"] } }));
  });
  it("fixed fields never change", async () => {
    await seed(active());
    await denied(as("alice").update(g(), { type: "connectFour", turn: "bob", moveCount: 2 }));
    await denied(as("alice").update(g(), { invitee: "alice", turn: "bob", moveCount: 2 }));
  });
  it("finished and cancelled games are frozen; nobody deletes", async () => {
    await seed(active({ status: "finished", turn: null, winner: "alice" }));
    await denied(as("bob").update(g(), { status: "cancelled", turn: null, moveCount: 2 }));
    await denied(as("alice").update(g(), { winner: "bob", moveCount: 2 }));
    await denied(as("alice").delete(g()));
  });
});

describe("games: know-me quiz secrets", () => {
  const quiz = (state: O, o: O = {}) => active({ type: "knowMe", turn: "alice", state: { subject: "alice", questions: ["q1", "q2"], ...state }, ...o });

  it("the subject writes answers and hands over the turn in one batch", async () => {
    await seed(quiz({}));
    const b = as("alice").batch();
    b.set(secret(), { subject: "alice", answers: [0, 2] });
    b.update(g(), { turn: "bob", state: { subject: "alice", questions: ["q1", "q2"], answered: true }, moveCount: 2 });
    await ok(b.commit());
    await ok(as("alice").get(secret()));
  });
  it("the guesser cannot peek before locking in guesses", async () => {
    await seed(quiz({ answered: true }, { turn: "bob" }));
    await admin.set(secret(), { subject: "alice", answers: [0, 2] });
    await denied(as("bob").get(secret()));
  });
  it("after locking guesses, the guesser can read the answers", async () => {
    await seed(quiz({ answered: true }, { turn: "bob" }));
    await admin.set(secret(), { subject: "alice", answers: [0, 2] });
    await ok(as("bob").update(g(), {
      turn: "bob", moveCount: 2,
      state: { subject: "alice", questions: ["q1", "q2"], answered: true, guesses: [0, 1], guessesLocked: true },
    }));
    await ok(as("bob").get(secret()));
  });
  it("locked guesses cannot change", async () => {
    await seed(quiz({ answered: true, guesses: [0, 1], guessesLocked: true }, { turn: "bob" }));
    await denied(as("bob").update(g(), {
      turn: "bob", moveCount: 2,
      state: { subject: "alice", questions: ["q1", "q2"], answered: true, guesses: [0, 2], guessesLocked: true },
    }));
    await ok(as("bob").update(g(), {
      status: "finished", turn: null, moveCount: 2,
      state: { subject: "alice", questions: ["q1", "q2"], answered: true, guesses: [0, 1], guessesLocked: true, score: 1 },
    }));
  });
  it("only the subject, on their turn, can write answers; never rewritten", async () => {
    await seed(quiz({}));
    await denied(as("bob").set(secret(), { subject: "bob", answers: [1, 1] }));
    await denied(as("bob").set(secret(), { subject: "alice", answers: [1, 1] }));
    await ok(as("alice").set(secret(), { subject: "alice", answers: [0, 2] }));
    await denied(as("alice").set(secret(), { subject: "alice", answers: [3, 3] }));
  });
  it("locked guesses cannot be unlocked to try again", async () => {
    await seed(quiz({ answered: true, guesses: [0, 1], guessesLocked: true }, { turn: "bob" }));
    await denied(as("bob").update(g(), {
      turn: "bob", moveCount: 2,
      state: { subject: "alice", questions: ["q1", "q2"], answered: true, guesses: [0, 1], guessesLocked: false },
    }));
  });
  it("the subject cannot be swapped mid-game", async () => {
    await seed(quiz({}));
    await denied(as("alice").update(g(), { turn: "bob", moveCount: 2, state: { subject: "bob", questions: [] } }));
  });
});
