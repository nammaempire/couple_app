// Port of firestore-tests/test/play-flows.rules.test.js: the exact writes the
// Play client code makes (GameService, KnowMeService) as full game flows,
// using transactions like the Dart code.
import { describe, it } from "node:test";
import { ST, admin, as, assert, denied, ok, useDb, type Data } from "./rules-helpers.js";

type O = Record<string, any>;
const C = "couple1";
const gref = (id: string) => `couples/${C}/games/${id}`;
const sref = (id: string) => `couples/${C}/games/${id}/secret/answers`;

// GameService.invite
async function invite(me: string, invitee: string, type: string, state: O, id: string) {
  await as(me).set(gref(id), {
    type, status: "invited", createdBy: me, invitee, players: [me, invitee],
    turn: null, state, winner: null, moveCount: 0,
    createdAt: ST, updatedAt: ST, finishedAt: null,
  });
}
// GameService.move
async function move(uid: string, id: string, apply: (g: Data) => O) {
  return as(uid).runTransaction(async (tx) => {
    const game = (await tx.get(gref(id)))!;
    const changes = apply(game);
    tx.update(gref(id), {
      ...changes,
      moveCount: game.moveCount + 1,
      updatedAt: ST,
      ...(changes.status === "finished" ? { finishedAt: ST } : {}),
    });
  });
}
const accept = (me: string, id: string, firstTurn: string) => move(me, id, (g) => {
  if (g.status !== "invited" || g.invitee !== me) throw new Error("not open");
  return { status: "active", turn: firstTurn };
});
const cancel = (me: string, id: string) => move(me, id, () => ({ status: "cancelled", turn: null }));
const takeTurn = (me: string, id: string, apply: (g: Data) => O) => move(me, id, (g) => {
  if (g.status !== "active") throw new Error("ended");
  if (g.turn !== me) throw new Error("not your turn");
  return apply(g);
});
const read = async (id: string) => (await as("alice").data(gref(id)))!;

// ---- tic-tac-toe (port of TicTacToeLogic.applyMove) ----
const TL = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]];
const tttWin = (b: string[]) => TL.some(([a, c, d]) => b[a] && b[a] === b[c] && b[a] === b[d]);
function tttMove(g: Data, me: string, cell: number): O {
  const other = me === g.createdBy ? g.invitee : g.createdBy;
  const next = [...g.state.board];
  if (next[cell]) throw new Error("taken");
  const mark = (g.state.marks && g.state.marks[me]) || (me === g.invitee ? "X" : "O");
  next[cell] = mark;
  const state = { board: next, marks: { [me]: mark, [other]: mark === "X" ? "O" : "X" }, lastMove: cell };
  if (tttWin(next)) return { state, status: "finished", turn: null, winner: me };
  if (next.every((c) => c)) return { state, status: "finished", turn: null, winner: "draw" };
  return { state, turn: other };
}
// ---- connect four ----
function c4Move(g: Data, me: string, col: number): O {
  const other = me === g.createdBy ? g.invitee : g.createdBy;
  const next = [...g.state.board];
  let row = -1;
  for (let r = 5; r >= 0; r--) if (!next[r * 7 + col]) { row = r; break; }
  if (row < 0) throw new Error("full");
  const color = (g.state.marks && g.state.marks[me]) || (me === g.invitee ? "R" : "Y");
  next[row * 7 + col] = color;
  const win = (() => {
    for (let r = 0; r < 6; r++) for (let c = 0; c < 7; c++) {
      const v = next[r * 7 + c]; if (!v) continue;
      for (const [dr, dc] of [[0, 1], [1, 0], [1, 1], [1, -1]]) {
        let n = 1, rr = r + dr, cc = c + dc;
        while (rr >= 0 && rr < 6 && cc >= 0 && cc < 7 && next[rr * 7 + cc] === v) { n++; rr += dr; cc += dc; }
        if (n >= 4) return true;
      }
    }
    return false;
  })();
  const state = { board: next, marks: { [me]: color, [other]: color === "R" ? "Y" : "R" }, lastMove: row * 7 + col };
  if (win) return { state, status: "finished", turn: null, winner: me };
  if (next.every((c) => c)) return { state, status: "finished", turn: null, winner: "draw" };
  return { state, turn: other };
}

