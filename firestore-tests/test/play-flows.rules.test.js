// Reproduces the exact writes the Play client code makes (GameService,
// KnowMeService) as full game flows, using transactions like the Dart code.
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, collection, query, orderBy, limit, getDocs,
  runTransaction, serverTimestamp,
} = require('firebase/firestore');

const C = 'couple1';
let env;
const dbs = {};
const db = (uid) => (dbs[uid] ||= env.authenticatedContext(uid).firestore());
const gref = (uid, id) => doc(db(uid), `couples/${C}/games/${id}`);
const sref = (uid, id) => doc(db(uid), `couples/${C}/games/${id}/secret/answers`);

// GameService.invite
async function invite(me, invitee, type, state, id) {
  await setDoc(gref(me, id), {
    type, status: 'invited', createdBy: me, invitee, players: [me, invitee],
    turn: null, state, winner: null, moveCount: 0,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), finishedAt: null,
  });
}
// GameService.move
async function move(uid, id, apply) {
  return runTransaction(db(uid), async (tx) => {
    const snap = await tx.get(gref(uid, id));
    const game = snap.data();
    const changes = apply(game);
    tx.update(gref(uid, id), {
      ...changes,
      moveCount: game.moveCount + 1,
      updatedAt: serverTimestamp(),
      ...(changes.status === 'finished' ? { finishedAt: serverTimestamp() } : {}),
    });
  });
}
const accept = (me, id, firstTurn) => move(me, id, (g) => {
  if (g.status !== 'invited' || g.invitee !== me) throw new Error('not open');
  return { status: 'active', turn: firstTurn };
});
const cancel = (me, id) => move(me, id, () => ({ status: 'cancelled', turn: null }));
const takeTurn = (me, id, apply) => move(me, id, (g) => {
  if (g.status !== 'active') throw new Error('ended');
  if (g.turn !== me) throw new Error('not your turn');
  return apply(g);
});
const read = async (id) => (await getDoc(gref('alice', id))).data();

// ---- tic-tac-toe (port of TicTacToeLogic.applyMove) ----
const TL = [[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]];
const tttWin = (b) => TL.some(([a, c, d]) => b[a] && b[a] === b[c] && b[a] === b[d]);
function tttMove(g, me, cell) {
  const other = me === g.createdBy ? g.invitee : g.createdBy;
  const next = [...g.state.board];
  if (next[cell]) throw new Error('taken');
  const mark = (g.state.marks && g.state.marks[me]) || (me === g.invitee ? 'X' : 'O');
  next[cell] = mark;
  const state = { board: next, marks: { [me]: mark, [other]: mark === 'X' ? 'O' : 'X' }, lastMove: cell };
  if (tttWin(next)) return { state, status: 'finished', turn: null, winner: me };
  if (next.every((c) => c)) return { state, status: 'finished', turn: null, winner: 'draw' };
  return { state, turn: other };
}
// ---- connect four ----
function c4Move(g, me, col) {
  const other = me === g.createdBy ? g.invitee : g.createdBy;
  const next = [...g.state.board];
  let row = -1;
  for (let r = 5; r >= 0; r--) if (!next[r * 7 + col]) { row = r; break; }
  if (row < 0) throw new Error('full');
  const color = (g.state.marks && g.state.marks[me]) || (me === g.invitee ? 'R' : 'Y');
  next[row * 7 + col] = color;
  const win = (() => {
    for (let r = 0; r < 6; r++) for (let c = 0; c < 7; c++) {
      const v = next[r * 7 + c]; if (!v) continue;
      for (const [dr, dc] of [[0,1],[1,0],[1,1],[1,-1]]) {
        let n = 1, rr = r + dr, cc = c + dc;
        while (rr >= 0 && rr < 6 && cc >= 0 && cc < 7 && next[rr * 7 + cc] === v) { n++; rr += dr; cc += dc; }
        if (n >= 4) return true;
      }
    }
    return false;
  })();
  const state = { board: next, marks: { [me]: color, [other]: color === 'R' ? 'Y' : 'R' }, lastMove: row * 7 + col };
  if (win) return { state, status: 'finished', turn: null, winner: me };
  if (next.every((c) => c)) return { state, status: 'finished', turn: null, winner: 'draw' };
  return { state, turn: other };
}


