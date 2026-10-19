// Firestore rules tests for NoteNest, run against the local emulator only
// (project id "demo-notenest", which can never reach a real project).
//
//   cd firestore-tests && npm install && npm test
//
// Each test pairs what the app really writes (which must pass) with the
// nearest thing a modified client could write instead (which must not). Run
// against the rules before the October 2026 hardening, 12 of the 15 fail —
// that is the evidence the holes they cover were real.
//
// RULES_PATH overrides which rules file is loaded; the default is the one
// this repository deploys.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { test, before, after, beforeEach } from 'node:test';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, writeBatch, arrayUnion,
  arrayRemove, collection, query, where, getDocs,
} from 'firebase/firestore';

const RULES = process.env.RULES_PATH ??
  fileURLToPath(new URL('../firestore.rules', import.meta.url));
let env;

const now = () => Date.now();

function as(uid, email, verified = true) {
  return env
    .authenticatedContext(uid, { email, email_verified: verified })
    .firestore();
}

const profile = (uid, email, extra = {}) => ({
  uid, name: uid.toUpperCase(), email, role: 'student', institution: '',
  createdAt: now(), updatedAt: now(), ...extra,
});

const group = (owner, code, extra = {}) => ({
  name: 'Algorithms', joinCode: code, ownerUid: owner, ownerName: owner,
  kind: 'study', subject: 'CSE', memberUids: [owner],
  createdAt: now(), updatedAt: now(), ...extra,
});

const share = (from, to, extra = {}) => ({
  fromUid: from, fromName: from, toUid: to, title: 'Note', payload: '{}',
  groupId: '', groupName: '', message: '', subjectCode: '', fileCount: 0,
  state: 'pending', createdAt: now(), ...extra,
});

const message = (from, extra = {}) => ({
  fromUid: from, fromName: from, kind: 'text', text: 'hi', title: '',
  subjectCode: '', fileCount: 0, blobId: '', thumb: '', durationMs: 0,
  createdAt: now(), ...extra,
});

// Seeds an accepted message request, bypassing rules, as the precondition for
// opening a direct chat between these two.
async function seedAccepted(from, to) {
  const id = from < to ? 'dm_' + from + '_' + to : 'dm_' + to + '_' + from;
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'dmRequests', id), {
      fromUid: from, toUid: to, text: 'hi', state: 'accepted', createdAt: now(),
    });
  });
}

