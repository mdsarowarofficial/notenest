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
  const a = as('alice', 'alice@uni.edu');
  await setDoc(doc(a, 'chats/dm_alice_bob'), { kind: 'direct', memberUids: ['alice', 'bob'] });
  await assertSucceeds(setDoc(doc(a, 'chats/dm_alice_bob/blobs/b1'),
    { payload: 'x', fromUid: 'alice', createdAt: now() }));
  await assertFails(setDoc(doc(a, 'chats/dm_alice_bob/blobs/b2'),
    { payload: 'x', fromUid: 'alice', createdAt: now(), more: 'y' }));
});

// ------------------------------------------------------- blocks, reports

async function openDm(db) {
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