// scoped-hooks: keep this file's before/beforeEach from running for other files.
describe('play-flows rules', () => {
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-couple',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
      host: '127.0.0.1', port: 8085,
    },
  });
});
after(async () => env && env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), `couples/${C}`), { memberIds: ['alice', 'bob'], inviteCode: 'ABC234' }));
});

describe('play flows: exact client writes', () => {
  it('tic-tac-toe: full game to a win, then Play again', async () => {
    await assertSucceeds(invite('alice', 'bob', 'ticTacToe',
      { board: Array(9).fill(''), marks: {}, lastMove: -1 }, 't1'));
    await assertSucceeds(accept('bob', 't1', 'bob'));
    // bob X: 0,1,2 ; alice O: 3,4
    const seq = [['bob', 0], ['alice', 3], ['bob', 1], ['alice', 4], ['bob', 2]];
    for (const [who, cell] of seq) await assertSucceeds(takeTurn(who, 't1', (g) => tttMove(g, who, cell)));
    const g = await read('t1');
    assert.strictEqual(g.status, 'finished'); assert.strictEqual(g.winner, 'bob');
    assert.ok(g.finishedAt); assert.ok(g.createdAt);
    // frozen
    await assertFails(move('bob', 't1', () => ({ turn: 'alice' })));
    // Play again from the loser's phone
    await assertSucceeds(invite('alice', 'bob', 'ticTacToe',
      { board: Array(9).fill(''), marks: {}, lastMove: -1 }, 't2'));
    await assertSucceeds(accept('bob', 't2', 'bob'));
  });

  it('tic-tac-toe: draw', async () => {
    await invite('alice', 'bob', 'ticTacToe', { board: Array(9).fill(''), marks: {}, lastMove: -1 }, 't3');
    await accept('bob', 't3', 'bob');
    // X O X / X O O / O X X  -> draw
    const seq = [['bob', 0], ['alice', 1], ['bob', 2], ['alice', 4], ['bob', 3], ['alice', 5], ['bob', 7], ['alice', 6], ['bob', 8]];
    for (const [who, cell] of seq) await assertSucceeds(takeTurn(who, 't3', (g) => tttMove(g, who, cell)));
    const g = await read('t3');
    assert.strictEqual(g.winner, 'draw'); assert.strictEqual(g.moveCount, 10);
  });

  it('connect four: vertical win', async () => {
    await invite('alice', 'bob', 'connectFour', { board: Array(42).fill(''), marks: {}, lastMove: -1 }, 'c1');
    await assertSucceeds(accept('bob', 'c1', 'bob'));
    const seq = [['bob', 3], ['alice', 4], ['bob', 3], ['alice', 4], ['bob', 3], ['alice', 4], ['bob', 3]];
    for (const [who, col] of seq) await assertSucceeds(takeTurn(who, 'c1', (g) => c4Move(g, who, col)));
    const g = await read('c1');
    assert.strictEqual(g.winner, 'bob'); assert.strictEqual(g.status, 'finished');
  });

  it('truth or dare: 10 rounds', async () => {
    await invite('alice', 'bob', 'truthOrDare', {
      round: 1, rounds: 10, phase: 'choose', chooser: null, card: null,
      used: [], done: {}, skipped: {}, history: [],
    }, 'd1');
    await assertSucceeds(accept('bob', 'd1', 'bob'));
    let chooser = 'bob';
    for (let i = 0; i < 10; i++) {
      const judge = chooser === 'bob' ? 'alice' : 'bob';
      await assertSucceeds(takeTurn(chooser, 'd1', (g) => ({
        turn: judge,
        state: { ...g.state, phase: 'judge', chooser, card: { kind: 'truth', id: `t0${i}`, text: 'x' }, used: [...g.state.used, `t0${i}`] },
      })));
      await assertSucceeds(takeTurn(judge, 'd1', (g) => {
        const s = g.state; const done = { ...s.done, [chooser]: (s.done[chooser] || 0) + 1 };
        const finished = s.round >= s.rounds;
        const state = { ...s, round: finished ? s.round : s.round + 1, phase: 'choose', chooser: judge, card: null, done, skipped: s.skipped,
          history: [...s.history, { round: s.round, chooser, kind: 'truth', id: `t0${i}`, result: 'done' }] };
        return finished ? { state, status: 'finished', turn: null, winner: null } : { state, turn: judge };
      }));
      chooser = judge;
    }
    const g = await read('d1');
    assert.strictEqual(g.status, 'finished'); assert.strictEqual(g.moveCount, 21);
    assert.deepStrictEqual(g.state.done, { bob: 5, alice: 5 });
  });

  it('know me: answers (tx with secret), lock, read secret, reveal/finish, both read after', async () => {
    const qs = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
    await assertSucceeds(invite('alice', 'bob', 'knowMe', { subject: 'alice', questions: qs, total: 7 }, 'k1'));
    await assertSucceeds(accept('bob', 'k1', 'alice'));
    // bob cannot read the (nonexistent) secret yet
    await assertFails(getDoc(sref('bob', 'k1')));
    // KnowMeService.submitAnswers
    const answers = [0, 1, 2, 3, 0, 1, 2];
    await assertSucceeds(runTransaction(db('alice'), async (tx) => {
      const snap = await tx.get(gref('alice', 'k1'));
      const g = snap.data();
      tx.set(sref('alice', 'k1'), { subject: 'alice', answers });
      tx.update(gref('alice', 'k1'), {
        state: { ...g.state, answered: true }, turn: 'bob',
        moveCount: g.moveCount + 1, updatedAt: serverTimestamp(),
      });
    }));
    await assertFails(getDoc(sref('bob', 'k1')));
    const guesses = [0, 1, 1, 3, 2, 1, 0];
    await assertSucceeds(takeTurn('bob', 'k1', (g) => ({ state: { ...g.state, guesses, guessesLocked: true }, turn: 'bob' })));
    const sec = await assertSucceeds(getDoc(sref('bob', 'k1')));
    const ans = sec.data().answers;
    await assertSucceeds(takeTurn('bob', 'k1', (g) => ({
      state: { ...g.state, answers: ans, score: 4 }, status: 'finished', turn: null, winner: null,
    })));
    const g = await read('k1');
    assert.strictEqual(g.status, 'finished'); assert.strictEqual(g.state.score, 4);
    await assertSucceeds(getDoc(sref('alice', 'k1')));
    await assertSucceeds(getDoc(sref('bob', 'k1')));
    // Play again from bob (subject flips)
    await assertSucceeds(invite('bob', 'alice', 'knowMe', { subject: 'bob', questions: qs, total: 7 }, 'k2'));
    await assertSucceeds(accept('alice', 'k2', 'bob'));
  });

  it('cancel at every phase + games list query', async () => {
    await invite('alice', 'bob', 'knowMe', { subject: 'alice', questions: ['a'], total: 1 }, 'x1');
    await assertSucceeds(cancel('alice', 'x1'));
    await invite('alice', 'bob', 'connectFour', { board: Array(42).fill(''), marks: {}, lastMove: -1 }, 'x2');
    await accept('bob', 'x2', 'bob');
    await assertSucceeds(cancel('alice', 'x2'));
    await assertSucceeds(getDocs(query(collection(db('bob'), `couples/${C}/games`), orderBy('createdAt', 'desc'), limit(100))));
  });

  it('race: two transactions on the same turn — only one lands', async () => {
    await invite('alice', 'bob', 'ticTacToe', { board: Array(9).fill(''), marks: {}, lastMove: -1 }, 'r1');
    await accept('bob', 'r1', 'bob');
    const results = await Promise.allSettled([
      takeTurn('bob', 'r1', (g) => tttMove(g, 'bob', 0)),
      takeTurn('bob', 'r1', (g) => tttMove(g, 'bob', 4)),
    ]);
    const g = await read('r1');
    assert.strictEqual(g.moveCount, 2);
    assert.strictEqual(g.state.board.filter((c) => c).length, 1);
    assert.strictEqual(results.filter((r) => r.status === 'fulfilled').length, 1);
  });
});

});