async function createGroup(db, owner, groupId, code) {
  const b = writeBatch(db);
  b.set(doc(db, 'groups', groupId), group(owner, code));
  b.set(doc(db, 'joinCodes', code), {
    groupId, name: 'Algorithms', ownerUid: owner, createdAt: now(),
  });
  return b.commit();
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-notenest',
    firestore: { rules: readFileSync(RULES, 'utf8').replace(/^﻿/, '') },
  });
});
after(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

// ---------------------------------------------------------------- profiles

test('profile: own create ok, extra field refused, other uid refused', async () => {
  const a = as('alice', 'alice@uni.edu');
  await assertSucceeds(setDoc(doc(a, 'users/alice'), profile('alice', 'alice@uni.edu')));
  await assertFails(setDoc(doc(a, 'users/alice'),
    profile('alice', 'alice@uni.edu', { junk: 'x'.repeat(10) })));
  await assertFails(setDoc(doc(a, 'users/bob'), profile('bob', 'alice@uni.edu')));
});

test('profile: merge update by the app passes; listing is closed', async () => {
  const a = as('alice', 'alice@uni.edu');
  await setDoc(doc(a, 'users/alice'), profile('alice', 'alice@uni.edu'));
  await assertSucceeds(setDoc(doc(a, 'users/alice'),
    profile('alice', 'alice@uni.edu', { name: 'Alice B' }), { merge: true }));
  await assertFails(getDocs(collection(a, 'users')));
});

// -------------------------------------------------------------- emailIndex

test('emailIndex: unverified address cannot be claimed (H-1)', async () => {
  const squatter = as('mallory', 'victim@uni.edu', false);
  await assertFails(setDoc(doc(squatter, 'emailIndex/victim@uni.edu'),
    { uid: 'mallory', updatedAt: 'x' }));
});

test('emailIndex: verified own address ok; someone else\'s refused', async () => {
  const a = as('alice', 'alice@uni.edu');
  await assertSucceeds(setDoc(doc(a, 'emailIndex/alice@uni.edu'),
    { uid: 'alice', updatedAt: 'x' }));
  await assertFails(setDoc(doc(a, 'emailIndex/bob@uni.edu'),
    { uid: 'alice', updatedAt: 'x' }));
  await assertFails(setDoc(doc(a, 'emailIndex/alice@uni.edu'),
    { uid: 'alice', updatedAt: 'x', extra: 1 }));
});

// ------------------------------------------------------------------ groups

test('groups: app create batch passes; group without its code refused', async () => {
  const a = as('alice', 'alice@uni.edu');
  await assertSucceeds(createGroup(a, 'alice', 'g1', 'ABCDEF'));
  await assertFails(setDoc(doc(a, 'groups/g2'), group('alice', 'ZZZZZZ')));
});

test('joinCodes: cannot mint a code for somebody else\'s group', async () => {
  await createGroup(as('alice', 'alice@uni.edu'), 'alice', 'g1', 'ABCDEF');
  const m = as('mallory', 'm@uni.edu');
  await assertFails(setDoc(doc(m, 'joinCodes/QQQQQQ'),
    { groupId: 'g1', name: 'x', ownerUid: 'mallory', createdAt: now() }));
});

test('groups: join once ok, join twice refused, leave ok', async () => {
  await createGroup(as('alice', 'alice@uni.edu'), 'alice', 'g1', 'ABCDEF');
  const b = as('bob', 'bob@uni.edu');
  await assertSucceeds(getDoc(doc(b, 'joinCodes/ABCDEF')));
  await assertSucceeds(updateDoc(doc(b, 'groups/g1'),
    { memberUids: arrayUnion('bob'), updatedAt: now() }));
  await assertFails(updateDoc(doc(b, 'groups/g1'),
    { memberUids: [...['alice', 'bob'], 'bob'], updatedAt: now() }));
  await assertSucceeds(getDocs(query(collection(b, 'groups'),
    where('memberUids', 'array-contains', 'bob'))));
  await assertSucceeds(updateDoc(doc(b, 'groups/g1'),
    { memberUids: arrayRemove('bob'), updatedAt: now() }));
});

test('groups: owner may rename and remove, but not add people (M-3)', async () => {
  const a = as('alice', 'alice@uni.edu');
  await createGroup(a, 'alice', 'g1', 'ABCDEF');
  await updateDoc(doc(as('bob', 'bob@uni.edu'), 'groups/g1'),
    { memberUids: arrayUnion('bob'), updatedAt: now() });
  await assertSucceeds(updateDoc(doc(a, 'groups/g1'), { name: 'Algo II', updatedAt: now() }));
  await assertFails(updateDoc(doc(a, 'groups/g1'),
    { memberUids: ['alice', 'bob', 'carol'], updatedAt: now() }));
  await assertSucceeds(updateDoc(doc(a, 'groups/g1'),
    { memberUids: ['alice'], updatedAt: now() }));
  await assertSucceeds(deleteDoc(doc(a, 'groups/g1')));
});

// ------------------------------------------------------------------ shares

test('shares: send ok, extra field refused, outsider cannot read', async () => {
  const a = as('alice', 'alice@uni.edu');
  await assertSucceeds(setDoc(doc(a, 'shares/s1'), share('alice', 'bob')));
  await assertFails(setDoc(doc(a, 'shares/s2'),
    share('alice', 'bob', { extra: 'x' })));
  await assertFails(setDoc(doc(a, 'shares/s3'), share('bob', 'carol')));
  await assertFails(getDoc(doc(as('carol', 'c@uni.edu'), 'shares/s1')));
});

test('shares: recipient answers then deletes; sender may withdraw pending', async () => {
  const a = as('alice', 'alice@uni.edu');
  const b = as('bob', 'bob@uni.edu');
  await setDoc(doc(a, 'shares/s1'), share('alice', 'bob'));
  await setDoc(doc(a, 'shares/s2'), share('alice', 'bob'));
  await assertSucceeds(getDocs(query(collection(b, 'shares'), where('toUid', '==', 'bob'))));
  await assertSucceeds(updateDoc(doc(b, 'shares/s1'),
    { state: 'accepted', respondedAt: now() }));
  await assertSucceeds(deleteDoc(doc(b, 'shares/s1')));
  await assertSucceeds(deleteDoc(doc(a, 'shares/s2')));
});

// -------------------------------------------------------------------- chat

async function groupWithBob() {
  await createGroup(as('alice', 'alice@uni.edu'), 'alice', 'g1', 'ABCDEF');
  await updateDoc(doc(as('bob', 'bob@uni.edu'), 'groups/g1'),
    { memberUids: arrayUnion('bob'), updatedAt: now() });
}

function sendBatch(db, chatId, from, msgExtra = {}, chatExtra = {}) {
  const b = writeBatch(db);
  b.set(doc(db, `chats/${chatId}/messages/${'m' + Math.random().toString(36).slice(2)}`),
    message(from, msgExtra));
  b.set(doc(db, `chats/${chatId}`), {
    kind: 'group', groupId: 'g1', lastText: 'hi', lastFromUid: from,
    lastFromName: from, lastAt: now(), readAt: { [from]: now() }, ...chatExtra,
  }, { merge: true });
  return b.commit();
}

test('group chat: first message batch by a member passes', async () => {
  await groupWithBob();
  await assertSucceeds(sendBatch(as('bob', 'bob@uni.edu'), 'grp_g1', 'bob'));
  await assertSucceeds(sendBatch(as('alice', 'alice@uni.edu'), 'grp_g1', 'alice'));
  await assertSucceeds(setDoc(doc(as('bob', 'bob@uni.edu'), 'chats/grp_g1'),
    { readAt: { bob: now() } }, { merge: true }));
  await assertSucceeds(setDoc(doc(as('bob', 'bob@uni.edu'), 'chats/grp_g1'),
    { typingAt: { bob: now() } }, { merge: true }));
});

test('group chat: outsider refused, system kind refused, spoofed sender refused', async () => {
  await groupWithBob();
  const m = as('mallory', 'm@uni.edu');
  await assertFails(sendBatch(m, 'grp_g1', 'mallory'));
  const b = as('bob', 'bob@uni.edu');
  await assertFails(sendBatch(b, 'grp_g1', 'bob', { kind: 'system' }));
  await assertSucceeds(sendBatch(b, 'grp_g1', 'bob'));
  await assertFails(setDoc(doc(b, 'chats/grp_g1'), { lastFromUid: 'alice' }, { merge: true }));
  await assertFails(setDoc(doc(b, 'chats/grp_g1'),
    { readAt: { alice: now() } }, { merge: true }));
  await assertFails(getDocs(collection(m, 'chats/grp_g1/messages')));
});

test('group chat: first write cannot point the thread at another group', async () => {
  await groupWithBob();
  await assertFails(sendBatch(as('bob', 'bob@uni.edu'), 'grp_g1', 'bob', {}, { groupId: 'g2' }));
});

test('direct chat: open, message, outsider locked out', async () => {
  await seedAccepted('alice', 'bob');
  const a = as('alice', 'alice@uni.edu');
  await assertSucceeds(setDoc(doc(a, 'chats/dm_alice_bob'),
    { kind: 'direct', memberUids: ['alice', 'bob'] }, { merge: true }));
  await assertSucceeds(setDoc(doc(a, 'chats/dm_alice_bob'),
    { kind: 'direct', memberUids: ['alice', 'bob'] }, { merge: true }));
  await assertFails(setDoc(doc(a, 'chats/dm_alice_carol'),
    { kind: 'direct', memberUids: ['alice', 'carol'], extra: 1 }));
  await assertSucceeds(setDoc(doc(a, 'chats/dm_alice_bob/messages/m1'), message('alice')));
  await assertSucceeds(getDocs(query(collection(as('bob', 'bob@uni.edu'), 'chats'),
    where('memberUids', 'array-contains', 'bob'))));
  await assertFails(getDoc(doc(as('carol', 'c@uni.edu'), 'chats/dm_alice_bob/messages/m1')));
});

test('blobs: payload only', async () => {
  await seedAccepted('alice', 'bob');
  const a = as('alice', 'alice@uni.edu');
  await setDoc(doc(a, 'chats/dm_alice_bob'), { kind: 'direct', memberUids: ['alice', 'bob'] });
  await assertSucceeds(setDoc(doc(a, 'chats/dm_alice_bob/blobs/b1'),
    { payload: 'x', fromUid: 'alice', createdAt: now() }));
  await assertFails(setDoc(doc(a, 'chats/dm_alice_bob/blobs/b2'),
    { payload: 'x', fromUid: 'alice', createdAt: now(), more: 'y' }));
});

// ------------------------------------------------------- blocks, reports

async function openDm(db) {
  await seedAccepted('alice', 'bob');
  await setDoc(doc(db, 'chats/dm_alice_bob'),
    { kind: 'direct', memberUids: ['alice', 'bob'] }, { merge: true });
}

test('blocks: private to their owner', async () => {
  const a = as('alice', 'alice@uni.edu');
  await assertSucceeds(setDoc(doc(a, 'blocks/alice'),
    { uids: ['bob'], updatedAt: now() }));
  await assertSucceeds(getDoc(doc(a, 'blocks/alice')));
  await assertFails(getDoc(doc(as('bob', 'bob@uni.edu'), 'blocks/alice')));
  await assertFails(setDoc(doc(as('bob', 'bob@uni.edu'), 'blocks/alice'),
    { uids: [], updatedAt: now() }));
  await assertFails(setDoc(doc(a, 'blocks/alice'),
    { uids: ['bob'], updatedAt: now(), extra: 1 }));
});

test('blocks: a blocked person cannot message or open a DM; others still can', async () => {
  const a = as('alice', 'alice@uni.edu');
  const b = as('bob', 'bob@uni.edu');
  await openDm(a);
  await assertSucceeds(setDoc(doc(b, 'chats/dm_alice_bob/messages/m0'), message('bob')));
  await setDoc(doc(a, 'blocks/alice'), { uids: ['bob'], updatedAt: now() });
  await assertFails(setDoc(doc(b, 'chats/dm_alice_bob/messages/m1'), message('bob')));
  await assertFails(setDoc(doc(b, 'chats/dm_alice_bob/blobs/x1'),
    { payload: 'x', fromUid: 'bob', createdAt: now() }));
  // Alice, who did the blocking, is not blocked herself.
  await assertSucceeds(setDoc(doc(a, 'chats/dm_alice_bob/messages/m2'), message('alice')));
  // A fresh DM with someone who blocked you is refused.
  await setDoc(doc(as('carol', 'c@uni.edu'), 'blocks/carol'), { uids: ['bob'], updatedAt: now() });
  await assertFails(setDoc(doc(b, 'chats/dm_bob_carol'),
    { kind: 'direct', memberUids: ['bob', 'carol'] }));
  // Unblocking restores it.
  await setDoc(doc(a, 'blocks/alice'), { uids: [], updatedAt: now() });
  await assertSucceeds(setDoc(doc(b, 'chats/dm_alice_bob/messages/m3'), message('bob')));
});

const report = (from, target, extra = {}) => ({
  reporterUid: from, targetUid: target, reason: 'harassment', details: '',
  chatId: 'dm_alice_bob', messageId: 'm1', shareId: '', messageText: 'mean',
  createdAt: now(), ...extra,
});

test('reports: write-only, as yourself, about someone else', async () => {
  const a = as('alice', 'alice@uni.edu');
  await assertSucceeds(setDoc(doc(a, 'reports/r1'), report('alice', 'bob')));
  await assertFails(getDoc(doc(a, 'reports/r1')));
  await assertFails(getDoc(doc(as('bob', 'bob@uni.edu'), 'reports/r1')));
  await assertFails(setDoc(doc(a, 'reports/r2'), report('bob', 'carol')));
  await assertFails(setDoc(doc(a, 'reports/r3'), report('alice', 'alice')));
  await assertFails(setDoc(doc(a, 'reports/r4'), report('alice', 'bob', { reason: 'boring' })));
  await assertFails(setDoc(doc(a, 'reports/r5'), report('alice', 'bob', { extra: 1 })));
  await assertFails(updateDoc(doc(a, 'reports/r1'), { details: 'edit' }));
});

// ------------------------------------------------------------ profile photo

test('profile: a small photo is allowed, an oversized one refused', async () => {
  const a = as('alice', 'alice@uni.edu');
  await assertSucceeds(setDoc(doc(a, 'users/alice'),
    profile('alice', 'alice@uni.edu', { photo: 'x'.repeat(30000) })));
  await assertFails(setDoc(doc(a, 'users/alice'),
    profile('alice', 'alice@uni.edu', { photo: 'x'.repeat(40001) }),
    { merge: true }));
});

// --------------------------------------------------------------- classwork

async function createClass(db, owner, classId, code) {
  const b = writeBatch(db);
  b.set(doc(db, 'groups', classId), group(owner, code, { kind: 'class' }));
  b.set(doc(db, 'joinCodes', code), {
    groupId: classId, name: 'Algorithms', ownerUid: owner, createdAt: now(),
  });
  return b.commit();
}

const post = (author, extra = {}) => ({
  kind: 'assignment', title: 'Lab 3', body: 'Do it', topic: 'Week 3',
  dueAt: now() + 86400000, points: 100,
  files: [{ id: 'drive123', name: 'lab3.pdf', mime: 'application/pdf', size: 10 }],
  authorUid: author, authorName: author, createdAt: now(), updatedAt: now(),
  ...extra,
});

const work = (uid, extra = {}) => ({
  uid, name: uid, text: 'my answer', files: [], state: 'turnedIn',
  submittedAt: now(), updatedAt: now(), ...extra,
});

// A teacher with a class, and two students in it.
async function seedClass() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/tara'),
      profile('tara', 'tara@uni.edu', { role: 'teacher' }));
    await setDoc(doc(db, 'users/sam'), profile('sam', 'sam@uni.edu'));
    await setDoc(doc(db, 'users/sue'), profile('sue', 'sue@uni.edu'));
  });
  const t = as('tara', 'tara@uni.edu');
  await createClass(t, 'tara', 'c1', 'CLASS1');
  for (const s of ['sam', 'sue']) {
    await updateDoc(doc(as(s, `${s}@uni.edu`), 'groups/c1'),
      { memberUids: arrayUnion(s), updatedAt: now() });
  }
  return t;
}

