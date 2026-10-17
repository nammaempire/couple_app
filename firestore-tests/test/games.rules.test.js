// Rules for couples/{id}/games: invites, turns, moveCount, frozen games and
// the hidden quiz answers.
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp,
} = require('firebase/firestore');

const C = 'couple1';
let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const g = (uid, id = 'g1') => doc(db(uid), `couples/${C}/games/${id}`);
const secret = (uid, id = 'g1') => doc(db(uid), `couples/${C}/games/${id}/secret/answers`);

const invite = (o = {}) => ({
  type: 'ticTacToe', status: 'invited', createdBy: 'alice', invitee: 'bob',
  players: ['alice', 'bob'], turn: null, state: {}, winner: null, moveCount: 0,
  createdAt: serverTimestamp(), updatedAt: serverTimestamp(), finishedAt: null, ...o,
});

async function seed(data) {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), `couples/${C}/games/g1`), data));
}
const active = (o = {}) => ({ ...invite(), status: 'active', turn: 'alice', moveCount: 1, createdAt: 1, state: { board: [] }, ...o });


// scoped-hooks: keep this file's before/beforeEach from running for other files.
describe('games rules', () => {
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

describe('games: invites', () => {
  it('a member invites their partner', async () => {
    await assertSucceeds(setDoc(g('alice'), invite()));
    await assertSucceeds(getDoc(g('bob')));
  });
  it('rejects bad invites', async () => {
    await assertFails(setDoc(g('alice'), invite({ invitee: 'alice', players: ['alice', 'alice'] })));
    await assertFails(setDoc(g('alice'), invite({ invitee: 'eve', players: ['alice', 'eve'] })));
    await assertFails(setDoc(g('alice'), invite({ createdBy: 'bob', invitee: 'alice', players: ['bob', 'alice'] })));
    await assertFails(setDoc(g('alice'), invite({ status: 'active' })));
    await assertFails(setDoc(g('alice'), invite({ type: 'poker' })));
    await assertFails(setDoc(g('alice'), invite({ moveCount: 3 })));
    await assertFails(setDoc(g('eve'), invite({ createdBy: 'eve', invitee: 'bob', players: ['eve', 'bob'] })));
  });
  it('only the invitee accepts', async () => {
    await seed({ ...invite(), createdAt: 1 });
    await assertFails(updateDoc(g('alice'), { status: 'active', turn: 'alice', moveCount: 1 }));
    await assertSucceeds(updateDoc(g('bob'), { status: 'active', turn: 'alice', moveCount: 1 }));
  });
  it('either player can decline or withdraw', async () => {
    await seed({ ...invite(), createdAt: 1 });
    await assertSucceeds(updateDoc(g('alice'), { status: 'cancelled', turn: null, moveCount: 1 }));
  });
  it('strangers cannot read or touch games', async () => {
    await seed({ ...invite(), createdAt: 1 });
    await assertFails(getDoc(g('eve')));
    await assertFails(updateDoc(g('eve'), { status: 'cancelled', turn: null, moveCount: 1 }));
  });
});

describe('games: turns', () => {
  it('only the player whose turn it is can move', async () => {
    await seed(active());
    await assertFails(updateDoc(g('bob'), { state: { board: ['X'] }, turn: 'alice', moveCount: 2 }));
    await assertSucceeds(updateDoc(g('alice'), { state: { board: ['X'] }, turn: 'bob', moveCount: 2 }));
  });
  it('moveCount must go up by exactly one (no double moves)', async () => {
    await seed(active());
    await assertFails(updateDoc(g('alice'), { state: { board: ['X'] }, turn: 'bob', moveCount: 1 }));
    await assertFails(updateDoc(g('alice'), { state: { board: ['X'] }, turn: 'bob', moveCount: 3 }));
  });
  it('the next turn must be a player; no winner while active', async () => {
    await seed(active());
    await assertFails(updateDoc(g('alice'), { turn: 'eve', moveCount: 2 }));
    await assertFails(updateDoc(g('alice'), { turn: 'bob', winner: 'alice', moveCount: 2 }));
  });
  it('the mover can finish with a winner or a draw', async () => {
    await seed(active());
    await assertSucceeds(updateDoc(g('alice'), { status: 'finished', turn: null, winner: 'alice', moveCount: 2 }));
    await seed(active());
    await assertSucceeds(updateDoc(g('alice'), { status: 'finished', turn: null, winner: 'draw', moveCount: 2 }));
    await seed(active());
    await assertFails(updateDoc(g('alice'), { status: 'finished', turn: null, winner: 'eve', moveCount: 2 }));
  });
  it('either player can leave an active game, even off-turn', async () => {
    await seed(active());
    await assertSucceeds(updateDoc(g('bob'), { status: 'cancelled', turn: null, moveCount: 2 }));
  });
  it('leaving cannot sneak in a board change', async () => {
    await seed(active());
    await assertFails(updateDoc(g('bob'), { status: 'cancelled', turn: null, moveCount: 2, state: { board: ['O'] } }));
  });
  it('fixed fields never change', async () => {
    await seed(active());
    await assertFails(updateDoc(g('alice'), { type: 'connectFour', turn: 'bob', moveCount: 2 }));
    await assertFails(updateDoc(g('alice'), { invitee: 'alice', turn: 'bob', moveCount: 2 }));
  });
  it('finished and cancelled games are frozen; nobody deletes', async () => {
    await seed(active({ status: 'finished', turn: null, winner: 'alice' }));
    await assertFails(updateDoc(g('bob'), { status: 'cancelled', turn: null, moveCount: 2 }));
    await assertFails(updateDoc(g('alice'), { winner: 'bob', moveCount: 2 }));
    await assertFails(deleteDoc(g('alice')));
  });
});

describe('games: know-me quiz secrets', () => {
  const quiz = (state, o = {}) => active({ type: 'knowMe', turn: 'alice', state: { subject: 'alice', questions: ['q1', 'q2'], ...state }, ...o });

  it('the subject writes answers and hands over the turn in one batch', async () => {
    await seed(quiz({}));
    const alice = db('alice');
    const b = writeBatch(alice);
    b.set(doc(alice, `couples/${C}/games/g1/secret/answers`), { subject: 'alice', answers: [0, 2] });
    b.update(doc(alice, `couples/${C}/games/g1`), { turn: 'bob', state: { subject: 'alice', questions: ['q1', 'q2'], answered: true }, moveCount: 2 });
    await assertSucceeds(b.commit());
    await assertSucceeds(getDoc(secret('alice')));
  });
  it('the guesser cannot peek before locking in guesses', async () => {
    await seed(quiz({ answered: true }, { turn: 'bob' }));
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), `couples/${C}/games/g1/secret/answers`), { subject: 'alice', answers: [0, 2] }));
    await assertFails(getDoc(secret('bob')));
  });
  it('after locking guesses, the guesser can read the answers', async () => {
    await seed(quiz({ answered: true }, { turn: 'bob' }));
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), `couples/${C}/games/g1/secret/answers`), { subject: 'alice', answers: [0, 2] }));
    await assertSucceeds(updateDoc(g('bob'), {
      turn: 'bob', moveCount: 2,
      state: { subject: 'alice', questions: ['q1', 'q2'], answered: true, guesses: [0, 1], guessesLocked: true },
    }));
    await assertSucceeds(getDoc(secret('bob')));
  });
  it('locked guesses cannot change', async () => {
    await seed(quiz({ answered: true, guesses: [0, 1], guessesLocked: true }, { turn: 'bob' }));
    await assertFails(updateDoc(g('bob'), {
      turn: 'bob', moveCount: 2,
      state: { subject: 'alice', questions: ['q1', 'q2'], answered: true, guesses: [0, 2], guessesLocked: true },
    }));
    await assertSucceeds(updateDoc(g('bob'), {
      status: 'finished', turn: null, moveCount: 2,
      state: { subject: 'alice', questions: ['q1', 'q2'], answered: true, guesses: [0, 1], guessesLocked: true, score: 1 },
    }));
  });
  it('only the subject, on their turn, can write answers; never rewritten', async () => {
    await seed(quiz({}));
    await assertFails(setDoc(secret('bob'), { subject: 'bob', answers: [1, 1] }));
    await assertFails(setDoc(secret('bob'), { subject: 'alice', answers: [1, 1] }));
    await assertSucceeds(setDoc(secret('alice'), { subject: 'alice', answers: [0, 2] }));
    await assertFails(setDoc(secret('alice'), { subject: 'alice', answers: [3, 3] }));
  });
  it('locked guesses cannot be unlocked to try again', async () => {
    await seed(quiz({ answered: true, guesses: [0, 1], guessesLocked: true }, { turn: 'bob' }));
    await assertFails(updateDoc(g('bob'), {
      turn: 'bob', moveCount: 2,
      state: { subject: 'alice', questions: ['q1', 'q2'], answered: true, guesses: [0, 1], guessesLocked: false },
    }));
  });
  it('the subject cannot be swapped mid-game', async () => {
    await seed(quiz({}));
    await assertFails(updateDoc(g('alice'), { turn: 'bob', moveCount: 2, state: { subject: 'bob', questions: [] } }));
  });
});

});
