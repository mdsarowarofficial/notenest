import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/chat.dart';
import '../models/cloud_profile.dart';
import '../models/note_share.dart';
import '../models/study_group.dart';
import 'google_identity.dart';

/// Everything that talks to Firebase.
///
/// **The cloud is an extra, never a requirement.** NoteNest worked entirely on
/// the device for nine activities and it still does: notes, subjects, exams,
/// cover pages and conversions never touch this class. If Firebase cannot
/// start — no config, no connection, a project that was deleted — the app
/// opens normally and the cloud screen explains itself. Nothing else notices.
///
/// That is why every method here begins by checking [isReady] instead of
/// assuming it. `FirebaseAuth.instance` throws if it is read before
/// `Firebase.initializeApp` has succeeded, and one such read on a startup path
/// would take the whole app down for a student who only wanted to write a note.
class CloudService extends ChangeNotifier {
  CloudService._();

  static final CloudService instance = CloudService._();

  bool _ready = false;
  String? _startupError;
  CloudProfile? _profile;
  bool _busy = false;

  /// True once `Firebase.initializeApp` has succeeded.
  bool get isReady => _ready;

  /// Why Firebase could not start, for the one screen that should say so.
  String? get startupError => _startupError;

  /// The signed-in account's profile document, or null.
  CloudProfile? get profile => _profile;

  bool get isBusy => _busy;

  bool get isSignedIn => _ready && FirebaseAuth.instance.currentUser != null;

  String? get uid => _ready ? FirebaseAuth.instance.currentUser?.uid : null;

  FirebaseFirestore get _store => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _store.collection('users');

  CollectionReference<Map<String, dynamic>> get _groups =>
      _store.collection('groups');

  CollectionReference<Map<String, dynamic>> get _joinCodes =>
      _store.collection('joinCodes');

  CollectionReference<Map<String, dynamic>> get _shares =>
      _store.collection('shares');

  CollectionReference<Map<String, dynamic>> get _chats =>
      _store.collection('chats');

  /// address → uid, one tiny document per account.
  ///
  /// This exists so that finding a classmate is a `get` of one document whose
  /// name you already know, instead of a query across every account. The rules
  /// used to allow listing `users` with a limit of twenty, on the reasoning
  /// that the caller only ever learns a name against an address they already
  /// had. That reasoning was wrong: a query is not obliged to be the query the
  /// app makes. Anyone could ask for twenty accounts ordered by anything, page
  /// through with a cursor, and walk out with every name, address and
  /// institution in the project.
  ///
  /// Reading this index still tells a caller whether one address they typed is
  /// registered, which is an honest cost: it answers one guess at a time and
  /// hands back no name. Listing is closed.
  CollectionReference<Map<String, dynamic>> get _emailIndex =>
      _store.collection('emailIndex');

  /// Profiles already fetched, so opening a group of thirty does not read
  /// thirty documents every time the screen rebuilds.
  final Map<String, CloudProfile> _profileCache = {};

  final _random = Random();

  /// When a typing flag was last written, per thread. See [setTyping].
  final Map<String, DateTime> _lastTypingWrite = {};

  // ------------------------------------------------------------- startup

  /// How long the first frame is willing to wait for Firebase.
  ///
  /// There has to be a limit, and this is the whole reason why: on a
  /// connection that cannot reach Google at all, `Firebase.initializeApp` does
  /// not fail — it waits. `main` awaits this before `runApp`, so a wait with no
  /// end is a white screen with no end, on a device where every note is sitting
  /// on the disk ready to be shown.
  ///
  /// Five seconds is far longer than a working connection needs (under a
  /// second, usually) and short enough that a broken one is not mistaken for a
  /// broken app.
  static const startupTimeout = Duration(seconds: 5);

  /// Starts Firebase. Never throws, and never waits forever.
  ///
  /// Called from `main` before the first frame, so the drawer can show whether
  /// the cloud is available without a flash of the wrong state.
  Future<void> start() async {
    if (_ready) return;
    try {
      await _connect().timeout(startupTimeout);
    } on TimeoutException {
      _ready = false;
      _startupError = 'Firebase did not answer within '
          '${startupTimeout.inSeconds} seconds, so the cloud is off for now. '
          'Everything stored on this device still works. Check your '
          'connection and reopen the app to try again.';
      notifyListeners();
      return;
    } catch (e) {
      _ready = false;
      _startupError = 'Firebase could not start. Everything that works on '
          'this device still works; only the cloud features are off.\n\n$e';
      notifyListeners();
      return;
    }
    notifyListeners();
  }