test('classes: a student account cannot make a class; a teacher can', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/sam'), profile('sam', 'sam@uni.edu'));
    await setDoc(doc(db, 'users/tara'),
      profile('tara', 'tara@uni.edu', { role: 'teacher' }));
  });
  await assertFails(createClass(as('sam', 'sam@uni.edu'), 'sam', 'c9', 'SAMSAM'));
  await assertSucceeds(createClass(as('tara', 'tara@uni.edu'), 'tara', 'c1', 'CLASS1'));
  // A study group is still anyone's to make.
  await assertSucceeds(createGroup(as('sam', 'sam@uni.edu'), 'sam', 'g1', 'STUDY1'));
});

test('posts: teacher posts, members read, students and outsiders cannot post', async () => {
  const t = await seedClass();
  await assertSucceeds(setDoc(doc(t, 'groups/c1/posts/p1'), post('tara')));
  await assertFails(setDoc(doc(t, 'groups/c1/posts/p2'),
    post('tara', { junk: 1 })));
  await assertFails(setDoc(doc(t, 'groups/c1/posts/p3'),
    post('tara', { points: 5000 })));

  const sam = as('sam', 'sam@uni.edu');
  await assertSucceeds(getDoc(doc(sam, 'groups/c1/posts/p1')));
  await assertSucceeds(getDocs(collection(sam, 'groups/c1/posts')));
  await assertFails(setDoc(doc(sam, 'groups/c1/posts/p4'), post('sam')));

  const out = as('olly', 'olly@uni.edu');
  await assertFails(getDoc(doc(out, 'groups/c1/posts/p1')));

  // The deadline can move; the files cannot be swapped.
  await assertSucceeds(updateDoc(doc(t, 'groups/c1/posts/p1'),
    { dueAt: now() + 2 * 86400000, updatedAt: now() }));
  await assertFails(updateDoc(doc(t, 'groups/c1/posts/p1'),
    { files: [], updatedAt: now() }));
});