useDb(async () => {
  await admin.set(`couples/${C}`, { memberIds: ["alice", "bob"], inviteCode: "ABC234" });
});

describe("play flows: exact client writes", () => {
  it("tic-tac-toe: full game to a win, then Play again", async () => {
    await ok(invite("alice", "bob", "ticTacToe", { board: Array(9).fill(""), marks: {}, lastMove: -1 }, "t1"));
    await ok(accept("bob", "t1", "bob"));
    // bob X: 0,1,2 ; alice O: 3,4
    const seq: [string, number][] = [["bob", 0], ["alice", 3], ["bob", 1], ["alice", 4], ["bob", 2]];
    for (const [who, cell] of seq) await ok(takeTurn(who, "t1", (g) => tttMove(g, who, cell)));
    const g = await read("t1");
    assert.strictEqual(g.status, "finished"); assert.strictEqual(g.winner, "bob");
    assert.ok(g.finishedAt); assert.ok(g.createdAt);
    // frozen
    await denied(move("bob", "t1", () => ({ turn: "alice" })));
    // Play again from the loser's phone
    await ok(invite("alice", "bob", "ticTacToe", { board: Array(9).fill(""), marks: {}, lastMove: -1 }, "t2"));
    await ok(accept("bob", "t2", "bob"));
  });

  it("tic-tac-toe: draw", async () => {
    await invite("alice", "bob", "ticTacToe", { board: Array(9).fill(""), marks: {}, lastMove: -1 }, "t3");
    await accept("bob", "t3", "bob");
    // X O X / X O O / O X X  -> draw
    const seq: [string, number][] = [["bob", 0], ["alice", 1], ["bob", 2], ["alice", 4], ["bob", 3], ["alice", 5], ["bob", 7], ["alice", 6], ["bob", 8]];
    for (const [who, cell] of seq) await ok(takeTurn(who, "t3", (g) => tttMove(g, who, cell)));
    const g = await read("t3");
    assert.strictEqual(g.winner, "draw"); assert.strictEqual(g.moveCount, 10);
  });

  it("connect four: vertical win", async () => {
    await invite("alice", "bob", "connectFour", { board: Array(42).fill(""), marks: {}, lastMove: -1 }, "c1");
    await ok(accept("bob", "c1", "bob"));
    const seq: [string, number][] = [["bob", 3], ["alice", 4], ["bob", 3], ["alice", 4], ["bob", 3], ["alice", 4], ["bob", 3]];
    for (const [who, col] of seq) await ok(takeTurn(who, "c1", (g) => c4Move(g, who, col)));
    const g = await read("c1");
    assert.strictEqual(g.winner, "bob"); assert.strictEqual(g.status, "finished");
  });

  it("truth or dare: 10 rounds", async () => {
    await invite("alice", "bob", "truthOrDare", {
      round: 1, rounds: 10, phase: "choose", chooser: null, card: null,
      used: [], done: {}, skipped: {}, history: [],
    }, "d1");
    await ok(accept("bob", "d1", "bob"));
    let chooser = "bob";
    for (let i = 0; i < 10; i++) {
      const judge = chooser === "bob" ? "alice" : "bob";
      await ok(takeTurn(chooser, "d1", (g) => ({
        turn: judge,
        state: { ...g.state, phase: "judge", chooser, card: { kind: "truth", id: `t0${i}`, text: "x" }, used: [...g.state.used, `t0${i}`] },
      })));
      await ok(takeTurn(judge, "d1", (g) => {
        const s = g.state; const done = { ...s.done, [chooser]: (s.done[chooser] || 0) + 1 };
        const finished = s.round >= s.rounds;
        const state = { ...s, round: finished ? s.round : s.round + 1, phase: "choose", chooser: judge, card: null, done, skipped: s.skipped,
          history: [...s.history, { round: s.round, chooser, kind: "truth", id: `t0${i}`, result: "done" }] };
        return finished ? { state, status: "finished", turn: null, winner: null } : { state, turn: judge };
      }));
      chooser = judge;
    }
    const g = await read("d1");
    assert.strictEqual(g.status, "finished"); assert.strictEqual(g.moveCount, 21);
    assert.deepStrictEqual(g.state.done, { bob: 5, alice: 5 });
  });

  it("know me: answers (tx with secret), lock, read secret, reveal/finish, both read after", async () => {
    const qs = ["a", "b", "c", "d", "e", "f", "g"];
    await ok(invite("alice", "bob", "knowMe", { subject: "alice", questions: qs, total: 7 }, "k1"));
    await ok(accept("bob", "k1", "alice"));
    // bob cannot read the (nonexistent) secret yet
    await denied(as("bob").get(sref("k1")));
    // KnowMeService.submitAnswers
    const answers = [0, 1, 2, 3, 0, 1, 2];
    await ok(as("alice").runTransaction(async (tx) => {
      const g = (await tx.get(gref("k1")))!;
      tx.set(sref("k1"), { subject: "alice", answers });
      tx.update(gref("k1"), {
        state: { ...g.state, answered: true }, turn: "bob",
        moveCount: g.moveCount + 1, updatedAt: ST,
      });
    }));
    await denied(as("bob").get(sref("k1")));
    const guesses = [0, 1, 1, 3, 2, 1, 0];
    await ok(takeTurn("bob", "k1", (g) => ({ state: { ...g.state, guesses, guessesLocked: true }, turn: "bob" })));
    const sec = await ok(as("bob").get(sref("k1")));
    const ans = sec.data!.answers;
    await ok(takeTurn("bob", "k1", (g) => ({
      state: { ...g.state, answers: ans, score: 4 }, status: "finished", turn: null, winner: null,
    })));
    const g = await read("k1");
    assert.strictEqual(g.status, "finished"); assert.strictEqual(g.state.score, 4);
    await ok(as("alice").get(sref("k1")));
    await ok(as("bob").get(sref("k1")));
    // Play again from bob (subject flips)
    await ok(invite("bob", "alice", "knowMe", { subject: "bob", questions: qs, total: 7 }, "k2"));
    await ok(accept("alice", "k2", "bob"));
  });

  it("cancel at every phase + games list query", async () => {
    await invite("alice", "bob", "knowMe", { subject: "alice", questions: ["a"], total: 1 }, "x1");
    await ok(cancel("alice", "x1"));
    await invite("alice", "bob", "connectFour", { board: Array(42).fill(""), marks: {}, lastMove: -1 }, "x2");
    await accept("bob", "x2", "bob");
    await ok(cancel("alice", "x2"));
    const list = await ok(as("bob").query({ collection: `couples/${C}/games`, orderBy: [["createdAt", "desc"]], limit: 100 }));
    assert.equal(list.length, 2);
  });

  it("race: two transactions on the same turn — only one lands", async () => {
    await invite("alice", "bob", "ticTacToe", { board: Array(9).fill(""), marks: {}, lastMove: -1 }, "r1");
    await accept("bob", "r1", "bob");
    const results = await Promise.allSettled([
      takeTurn("bob", "r1", (g) => tttMove(g, "bob", 0)),
      takeTurn("bob", "r1", (g) => tttMove(g, "bob", 4)),
    ]);
    const g = await read("r1");
    assert.strictEqual(g.moveCount, 2);
    assert.strictEqual(g.state.board.filter((c: string) => c).length, 1);
    assert.strictEqual(results.filter((r) => r.status === "fulfilled").length, 1);
  });

  // ---- snakes & ladders: one write per roll (SnakesLaddersLogic) ----
  it("snakes & ladders: rolls, a ladder, a snake, extra roll on 6, then a win", async () => {
    await ok(invite("alice", "bob", "snakesLadders", { positions: { alice: 0, bob: 0 }, lastRoll: null, sixes: 0 }, "sl"));
    await ok(accept("bob", "sl", "bob"));
    const roll = (me: string, other: string, to: number, extra: O = {}) => takeTurn(me, "sl", (g) => ({
      state: {
        positions: { ...g.state.positions, [me]: to },
        lastRoll: { by: me, value: extra.value ?? 3, from: g.state.positions[me], to,
          via: extra.via ?? null, viaFrom: extra.viaFrom ?? null, viaTo: extra.viaTo ?? null,
          bounced: false, forfeit: false, again: !!extra.again },
        sixes: extra.again ? 1 : 0,
      },
      turn: extra.again ? me : other,
      ...(to === 100 ? { status: "finished", turn: null, winner: me } : {}),
    }));
    await ok(roll("bob", "alice", 38, { value: 1, via: "ladder", viaFrom: 1, viaTo: 38 }));
    // Not Bob's turn any more: a direct write (skipping the app's own check).
    const now = await read("sl");
    await denied(as("bob").update(gref("sl"), { "state.positions.bob": 40, moveCount: now.moveCount + 1 }));
    await ok(roll("alice", "bob", 6, { value: 6, again: true }));
    await ok(roll("alice", "bob", 9, { value: 3 })); // same player again after a 6
    await ok(roll("bob", "alice", 19, { value: 24, via: "snake", viaFrom: 62, viaTo: 19 }));
    await ok(roll("alice", "bob", 100, { value: 4 }));
    const g = await read("sl");
    assert.strictEqual(g.status, "finished");
    assert.strictEqual(g.winner, "alice");
    const done = await read("sl");
    await denied(as("bob").update(gref("sl"), { "state.positions.bob": 22, moveCount: done.moveCount + 1 })); // frozen
  });

  // ---- ludo: roll write, then move write (LudoLogic) ----
  it("ludo: roll keeps the turn for the move, pass with no move, capture, win", async () => {
    await ok(invite("alice", "bob", "ludo", {
      mode: "quick", tokens: { alice: [-1, -1], bob: [-1, -1] },
      pendingRoll: null, lastRoll: null, sixes: 0,
    }, "ld"));
    await ok(accept("bob", "ld", "bob"));
    const lr = (by: string, value: number, o: O = {}) => ({ by, value, token: null, from: null, to: null,
      captured: [], passed: false, forfeit: false, again: false, ...o });
    // Bob rolls a 6: one token can leave, turn stays with Bob.
    await ok(takeTurn("bob", "ld", (g) => ({
      state: { ...g.state, pendingRoll: { value: 6, movable: [0, 1] }, lastRoll: lr("bob", 6), sixes: 1 },
      turn: "bob",
    })));
    const mid = await read("ld");
    await denied(as("alice").update(gref("ld"), { turn: "alice", moveCount: mid.moveCount + 1 }));
    // Bob moves token 0 out; extra roll for the 6.
    await ok(takeTurn("bob", "ld", (g) => ({
      state: { ...g.state, tokens: { ...g.state.tokens, bob: [0, -1] }, pendingRoll: null,
        lastRoll: lr("bob", 6, { token: 0, from: -1, to: 0, again: true }) },
      turn: "bob",
    })));
    // Bob rolls 2, moves, turn passes.
    await ok(takeTurn("bob", "ld", (g) => ({
      state: { ...g.state, pendingRoll: { value: 2, movable: [0] }, lastRoll: lr("bob", 2), sixes: 0 }, turn: "bob",
    })));
    await ok(takeTurn("bob", "ld", (g) => ({
      state: { ...g.state, tokens: { ...g.state.tokens, bob: [2, -1] }, pendingRoll: null,
        lastRoll: lr("bob", 2, { token: 0, from: 0, to: 2 }) },
      turn: "alice",
    })));
    // Alice rolls 3 with everything in the yard: no move, turn passes in one write.
    await ok(takeTurn("alice", "ld", (g) => ({
      state: { ...g.state, pendingRoll: null, lastRoll: lr("alice", 3, { passed: true }), sixes: 0 },
      turn: "bob",
    })));
    // Jump to the end: Bob brings his last token home and wins.
    await ok(takeTurn("bob", "ld", (g) => ({
      state: { ...g.state, tokens: { alice: [-1, -1], bob: [56, 56] }, pendingRoll: null,
        lastRoll: lr("bob", 4, { token: 1, from: 52, to: 56 }) },
      status: "finished", turn: null, winner: "bob",
    })));
    assert.strictEqual((await read("ld")).winner, "bob");
  });
});