  /// The part that can hang. Separated so one timeout covers all of it —
  /// including reading the profile, which is a network call of its own and
  /// would otherwise be an unbounded wait sitting just past a bounded one.
  Future<void> _connect() async {
    await Firebase.initializeApp(
      // The options are needed on web: there is no google-services.json in a
      // browser, so the configuration has to be compiled in.
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _ready = true;
    _startupError = null;

    // Firebase remembers a signed-in account across restarts, so a returning
    // student should already be connected.
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _loadProfile(user.uid);
    }
  }

  // ------------------------------------------------------------- account

  /// Creates a cloud account and its profile document.
  ///
  /// Throws [CloudException] with a message written for the student.
  Future<void> createAccount({
    required String name,
    required String email,
    required String password,
    required CloudRole role,
    String institution = '',
  }) async {
    _requireReady();
    await _run(() async {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: normaliseEmail(email),
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw const CloudException('The account was not created. Try again.');
      }

      // Shown by Firebase itself in the console user list, which makes the
      // project far easier to read while testing.
      await user.updateDisplayName(name.trim());

      final profile = CloudProfile(
        uid: user.uid,
        name: name,
        email: email,
        role: role,
        institution: institution,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _users.doc(user.uid).set(profile.toMap());
      _writeEmailIndex(user.uid, profile.email);
      _profile = profile;
    });
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    _requireReady();
    await _run(() async {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: normaliseEmail(email),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const CloudException('Signed in, but no account came back.');
      }
      await _loadProfile(user.uid);
    });
  }

  /// True when the signed-in Firebase account proves itself with Google and
  /// has no password of its own.
  ///
  /// Asked before anything that would demand a password. `providerData` is the
  /// list of ways this one account can sign in, so an account that has both —
  /// Google *and* a password, which Firebase allows — is not treated as
  /// password-less, because for that one a password check is still the right
  /// question and the stricter one.
  bool get signsInWithGoogle {
    if (!_ready) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final providers = user.providerData.map((p) => p.providerId).toSet();
    return providers.contains('google.com') && !providers.contains('password');
  }

  /// Signs in to Firebase with a Google account, creating the profile document
  /// on the first time.
  ///
  /// There is no separate "register with Google". Google already knows whether
  /// this person has an account with it; whether *NoteNest* has seen them
  /// before is answered by whether `users/{uid}` exists, and [_loadProfile]
  /// writes one when it does not. So the same method sits behind the button on
  /// the login screen and the button on the register screen, and a student who
  /// taps the wrong one still ends up in the right place.
  ///
  /// Lets [GoogleSignInCancelled] through untouched. A closed sheet is not a
  /// failure and must not come out of here as a [CloudException], because the
  /// screen would then draw a red line for somebody who simply changed their
  /// mind.
  Future<void> signInWithGoogle() async {
    _requireReady();
    await _run(() async {
      final GoogleCredential google;
      try {
        google = await GoogleAccounts.instance.signIn();
      } on GoogleIdentityError catch (e) {
        throw CloudException(e.message);
      }

      final credential = await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: google.idToken),
      );
      final user = credential.user;
      if (user == null) {
        throw const CloudException(
          'Google accepted the sign-in but no account came back. Try again.',
        );
      }
      if ((user.email ?? '').isEmpty) {
        // Every path after this one is keyed on the address: the device row,
        // the index classmates are found through, the profile document. An
        // account with none would sign in and then be unreachable.
        throw const CloudException(
          'That Google account has no email address on it, so there is nothing '
          'to connect a NoteNest account to.',
        );
      }
      await _loadProfile(user.uid);
    });
  }

  /// Asks Firebase to email a password-reset link.
  ///
  /// This is the only route a forgotten password has, and it is worth being
  /// clear why: the device password is a salted hash in this phone's own
  /// database and nothing else — there is no server holding a copy and no
  /// address to send a link from. The cloud account has both, so the reset
  /// goes through it and the device password is brought back into line the
  /// next time the student signs in.
  ///
  /// Deliberately says nothing about whether the address was found. Firebase
  /// itself refuses to, and for a good reason: an answer here would turn this
  /// screen into a way of asking "does this person use NoteNest?".
  Future<void> sendPasswordReset(String email) async {
    _requireReady();
    await _run(() async {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: normaliseEmail(email));
    });
  }

  /// Deletes the cloud account: the profile, the address index, and the
  /// Firebase sign-in itself.
  ///
  /// Required by Google Play for any app that lets a person create an account.
  ///
  /// What this removes, exactly:
  ///   * users/{uid} — the name, address, role and institution classmates see.
  ///   * emailIndex/{address} — so nobody can find the account again.
  ///   * the Firebase Authentication user, so the address can be registered
  ///     afresh by whoever owns it.
  ///
  /// What it does NOT remove, and why the screen says so before asking:
  /// messages already sent, and notes already shared and accepted, stay where
  /// they landed. They are in other people's conversations and other people's
  /// notebooks — deleting them would be reaching into someone else's data, and
  /// on this plan there is no server-side job that could do it safely anyway.
  /// Those copies carry the name that was on them when they were sent.
  ///
  /// The password is required because Firebase refuses to delete an account on
  /// a stale sign-in, which is the right rule: deletion is exactly the action
  /// a borrowed phone should not be able to take.
  /// [password] is null for an account that signs in with Google. Then the
  /// proof is a fresh Google sign-in instead: the student picks their account
  /// again, which is the same demand made in a different currency, and the one
  /// Firebase will accept for an account that has no password to check.
  Future<void> deleteCloudAccount({String? password}) async {
    _requireReady();
    await _run(() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw const CloudException('Not signed in to the cloud.');
      }
      final address = normaliseEmail(user.email ?? '');

      // Proves the person at the phone is the account holder, right now.
      if (password == null) {
        final GoogleCredential google;
        try {
          google = await GoogleAccounts.instance.signIn();
        } on GoogleIdentityError catch (e) {
          throw CloudException(e.message);
        }
        await user.reauthenticateWithCredential(
          GoogleAuthProvider.credential(idToken: google.idToken),
        );
      } else {
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(
            email: address,
            password: password,
          ),
        );
      }

      // The index first: while it is gone the profile is merely unfindable,
      // whereas a profile deleted first would leave the index pointing at
      // nothing and a classmate's search returning an empty card.
      if (looksLikeEmail(address)) {
        await _emailIndex.doc(address).delete();
      }
      await _users.doc(user.uid).delete();

      // Last, because once this succeeds there is no signed-in account left
      // with permission to do the two writes above.
      await user.delete();

      _profile = null;
      _profileCache.clear();
      _lastTypingWrite.clear();
      notifyListeners();
    });
  }

  /// Signs out of the cloud only. The local account, and every note in it,
  /// is untouched.
  Future<void> signOutOfCloud() async {
    if (!_ready) return;
    await FirebaseAuth.instance.signOut();
    // Google keeps its own idea of which account was chosen, and it outlives
    // Firebase's session. Without this, signing out and tapping the Google
    // button again drops straight back into the account just left — no sheet,
    // no choice. On a shared phone that is not a convenience.
    await GoogleAccounts.instance.signOut();
    _profile = null;
    // Another account must not inherit the last one's view of who people are.
    _profileCache.clear();
    _lastTypingWrite.clear();
    notifyListeners();
  }

  Future<void> updateProfile({
    String? name,
    CloudRole? role,
    String? institution,
  }) async {
    _requireReady();
    final current = _profile;
    final id = uid;
    if (current == null || id == null) {
      throw const CloudException('You are not connected to the cloud.');
    }

    await _run(() async {
      final next = current.copyWith(
        name: name,
        role: role,
        institution: institution,
        updatedAt: DateTime.now(),
      );
      // merge, so a field this version of the app does not know about is not
      // wiped by an older client writing the whole document.
      await _users.doc(id).set(next.toMap(), SetOptions(merge: true));
      _profile = next;
    });
  }

  /// Reads the profile document, creating one if the account predates it.
  /// Points this account's address at its uid.
  ///
  /// Never fatal, and this time the code says so too. The first version caught
  /// only FirebaseException while the comment above it promised that nothing
  /// here could stop a sign in — so anything else this write threw travelled
  /// up through `_loadProfile`, became a CloudException, and came out on the
  /// login screen as "No account found for this email". A lookup table that
  /// can lock a student out of their own account is worse than no lookup
  /// table.
  ///
  /// It is also no longer awaited by the caller. The index is a convenience
  /// for other people's searches; a student signing in should not wait on a
  /// round trip that has nothing to do with their own sign in, and on a slow
  /// connection they were.
  void _writeEmailIndex(String uid, String email) {
    final key = normaliseEmail(email);
    if (!looksLikeEmail(key)) return;
    _emailIndex.doc(key).set({
      'uid': uid,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }).catchError((Object _) {
      // Every failure, not merely the Firebase-shaped ones. Rules not yet
      // published, offline, anything: the sign in carries on and the write is
      // tried again next time.
    });
  }

  Future<void> _loadProfile(String id) async {
    try {
      final snapshot = await _users.doc(id).get();
      final data = snapshot.data();
      if (data != null) {
        final profile = CloudProfile.fromMap(id, data);
        _profile = profile;
        // Written on every sign in, not only at registration, so the accounts
        // that existed before this index did become findable again the first
        // time they open the app. It is one small idempotent write.
        _writeEmailIndex(id, profile.email);
        return;
      }

      // Signed in, but no document — the account was made before profiles
      // existed, or the write failed last time. Rebuild what can be known
      // rather than leaving the app in a state with no name to show.
      final user = FirebaseAuth.instance.currentUser;
      final rebuilt = CloudProfile(
        uid: id,
        name: user?.displayName ?? '',
        email: user?.email ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _users.doc(id).set(rebuilt.toMap());
      _writeEmailIndex(id, rebuilt.email);
      _profile = rebuilt;
    } on FirebaseException catch (e) {
      throw CloudException(describeStoreError(e.code));
    }
  }

  // ------------------------------------------------------------ lookups

  /// Finds a classmate by their exact address.
  ///
  /// An exact match on the folded address, not a prefix search: a directory
  /// that lets anyone list every account by typing one letter is a directory
  /// that leaks the whole user table. Sharing a note needs the address anyway.
  Future<CloudProfile?> findByEmail(String email) async {
    _requireReady();
    final wanted = normaliseEmail(email);
    if (!looksLikeEmail(wanted)) return null;

    try {
      final entry = await _emailIndex.doc(wanted).get();
      final uid = entry.data()?['uid'];
      if (uid is! String || uid.isEmpty) return null;
      // Awaited, not just returned. An un-awaited return hands the future back
      // before it completes, so it leaves the try block and this catch never
      // sees anything it throws — the handler reads as protection it does not
      // give. `flutter analyze` caught this one.
      return await profileFor(uid);
    } on FirebaseException catch (e) {
      throw CloudException(describeStoreError(e.code));
    }
  }

  /// Reads one profile, from the cache when it is there.
  Future<CloudProfile?> profileFor(String id) async {
    _requireReady();
    final cached = _profileCache[id];
    if (cached != null) return cached;
    try {
      // A `get` of one known document, not a query. The rules allow reading a
      // profile you can name; listing the collection is a different permission
      // and deliberately far narrower.
      final snapshot = await _users.doc(id).get();
      final data = snapshot.data();
      if (data == null) return null;
      final found = CloudProfile.fromMap(id, data);
      _profileCache[id] = found;
      return found;
    } on FirebaseException catch (e) {
      throw CloudException(describeStoreError(e.code));
    }
  }

  /// Reads several profiles at once, skipping any that are missing.
  Future<List<CloudProfile>> profilesFor(Iterable<String> ids) async {
    final found = await Future.wait(ids.toSet().map(profileFor));
    return found.whereType<CloudProfile>().toList();
  }

  // -------------------------------------------------------------- groups

  /// Every group this account belongs to, live.
  ///
  /// `array-contains` on the member list is not only how the screen finds the
  /// right rows — it is what makes the read legal. The security rule allows a
  /// group to be read only by a member, and Firestore will refuse a query it
  /// cannot prove stays inside that, so a query without this clause fails
  /// rather than returning somebody else's groups.
  Stream<List<StudyGroup>> watchGroups() {
    final id = uid;
    if (!_ready || id == null) return Stream.value(const []);
    return _groups
        .where('memberUids', arrayContains: id)
        .snapshots()
        .map((snap) {
      final groups = snap.docs
          .map((d) => StudyGroup.fromMap(d.id, d.data()))
          .toList();
      // Sorted here rather than by Firestore: an orderBy next to the
      // array-contains needs a composite index, which is one more thing to
      // create in the console before the app works at all. A student's groups
      // are a handful of rows.
      groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return groups;
    });
  }

  Stream<StudyGroup?> watchGroup(String groupId) {
    if (!_ready) return Stream.value(null);
    return _groups.doc(groupId).snapshots().map(
          (d) => d.data() == null ? null : StudyGroup.fromMap(d.id, d.data()!),
        );
  }

  /// Creates a group and reserves its join code.
  ///
  /// The code is not checked for uniqueness by reading first — two phones
  /// could both read "free" in the same moment and both take it. Instead the
  /// `joinCodes` rule allows a create and forbids an update, so the second
  /// writer is refused by the server and tries another code. The race is
  /// decided where the data is, which is the only place it can be decided.
  Future<StudyGroup> createGroup({
    required String name,
    required GroupKind kind,
    String subject = '',
  }) async {
    _requireReady();
    final me = _profile;
    final id = uid;
    if (me == null || id == null) {
      throw const CloudException('You are not connected to the cloud.');
    }

    _busy = true;
    notifyListeners();
    try {
      for (var attempt = 0; attempt < 6; attempt++) {
        final code = buildJoinCode(_random.nextInt);
        final doc = _groups.doc();
        final group = StudyGroup(
          id: doc.id,
          name: name,
          joinCode: code,
          ownerUid: id,
          ownerName: me.name,
          kind: kind,
          subject: subject,
          memberUids: [id],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final batch = _store.batch();
        batch.set(doc, group.toMap());
        batch.set(_joinCodes.doc(code), {
          'groupId': doc.id,
          'name': name.trim(),
          'ownerUid': id,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        try {
          await batch.commit();
          return group;
        } on FirebaseException catch (e) {
          // Someone already holds this code. Any other failure is real.
          if (e.code != 'permission-denied') {
            throw CloudException(describeStoreError(e.code));
          }
        }
      }
      throw const CloudException(
        'Could not find a free group code. Try again in a moment.',
      );
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Joins a group by its code.
  ///
  /// Two steps, and the first exists because of the second: a person who is not
  /// yet a member cannot read the group at all, so the code is looked up in a
  /// small public-to-members-of-nothing collection that holds only a name and
  /// an id. Then the join itself adds exactly one uid — their own — which is
  /// the only change the rules permit anyone to make from outside.
  Future<StudyGroup> joinByCode(String rawCode) async {
    _requireReady();
    final id = uid;
    if (id == null) {
      throw const CloudException('You are not connected to the cloud.');
    }

    final code = normaliseJoinCode(rawCode);
    final problem = joinCodeProblem(code);
    if (problem != null) throw CloudException(problem);

    _busy = true;
    notifyListeners();
    try {
      final lookup = await _joinCodes.doc(code).get();
      final data = lookup.data();
      if (data == null) {
        throw const CloudException(
          'No group has that code. Check it with whoever sent it.',
        );
      }

      final groupId = data['groupId'];
      if (groupId is! String || groupId.isEmpty) {
        throw const CloudException('That code points at nothing. Ask for a new one.');
      }

      // arrayUnion, not a read-then-write. The join rule compares the member
      // list after the write against the one before it plus this uid, and that
      // comparison is made on the server — so the client never needs to have
      // read a group it is not yet allowed to read.
      await _groups.doc(groupId).update({
        'memberUids': FieldValue.arrayUnion([id]),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      final joined = await _groups.doc(groupId).get();
      final body = joined.data();
      if (body == null) {
        throw const CloudException('That group is no longer there.');
      }
      return StudyGroup.fromMap(joined.id, body);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const CloudException(
          'That join was refused. You may already be in the group — check '
          'your group list.',
        );
      }
      throw CloudException(describeStoreError(e.code));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> leaveGroup(StudyGroup group) async {
    _requireReady();
    final id = uid;
    if (id == null) {
      throw const CloudException('You are not connected to the cloud.');
    }
    if (group.isOwner(id)) {
      throw const CloudException(
        'The owner cannot leave a group. Delete it instead.',
      );
    }
    await _run(() async {
      await _groups.doc(group.id).update({
        'memberUids': FieldValue.arrayRemove([id]),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  /// Renames a group, or changes what it is about. Owner only.
  Future<void> renameGroup(
    StudyGroup group, {
    required String name,
    String? subject,
  }) async {
    _requireReady();
    await _run(() async {
      await _groups.doc(group.id).update({
        'name': name.trim(),
        if (subject != null) 'subject': subject.trim(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  /// Deletes a group and frees its code. Owner only.
  ///
  /// The code is released in the same batch, so a deleted group cannot leave a
  /// code behind that points at nothing — which is the kind of debris that
  /// makes a join fail for a reason nobody can see.
  Future<void> deleteGroup(StudyGroup group) async {
    _requireReady();
    await _run(() async {
      final batch = _store.batch();
      batch.delete(_groups.doc(group.id));
      batch.delete(_joinCodes.doc(normaliseJoinCode(group.joinCode)));
      await batch.commit();
    });
  }

  // -------------------------------------------------------------- shares

  /// Shares waiting for an answer, live.
  ///
  /// Filtered on the recipient alone and sorted here. Adding `state` or an
  /// `orderBy` to the query would need a composite index created in the
  /// console before the inbox worked at all, and an inbox is not a place to
  /// put a setup step.
  Stream<List<NoteShare>> watchIncomingShares() {
    final id = uid;
    if (!_ready || id == null) return Stream.value(const []);
    return _shares.where('toUid', isEqualTo: id).snapshots().map((snap) {
      final shares = snap.docs
          .map((d) => NoteShare.fromMap(d.id, d.data()))
          .where((s) => s.isPending)
          .toList();
      shares.sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return shares;
    });
  }

  /// Sends one note to one or more people.
  ///
  /// One document per recipient, written in a single batch so a share to a
  /// group either reaches everyone or nobody. Returns how many were sent.
  Future<int> sendNote({
    required Iterable<String> toUids,
    required String title,
    required String payload,
    String groupId = '',
    String groupName = '',
    String message = '',
    String subjectCode = '',
    int fileCount = 0,
  }) async {
    _requireReady();
    final me = _profile;
    final id = uid;
    if (me == null || id == null) {
      throw const CloudException('You are not connected to the cloud.');
    }

    if (payload.length > sharePayloadBudget) {
      throw CloudException(
        'This note is too big to send through the cloud '
        '(${formatBytes(payload.length)}). Send it as a file instead.',
      );
    }

    // Sending to yourself is not an error worth a message — it is just not a
    // share. Dropping it quietly keeps "send to the group" working for the
    // person who is in the group.
    final targets = toUids.toSet()..remove(id);
    if (targets.isEmpty) return 0;

    // A batch is capped at 500 writes. No student group reaches that, but a
    // silent half-send would be a bad way to find out.
    if (targets.length > 450) {
      throw const CloudException(
        'That is too many people to send to at once.',
      );
    }

    await _run(() async {
      final batch = _store.batch();
      final now = DateTime.now();
      for (final to in targets) {
        final doc = _shares.doc();
        batch.set(
          doc,
          NoteShare(
            id: doc.id,
            fromUid: id,
            fromName: me.name,
            toUid: to,
            title: title,
            payload: payload,
            groupId: groupId,
            groupName: groupName,
            message: message,
            subjectCode: subjectCode,
            fileCount: fileCount,
            createdAt: now,
          ).toMap(),
        );
      }
      await batch.commit();
    });

    return targets.length;
  }

  /// Records what the recipient decided.
  ///
  /// The document is kept rather than deleted, so the sender's side can one day
  /// show that a note was received — and so a declined note does not simply
  /// reappear the next time the sender presses send.
  Future<void> respondToShare(NoteShare share, {required bool accept}) async {
    _requireReady();
    await _run(() async {
      await _shares.doc(share.id).update({
        'state': (accept ? ShareState.accepted : ShareState.declined).key,
        'respondedAt': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  // ---------------------------------------------------------------- chat
  //
  // One collection for both kinds of conversation. A group thread lives at a
  // derived address — `grp_<groupId>` — so a group always has exactly one
  // chat and it never has to be created as a separate step. A direct thread
  // lives at `dm_<a>_<b>` with the two uids sorted, so both people compute the
  // same address and land in the same conversation whoever opens it first.

  DocumentReference<Map<String, dynamic>> _chat(String chatId) =>
      _chats.doc(chatId);

  CollectionReference<Map<String, dynamic>> _messages(String chatId) =>
      _chat(chatId).collection('messages');

  /// Direct conversations this account is part of, live.
  ///
  /// Group threads are deliberately not in this query. They are found through
  /// the groups themselves, which is the only place that knows who is in them
  /// — mirroring a group's member list onto its chat would mean two copies of
  /// the same truth, and the day they disagreed somebody would be locked out
  /// of a conversation they were in.
  Stream<List<ChatThread>> watchDirectChats() {
    final id = uid;
    if (!_ready || id == null) return Stream.value(const []);
    return _chats.where('memberUids', arrayContains: id).snapshots().map(
      (snap) {
        final threads =
            snap.docs.map((d) => ChatThread.fromMap(d.id, d.data())).toList();
        threads.sort((a, b) {
          final at = a.lastAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.lastAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
        return threads;
      },
    );
  }

  /// One conversation's own document: last message, read receipts, typing.
  Stream<ChatThread?> watchChat(String chatId) {
    if (!_ready) return Stream.value(null);
    return _chat(chatId).snapshots().map(
          (d) => d.data() == null
              ? null
              : ChatThread.fromMap(d.id, d.data()!),
        );
  }

  /// The messages in a conversation, newest first.
  ///
  /// Capped rather than unbounded. A conversation that has run all term should
  /// not cost a student a megabyte of mobile data to open, and the list is
  /// drawn newest-first anyway.
  Stream<List<ChatMessage>> watchMessages(String chatId, {int limit = 120}) {
    if (!_ready) return Stream.value(const []);
    return _messages(chatId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ChatMessage.fromMap(d.id, d.data())).toList());
  }

  /// Makes sure the conversation between this account and [otherUid] exists,
  /// and returns its address.
  Future<String> openDirectChat(String otherUid) async {
    _requireReady();
    final me = uid;
    if (me == null) {
      throw const CloudException('You are not connected to the cloud.');
    }
    if (otherUid == me) {
      throw const CloudException('That is you.');
    }

    final chatId = directChatId(me, otherUid);
    try {
      // `set` with merge rather than a read-then-create. Both people may well
      // open the thread at the same moment, and a merge from each of them is
      // the same write twice rather than a race.
      await _chat(chatId).set({
        'kind': ChatKind.direct.key,
        'memberUids': [me, otherUid]..sort(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw CloudException(describeStoreError(e.code));
    }
    return chatId;
  }

  /// Sends a message, and updates what the conversation list shows.
  ///
  /// Both writes go in one batch. A message that arrived but left the list
  /// showing the previous one is the kind of inconsistency nobody reports and
  /// everybody notices.
  Future<void> sendMessage({
    required String chatId,
    required MessageKind kind,
    String text = '',
    String title = '',
    String subjectCode = '',
    int fileCount = 0,
    String payload = '',
    String groupId = '',
  }) async {
    _requireReady();
    final me = _profile;
    final id = uid;
    if (me == null || id == null) {
      throw const CloudException('You are not connected to the cloud.');
    }

    if (payload.length > sharePayloadBudget) {
      throw CloudException(
        'That is too big to post here (${formatBytes(payload.length)}). '
        'Send it as a file instead.',
      );
    }

    await _run(() async {
      final now = DateTime.now();
      final batch = _store.batch();

      // The heavy part, when there is one, goes in its own document so that
      // scrolling the conversation does not drag it along.
      var blobId = '';
      if (payload.isNotEmpty) {
        final blob = _chat(chatId).collection('blobs').doc();
        blobId = blob.id;
        batch.set(blob, {
          'payload': payload,
          'fromUid': id,
          'createdAt': now.millisecondsSinceEpoch,
        });
      }

      final message = _messages(chatId).doc();
      batch.set(
        message,
        ChatMessage(
          id: message.id,
          fromUid: id,
          fromName: me.name,
          kind: kind,
          text: text,
          title: title,
          subjectCode: subjectCode,
          fileCount: fileCount,
          blobId: blobId,
          createdAt: now,
        ).toMap(),
      );

      batch.set(
        _chat(chatId),
        {
          if (groupId.isNotEmpty) ...{
            'kind': ChatKind.group.key,
            'groupId': groupId,
          },
          'lastText': ChatMessage(
            id: '',
            fromUid: id,
            fromName: me.name,
            kind: kind,
            text: text,
            title: title,
          ).preview,
          'lastFromUid': id,
          'lastFromName': me.name,
          'lastAt': now.millisecondsSinceEpoch,
          // Writing your own read stamp with the message is not a nicety: it
          // stops the thread you just spoke in from being bold to you.
          'readAt': {id: now.millisecondsSinceEpoch},
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    });
  }

  /// Fetches the heavy part of a message — a posted note's payload.
  Future<String?> loadBlob(String chatId, String blobId) async {
    _requireReady();
    if (blobId.isEmpty) return null;
    try {
      final doc = await _chat(chatId).collection('blobs').doc(blobId).get();
      final data = doc.data();
      final payload = data?['payload'];
      return payload is String ? payload : null;
    } on FirebaseException catch (e) {
      throw CloudException(describeStoreError(e.code));
    }
  }

  /// Records that this account has seen everything in a conversation.
  ///
  /// Failures are swallowed on purpose. A read receipt is the least important
  /// thing on the screen, and an error banner because one did not save would
  /// be worse than the receipt being a minute stale.
  Future<void> markRead(String chatId) async {
    final id = uid;
    if (!_ready || id == null) return;
    try {
      await _chat(chatId).set({
        'readAt': {id: DateTime.now().millisecondsSinceEpoch},
      }, SetOptions(merge: true));
    } catch (_) {
      // Deliberately ignored — see above.
    }
  }

  /// Says this account is typing, at most once every [typingWriteEvery].
  ///
  /// The throttle is the whole point. Every call here is a document write and
  /// the free allowance is twenty thousand a day; writing on each keystroke
  /// would spend an afternoon's worth in one conversation. The flag is never
  /// cleared — it expires by age on the reading side, which costs nothing and
  /// cannot be left stuck on by a phone that lost signal mid-word.
  Future<void> setTyping(String chatId) async {
    final id = uid;
    if (!_ready || id == null) return;

    final now = DateTime.now();
    final last = _lastTypingWrite[chatId];
    if (last != null && now.difference(last) < typingWriteEvery) return;
    _lastTypingWrite[chatId] = now;

    try {
      await _chat(chatId).set({
        'typingAt': {id: now.millisecondsSinceEpoch},
      }, SetOptions(merge: true));
    } catch (_) {
      // Same reasoning as markRead.
    }
  }

  // ------------------------------------------------------------- plumbing

  void _requireReady() {
    if (!_ready) {
      throw const CloudException(
        'Firebase has not started, so the cloud is unavailable. '
        'Everything stored on this device still works.',
      );
    }
  }

  /// Runs one cloud operation with the busy flag, and turns Firebase's own
  /// exceptions into messages a student can act on.
  Future<void> _run(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw CloudException(describeAuthError(e.code));
    } on FirebaseException catch (e) {
      throw CloudException(describeStoreError(e.code));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}

/// A cloud failure with a message already written for the screen.
class CloudException implements Exception {
  const CloudException(this.message);

  final String message;

  @override
  String toString() => message;
}