test('posts: a study group owner gets no classwork', async () => {
  const a = as('alice', 'alice@uni.edu');
  await createGroup(a, 'alice', 'g1', 'ABCDEF');
  await assertFails(setDoc(doc(a, 'groups/g1/posts/p1'), post('alice')));
});

test('submissions: own work only, private from classmates, honest hand-in time', async () => {
  const t = await seedClass();
  await setDoc(doc(t, 'groups/c1/posts/p1'), post('tara'));
  const sam = as('sam', 'sam@uni.edu');
  const sue = as('sue', 'sue@uni.edu');

  await assertSucceeds(setDoc(doc(sam, 'groups/c1/posts/p1/submissions/sam'),
    work('sam'), { merge: true }));
  // Not as somebody else.
  await assertFails(setDoc(doc(sam, 'groups/c1/posts/p1/submissions/sue'),
    work('sue')));
  // Not with a grade.
  await assertFails(setDoc(doc(sue, 'groups/c1/posts/p1/submissions/sue'),
    work('sue', { grade: 100 })));
  // Not backdated to dodge "late".
  await assertFails(setDoc(doc(sue, 'groups/c1/posts/p1/submissions/sue'),
    work('sue', { submittedAt: now() - 3 * 86400000 })));
  // A classmate cannot read it; the teacher can.
  await assertFails(getDoc(doc(sue, 'groups/c1/posts/p1/submissions/sam')));
  await assertSucceeds(getDocs(collection(t, 'groups/c1/posts/p1/submissions')));
  // A draft needs no hand-in time.
  await assertSucceeds(setDoc(doc(sue, 'groups/c1/posts/p1/submissions/sue'),
    work('sue', { state: 'draft', submittedAt: null })));
});

