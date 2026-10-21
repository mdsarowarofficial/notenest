// NoteNest push notifications.
//
// The app has no server of its own: phones talk to Firestore. A phone that is
// closed cannot hear Firestore, so this file is the one piece that runs in the
// cloud. It watches for four things being written, and sends the people they
// are for a notification through Firebase Cloud Messaging:
//
//   - a message in a chat or a class chat
//   - a message request (somebody asking to talk)
//   - a post in a class (announcement, material, assignment)
//   - a note sent to somebody
//
// Where each phone can be reached is in pushTokens/{uid}, written by the app.
// Deploy with:  firebase deploy --only functions
// (needs the Blaze plan; see docs/PUSH_SETUP.md).

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// A notification is a preview, not the message. Kept short so nothing long or
// private sits on a lock screen.
const clip = (text, n = 120) => {
  const t = String(text || '').replace(/\s+/g, ' ').trim();
  return t.length > n ? `${t.slice(0, n - 1)}…` : t;
};

// Who among [uids] has blocked [fromUid], so they are not pinged by them.
async function blockedBy(uids, fromUid) {
  const snaps = await Promise.all(uids.map((u) => db.doc(`blocks/${u}`).get()));
  const out = new Set();
  snaps.forEach((s, i) => {
    const list = (s.exists && s.data().uids) || [];
    if (list.includes(fromUid)) out.add(uids[i]);
  });
  return out;
}

// Sends one notification to every phone of every person in [uids], and
// forgets tokens that Firebase says no longer exist.
async function notify(uids, { title, body, data }) {
  const unique = [...new Set(uids)].filter(Boolean);
  if (unique.length === 0) return;

  const snaps = await Promise.all(unique.map((u) => db.doc(`pushTokens/${u}`).get()));
  const targets = [];
  snaps.forEach((s, i) => {
    if (!s.exists) return;
    for (const token of s.data().tokens || []) targets.push({ uid: unique[i], token });
  });
  if (targets.length === 0) return;

  const res = await admin.messaging().sendEachForMulticast({
    tokens: targets.map((t) => t.token),
    notification: { title: clip(title, 60), body: clip(body, 140) },
    data: Object.fromEntries(
      Object.entries(data || {}).map(([k, v]) => [k, String(v)])),
    android: {
      priority: 'high',
      notification: { channelId: 'messages' },
    },
  });

  const dead = new Map();
  res.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ) {
      const { uid, token } = targets[i];
      if (!dead.has(uid)) dead.set(uid, []);
      dead.get(uid).push(token);
    }
  });
  await Promise.all([...dead].map(([uid, tokens]) =>
    db.doc(`pushTokens/${uid}`).update({
      tokens: admin.firestore.FieldValue.arrayRemove(...tokens),
    })));
}

const previewOf = (m) => {
  switch (m.kind) {
    case 'note': return `📄 ${m.title || 'A note'}`;
    case 'image': return '🖼 Photo';
    case 'voice': return '🎤 Voice message';
    default: return clip(m.text);
  }
};

// ------------------------------------------------------------- a chat message
exports.onChatMessage = onDocumentCreated(
  'chats/{chatId}/messages/{messageId}',
  async (event) => {
    const m = event.data && event.data.data();
    if (!m) return;
    const { chatId } = event.params;

    let recipients = [];
    let title = m.fromName || 'NoteNest';
    let body = previewOf(m);

    if (chatId.startsWith('grp_')) {
      // A group or class chat: everyone in the group.
      const groupId = chatId.slice(4);
      const group = await db.doc(`groups/${groupId}`).get();
      if (!group.exists) return;
      recipients = group.data().memberUids || [];
      title = group.data().name || title;
      body = `${m.fromName || 'Someone'}: ${previewOf(m)}`;
    } else {
      const chat = await db.doc(`chats/${chatId}`).get();
      recipients = (chat.exists && chat.data().memberUids) || [];
    }

    recipients = recipients.filter((u) => u !== m.fromUid);
    const blocked = await blockedBy(recipients, m.fromUid);
    recipients = recipients.filter((u) => !blocked.has(u));

    await notify(recipients, {
      title,
      body,
      data: { type: 'chat', chatId },
    });
  },
);

// ------------------------------------------------------- a message request
exports.onMessageRequest = onDocumentCreated('dmRequests/{requestId}', async (event) => {
  const r = event.data && event.data.data();
  if (!r || r.state !== 'pending') return;

  const blocked = await blockedBy([r.toUid], r.fromUid);
  if (blocked.has(r.toUid)) return;

  const sender = await db.doc(`users/${r.fromUid}`).get();
  const name = (sender.exists && sender.data().name) || 'Someone';
  await notify([r.toUid], {
    title: 'New message request',
    body: `${name}: ${clip(r.text, 100)}`,
    data: { type: 'request' },
  });
});

// ------------------------------------------------------- a class post
exports.onClassPost = onDocumentCreated('groups/{groupId}/posts/{postId}', async (event) => {
  const p = event.data && event.data.data();
  if (!p) return;
  const group = await db.doc(`groups/${event.params.groupId}`).get();
  if (!group.exists) return;

  const label = { announcement: 'Announcement', material: 'New material', assignment: 'New assignment' }[p.kind] || 'New post';
  const recipients = (group.data().memberUids || []).filter((u) => u !== p.authorUid);
  await notify(recipients, {
    title: group.data().name || 'Your class',
    body: `${label}: ${p.title || ''}`,
    data: { type: 'post', groupId: event.params.groupId },
  });
});

// ------------------------------------------------------- a note sent to you
exports.onSharedNote = onDocumentCreated('shares/{shareId}', async (event) => {
  const s = event.data && event.data.data();
  if (!s || s.state !== 'pending' || !s.toUid) return;

  const blocked = await blockedBy([s.toUid], s.fromUid);
  if (blocked.has(s.toUid)) return;

  await notify([s.toUid], {
    title: `${s.fromName || 'A classmate'} sent you a note`,
    body: s.title || 'Open NoteNest to accept it.',
    data: { type: 'share' },
  });
});