test('submissions: teacher grades and returns, but cannot rewrite the work', async () => {
  const t = await seedClass();
  await setDoc(doc(t, 'groups/c1/posts/p1'), post('tara'));
  const sam = as('sam', 'sam@uni.edu');
  await setDoc(doc(sam, 'groups/c1/posts/p1/submissions/sam'), work('sam'));

  await assertSucceeds(updateDoc(doc(t, 'groups/c1/posts/p1/submissions/sam'), {
    grade: 88, feedback: 'Good', state: 'returned', returnedAt: now(),
  }));
  await assertFails(updateDoc(doc(t, 'groups/c1/posts/p1/submissions/sam'),
    { text: 'something else' }));
  // The student cannot change their own grade afterwards.
  await assertFails(updateDoc(doc(sam, 'groups/c1/posts/p1/submissions/sam'),
    { grade: 100, updatedAt: now() }));
  // But may take the work back to change it.
  await assertSucceeds(setDoc(doc(sam, 'groups/c1/posts/p1/submissions/sam'),
    work('sam', { state: 'draft', submittedAt: null }), { merge: true }));
});

test('submissions: only on an assignment, not a material', async () => {
  const t = await seedClass();
  await setDoc(doc(t, 'groups/c1/posts/m1'),
    post('tara', { kind: 'material', dueAt: null, points: null }));
  await assertFails(setDoc(
    doc(as('sam', 'sam@uni.edu'), 'groups/c1/posts/m1/submissions/sam'),
    work('sam')));
});

// ------------------------------------------------------- message requests

// message requests are created together with the daily counter, as the app does
async function seedReq(id, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'dmRequests', id), data);
  });
}
async function reqBatch(db, uid, id, data) {
  const b = writeBatch(db);
  b.set(doc(db, 'dmQuota', uid), { day: Math.floor(Date.now() / 86400000), count: 1 });
  b.set(doc(db, 'dmRequests', id), data);
  return b.commit();
}

const dmReq = (from, to, extra = {}) => ({
  fromUid: from, toUid: to, text: 'Hi, can we talk?', state: 'pending',
  createdAt: now(), ...extra,
});

test('requests: cannot open a new chat without an accepted request', async () => {
  const a = as('alice', 'alice@uni.edu');
  await assertFails(setDoc(doc(a, 'chats/dm_alice_bob'),
    { kind: 'direct', memberUids: ['alice', 'bob'] }, { merge: true }));
  await assertSucceeds(reqBatch(a, 'alice', 'dm_alice_bob', dmReq('alice', 'bob')));
  // Still pending: still no chat, for either side.
  await assertFails(setDoc(doc(a, 'chats/dm_alice_bob'),
    { kind: 'direct', memberUids: ['alice', 'bob'] }, { merge: true }));
  const b = as('bob', 'bob@uni.edu');
  await assertFails(setDoc(doc(b, 'chats/dm_alice_bob'),
    { kind: 'direct', memberUids: ['alice', 'bob'] }, { merge: true }));
  await assertSucceeds(updateDoc(doc(b, 'dmRequests/dm_alice_bob'),
    { state: 'accepted', respondedAt: now() }));
  await assertSucceeds(setDoc(doc(b, 'chats/dm_alice_bob'),
    { kind: 'direct', memberUids: ['alice', 'bob'] }, { merge: true }));
  await assertSucceeds(setDoc(doc(a, 'chats/dm_alice_bob/messages/m1'), message('alice')));
});

test('requests: create as yourself, right id, pending, bounded text', async () => {
  const a = as('alice', 'alice@uni.edu');
  await assertFails(reqBatch(a, 'alice', 'dm_alice_bob', dmReq('bob', 'alice')));
  await assertFails(reqBatch(a, 'alice', 'dm_alice_carol', dmReq('alice', 'bob')));
  await assertFails(reqBatch(a, 'alice', 'dm_alice_bob', dmReq('alice', 'bob', { state: 'accepted' })));
  await assertFails(reqBatch(a, 'alice', 'dm_alice_bob', dmReq('alice', 'bob', { text: 'x'.repeat(501) })));
  await assertFails(reqBatch(a, 'alice', 'dm_alice_bob', dmReq('alice', 'bob', { text: '' })));
  await assertFails(reqBatch(a, 'alice', 'dm_alice_bob', dmReq('alice', 'bob', { extra: 1 })));
  await assertFails(reqBatch(a, 'alice', 'dm_alice_alice', dmReq('alice', 'alice')));
  await assertSucceeds(reqBatch(a, 'alice', 'dm_alice_bob', dmReq('alice', 'bob')));
});

test('requests: only the recipient answers; sender cannot accept or reset', async () => {
  const a = as('alice', 'alice@uni.edu');
  const b = as('bob', 'bob@uni.edu');
  await seedReq('dm_alice_bob', dmReq('alice', 'bob'));
  await assertFails(updateDoc(doc(a, 'dmRequests/dm_alice_bob'), { state: 'accepted' }));
  await assertFails(reqBatch(as('carol', 'c@uni.edu'), 'carol', 'dm_alice_bob', dmReq('alice', 'bob', { state: 'accepted' })));
  await assertFails(updateDoc(doc(b, 'dmRequests/dm_alice_bob'), { text: 'edited' }));
  await assertFails(updateDoc(doc(b, 'dmRequests/dm_alice_bob'), { state: 'pending' }));
  await assertSucceeds(updateDoc(doc(b, 'dmRequests/dm_alice_bob'), { state: 'declined', respondedAt: now() }));
  // After a decline the sender can neither re-send, reset, nor delete it.
  await assertFails(reqBatch(a, 'alice', 'dm_alice_bob', dmReq('alice', 'bob')));
  await assertFails(updateDoc(doc(a, 'dmRequests/dm_alice_bob'), { state: 'pending' }));
  await assertFails(deleteDoc(doc(a, 'dmRequests/dm_alice_bob')));
  // Bob can change his mind.
  await assertSucceeds(updateDoc(doc(b, 'dmRequests/dm_alice_bob'), { state: 'accepted', respondedAt: now() }));
});

test('requests: the other direction cannot create a second request', async () => {
  const a = as('alice', 'alice@uni.edu');
  const b = as('bob', 'bob@uni.edu');
  await seedReq('dm_alice_bob', dmReq('alice', 'bob'));
  await assertFails(reqBatch(b, 'bob', 'dm_alice_bob', dmReq('bob', 'alice')));
});

test('requests: outsiders cannot read; missing request reads as absent', async () => {
  const a = as('alice', 'alice@uni.edu');
  await seedReq('dm_alice_bob', dmReq('alice', 'bob'));
  await assertFails(getDoc(doc(as('carol', 'c@uni.edu'), 'dmRequests/dm_alice_bob')));
  await assertSucceeds(getDoc(doc(as('bob', 'bob@uni.edu'), 'dmRequests/dm_alice_bob')));
  const miss = await assertSucceeds(getDoc(doc(a, 'dmRequests/dm_alice_zed')));
  if (miss.exists()) throw new Error('should be absent');
  await assertSucceeds(getDocs(query(collection(as('bob', 'bob@uni.edu'), 'dmRequests'),
    where('toUid', '==', 'bob'))));
  await assertFails(getDocs(query(collection(as('carol', 'c@uni.edu'), 'dmRequests'),
    where('toUid', '==', 'bob'))));
});

test('requests: blocked sender cannot ask; sender may withdraw a pending one', async () => {
  const a = as('alice', 'alice@uni.edu');
  const b = as('bob', 'bob@uni.edu');
  await setDoc(doc(b, 'blocks/bob'), { uids: ['alice'], updatedAt: now() });
  await assertFails(reqBatch(a, 'alice', 'dm_alice_bob', dmReq('alice', 'bob')));
  await setDoc(doc(b, 'blocks/bob'), { uids: [], updatedAt: now() });
  await assertSucceeds(reqBatch(a, 'alice', 'dm_alice_bob', dmReq('alice', 'bob')));
  await assertSucceeds(deleteDoc(doc(a, 'dmRequests/dm_alice_bob')));
});

// ---------------------------------------------------- request daily quota

const day = () => Math.floor(Date.now() / 86400000);

async function sendRequest(db, from, to, count = 1, extra = {}) {
  const b = writeBatch(db);
  b.set(doc(db, 'dmQuota', from), { day: day(), count });
  b.set(doc(db, 'dmRequests', from < to ? `dm_${from}_${to}` : `dm_${to}_${from}`),
    dmReq(from, to, extra));
  return b.commit();
}

test('quota: a request needs its counter bumped in the same batch', async () => {
  const a = as('alice', 'alice@uni.edu');
  // Bare request, no counter: refused.
  await assertFails(setDoc(doc(a, 'dmRequests/dm_alice_bob'), dmReq('alice', 'bob')));
  await assertSucceeds(sendRequest(a, 'alice', 'bob', 1));
});

test('quota: counter only goes up by one, caps at 20, resets next day', async () => {
  const a = as('alice', 'alice@uni.edu');
  await assertSucceeds(setDoc(doc(a, 'dmQuota/alice'), { day: day(), count: 1 }));
  await assertFails(setDoc(doc(a, 'dmQuota/alice'), { day: day(), count: 5 }));
  await assertFails(setDoc(doc(a, 'dmQuota/alice'), { day: day(), count: 1 }));
  await assertSucceeds(setDoc(doc(a, 'dmQuota/alice'), { day: day(), count: 2 }));
  await assertFails(setDoc(doc(a, 'dmQuota/alice'), { day: day() - 1, count: 3 }));
  // Somebody else's counter is not yours to touch or read.
  await assertFails(setDoc(doc(as('bob', 'b@uni.edu'), 'dmQuota/alice'), { day: day(), count: 3 }));
  await assertFails(getDoc(doc(as('bob', 'b@uni.edu'), 'dmQuota/alice')));
  await assertFails(deleteDoc(doc(a, 'dmQuota/alice')));
  await assertFails(setDoc(doc(a, 'dmQuota/alice'), { day: day(), count: 21 }));
});
