import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/user_account.dart';
import 'app_database.dart';

/// Why a sign-in or sign-up attempt failed.
enum AuthError {
  emailTaken,
  emailNotFound,
  wrongPassword,
  weakPassword,
  invalidEmail,
  emptyName,
  googleAccount,
}

extension AuthErrorMessage on AuthError {
  String get message {
    switch (this) {
      case AuthError.emailTaken:
        return 'An account already uses this email on this device';
      case AuthError.emailNotFound:
        return 'No account found for this email';
      case AuthError.wrongPassword:
        return 'That password does not match';
      case AuthError.weakPassword:
        return 'Password needs 6+ characters, a capital letter and a symbol';
      case AuthError.invalidEmail:
        return 'Enter a valid email address';
      case AuthError.emptyName:
        return 'Enter your name';
      case AuthError.googleAccount:
        return 'This account signs in with Google, so it has no password here';
    }
  }
}

/// Owns accounts and the current session.
///
/// Passwords are salted and hashed with SHA-256 before they touch the database.
/// This is enough to keep plain passwords out of the file, but it is not what a
/// production service would use — those use a deliberately slow hash such as
/// bcrypt or Argon2. When cloud accounts arrive, the server takes this over.
class AuthRepository extends ChangeNotifier {
  AuthRepository._();

  static final AuthRepository instance = AuthRepository._();

  static const _kCurrentUser = 'current_user_id';

  final _db = AppDatabase.instance;

  UserAccount? _current;

  /// True when the signed-in row has no password of its own — see [_googleOnly].
  bool _currentIsGoogle = false;

  UserAccount? get currentUser => _current;

  bool get isSignedIn => _current != null;

  /// True when this account proves itself with Google instead of a password.
  ///
  /// Three screens need to know. "Change password" has nothing to change,
  /// "Delete account" cannot ask for a password that was never set, and the
  /// delete dialog must say that Google will be asked again instead. Before
  /// this existed those screens all assumed a password, and for a Google
  /// account each of them failed with a message about the password being
  /// wrong — which is a lie about an account that has none.
  bool get currentUserUsesGoogle => _currentIsGoogle;

  int get requireUserId {
    final id = _current?.id;
    if (id == null) throw StateError('No signed-in user');
    return id;
  }

  // ------------------------------------------------------------- validation

  static bool isValidEmail(String email) =>
      RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(email.trim());

  /// The rules the requirement specification asks for.
  static bool isStrongPassword(String password) =>
      password.length >= 6 &&
      RegExp(r'[A-Z]').hasMatch(password) &&
      RegExp(r'[^A-Za-z0-9]').hasMatch(password);

  // --------------------------------------------------------------- hashing

  static String _newSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// How many times the password is run through HMAC-SHA256.
  ///
  /// The point of a password hash is to be slow. The first version of this
  /// file used a single round of SHA-256, which is the opposite: SHA-256 is
  /// built to be fast, and a graphics card tries billions of candidates a
  /// second against it. Anyone who walked off with the phone's database had
  /// the passwords shortly afterwards — and people reuse passwords, so that is
  /// their email account too, not just their notes.
  ///
  /// PBKDF2-HMAC-SHA256 is the standard answer that needs no new package: the
  /// `crypto` package already here provides HMAC, and NIST SP 800-132 defines
  /// the construction. A hundred and twenty thousand rounds turns one guess
  /// from free into something measurable, which is the whole game.
  static const int _pbkdf2Rounds = 120000;

  /// PBKDF2 with a 32-byte output — exactly one block, so no loop over blocks.
  static String _pbkdf2(String password, String salt, int rounds) {
    final hmac = Hmac(sha256, utf8.encode(password));
    // U1 = HMAC(password, salt || INT_32_BE(1))
    var block = hmac.convert([...utf8.encode(salt), 0, 0, 0, 1]).bytes;
    final out = List<int>.from(block);
    for (var i = 1; i < rounds; i++) {
      block = hmac.convert(block).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= block[j];
      }
    }
    return base64Url.encode(out);
  }

  /// The stored form, which names its own algorithm and cost.
  ///
  /// Writing the round count into the value is what makes it possible to raise
  /// it later without locking anybody out: an old row still says how it was
  /// made, so it can still be checked.
  static String _hash(String password, String salt) =>
      'pbkdf2\$$_pbkdf2Rounds\$${_pbkdf2(password, salt, _pbkdf2Rounds)}';

  /// The single round of SHA-256 this app shipped with, kept only so that
  /// accounts created before the change can still sign in — once.
  static String _legacyHash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt::$password')).toString();

  /// What stands in the password column for an account that signs in with
  /// Google.
  ///
  /// `password_hash` and `password_salt` are both NOT NULL, so a Google
  /// account still needs *something* there, and the choice of something matters
  /// more than it looks. Two things were rejected:
  ///
  ///   * A random password, hashed properly. It would work, and it would mean
  ///     every screen still believes the account has a password — including
  ///     "change password", which would then ask for a current one that does
  ///     not exist anywhere. A lie in the data becomes a bug in the UI.
  ///   * An empty string, or a column left to default. Then any hash function
  ///     returning an empty result would be a valid password, which is the
  ///     kind of thing that is only ever discovered the hard way.
  ///
  /// So the column holds a value that is deliberately *not* a hash and that no
  /// hash function here can ever produce: the prefix alone, with nothing after
  /// it. [_verify] refuses it outright before any comparison, so there is no
  /// password — not a hard one, not an empty one, none — that opens this row.
  /// It also doubles as the flag that tells the screens what kind of account
  /// this is, which is why it is stored rather than inferred from Firebase:
  /// inferring it needs a connection, and the question comes up offline.
  static const String _googleOnly = 'google\$';

  static bool _isGoogleOnly(String stored) => stored == _googleOnly;

  /// True when [password] is the one behind [stored].
  ///
  /// Returns `legacy: true` through [wasLegacy] so the caller can quietly
  /// rewrite the row in the new form. Nobody is asked to reset anything.
  static bool _verify(String password, String salt, String stored) {
    // First, and before any hashing: a Google row has no password, so nothing
    // typed can be the right one. Falling through to the legacy branch would
    // also return false today — the marker is not 64 hex characters — but that
    // would be an accident of lengths rather than a decision, and the next
    // person to change the legacy format would not know they were relying on
    // it.
    if (_isGoogleOnly(stored)) return false;
    if (!stored.startsWith('pbkdf2\$')) {
      return _constantTimeEquals(_legacyHash(password, salt), stored);
    }
    final parts = stored.split('\$');
    if (parts.length != 3) return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null || rounds < 1) return false;
    return _constantTimeEquals(_pbkdf2(password, salt, rounds), parts[2]);
  }

  static bool _isLegacy(String stored) => !stored.startsWith('pbkdf2\$');

  /// Compares without returning early on the first wrong character.
  ///
  /// A plain `==` leaks how much of a guess was right through how long the
  /// comparison took. That is a thin channel on a phone and a real one on a
  /// server; it costs nothing to close either way.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  // --------------------------------------------------------------- session

  /// Restores the previous session, if any. Called once at startup.
  Future<void> restoreSession() async {
    final rows = await _db.db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [_kCurrentUser],
    );
    if (rows.isEmpty) return;

    final id = int.tryParse(rows.first['value'] as String? ?? '');
    if (id == null) return;

    final users =
        await _db.db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (users.isEmpty) {
      await _clearSession();
      return;
    }
    _current = UserAccount.fromMap(users.first);
    // Read from the row rather than remembered from the last sign in, because
    // this is the path a restarted app takes and there was no last sign in.
    _currentIsGoogle =
        _isGoogleOnly(users.first['password_hash'] as String? ?? '');
  }

  Future<void> _saveSession(int userId) async {
    await _db.db.insert(
      'app_settings',
      {'key': _kCurrentUser, 'value': '$userId'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _clearSession() async {
    await _db.db
        .delete('app_settings', where: 'key = ?', whereArgs: [_kCurrentUser]);
  }

  // ---------------------------------------------------------------- actions

  Future<AuthError?> register({
    required String name,
    required String email,
    required String password,
    String? institution,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim();

    if (cleanName.isEmpty) return AuthError.emptyName;
    if (!isValidEmail(cleanEmail)) return AuthError.invalidEmail;
    if (!isStrongPassword(password)) return AuthError.weakPassword;

    final existing = await _db.db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: [cleanEmail.toLowerCase()],
      limit: 1,
    );
    if (existing.isNotEmpty) return AuthError.emailTaken;

    final salt = _newSalt();
    final id = await _db.db.insert('users', {
      'name': cleanName,
      'email': cleanEmail,
      'institution': institution?.trim(),
      'password_hash': _hash(password, salt),
      'password_salt': salt,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    final rows =
        await _db.db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    _current = UserAccount.fromMap(rows.first);
    _currentIsGoogle = false;
    await _saveSession(id);
    notifyListeners();
    return null;
  }

  /// Builds the device account for somebody who already has a cloud account.
  ///
  /// Used when a student signs in on a new device, or after a browser has
  /// cleared its storage: the cloud knows who they are, but this device has
  /// never seen them. Rather than telling them their account does not exist —
  /// which is how this used to fail, and is simply untrue — the device account
  /// is rebuilt from what the cloud returned.
  ///
  /// The strength rule is deliberately not applied. It guards the *choice* of
  /// a new password; this password already belongs to a real account, and
  /// refusing it here would lock somebody out of their own notes over a rule
  /// their password predates.
  Future<AuthError?> adoptCloudAccount({
    required String name,
    required String email,
    required String password,
    String? institution,
  }) async {
    final cleanEmail = email.trim();
    if (!isValidEmail(cleanEmail)) return AuthError.invalidEmail;

    final existing = await _db.db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: [cleanEmail.toLowerCase()],
      limit: 1,
    );
    if (existing.isNotEmpty) return AuthError.emailTaken;

    final salt = _newSalt();
    final id = await _db.db.insert('users', {
      // A cloud profile with no name still has an address, and a blank name
      // would make every screen say "?" until they fixed it by hand.
      'name': name.trim().isEmpty ? cleanEmail.split('@').first : name.trim(),
      'email': cleanEmail,
      'institution': institution?.trim(),
      'password_hash': _hash(password, salt),
      'password_salt': salt,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    final rows =
        await _db.db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    _current = UserAccount.fromMap(rows.first);
    _currentIsGoogle = false;
    await _saveSession(id);
    notifyListeners();
    return null;
  }

  /// Attaches the session to the device row for [email], creating it if this
  /// device has never seen the account.
  ///
  /// **No password is checked here, and that is the whole point.** It is called
  /// with an address that Google issued a signed token for and Firebase then
  /// accepted — a stronger proof than a hash comparison against this phone's
  /// own database, because it is a proof this phone could not have forged.
  ///
  /// What makes that safe is not a check inside this method but the one place
  /// it may be called from: immediately after
  /// [CloudService.signInWithGoogle] has returned, with the address off the
  /// resulting Firebase user and nothing else. Called with an address from
  /// anywhere else — a text field, a stored string, a share — it is a way into
  /// any account on the device. The same reasoning, and the same danger, as
  /// [rekeyPassword].
  ///
  /// Two cases, and the difference matters:
  ///
  ///   * **The row exists.** Its password column is left exactly as it is. A
  ///     student who registered with a password and later used the Google
  ///     button still has that password, and overwriting it with the Google
  ///     marker would take it away from them without asking.
  ///   * **No row.** One is created with the marker, so it has no password
  ///     rather than a password nobody knows.
  Future<AuthError?> signInWithVerifiedEmail({
    required String email,
    required String name,
    String? institution,
  }) async {
    final cleanEmail = email.trim();
    if (!isValidEmail(cleanEmail)) return AuthError.invalidEmail;

    final rows = await _db.db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: [cleanEmail.toLowerCase()],
      limit: 1,
    );

    final int id;
    if (rows.isEmpty) {
      id = await _db.db.insert('users', {
        // A Google account with no name set still has an address, and a blank
        // name would show as "?" on every screen until they fixed it by hand.
        'name':
            name.trim().isEmpty ? cleanEmail.split('@').first : name.trim(),
        'email': cleanEmail,
        'institution': institution?.trim(),
        'password_hash': _googleOnly,
        'password_salt': _newSalt(),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      id = rows.first['id'] as int;
      // Only a name that is missing is filled in. Whatever they typed here
      // themselves wins over whatever Google has, because they typed it here.
      final existingName = (rows.first['name'] as String? ?? '').trim();
      if (existingName.isEmpty && name.trim().isNotEmpty) {
        await _db.db.update(
          'users',
          {'name': name.trim()},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }

    final fresh =
        await _db.db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    _current = UserAccount.fromMap(fresh.first);
    _currentIsGoogle =
        _isGoogleOnly(fresh.first['password_hash'] as String? ?? '');
    await _saveSession(id);
    notifyListeners();
    return null;
  }

  Future<AuthError?> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    if (!isValidEmail(cleanEmail)) return AuthError.invalidEmail;

    final rows = await _db.db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: [cleanEmail.toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return AuthError.emailNotFound;

    final row = rows.first;
    final salt = row['password_salt'] as String;
    final stored = row['password_hash'] as String;

    // Answered before the password is weighed, and answered differently.
    //
    // "That password does not match" would be true but useless: there is no
    // password that would have matched, and the student would keep trying
    // longer ones. It also matters to the caller — the login screen retries a
    // wrongPassword against the cloud, and a cloud retry with a password for a
    // Google account is a round trip that cannot succeed.
    if (_isGoogleOnly(stored)) return AuthError.googleAccount;

    if (!_verify(password, salt, stored)) {
      return AuthError.wrongPassword;
    }

    // The one moment the plain password is in hand and already proven: rewrite
    // an old single-round row in the new form. Silent, and it happens once.
    if (_isLegacy(stored)) {
      final freshSalt = _newSalt();
      await _db.db.update(
        'users',
        {
          'password_hash': _hash(password, freshSalt),
          'password_salt': freshSalt,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    _current = UserAccount.fromMap(row);
    _currentIsGoogle = false;
    await _saveSession(_current!.id!);
    notifyListeners();
    return null;
  }

  /// Sets the device password for an existing account to [password].
  ///
  /// **Only to be called after the cloud has already accepted that password.**
  /// There is no current-password check here — that is the point: a student who
  /// has just reset their password by email does not know the old one, and
  /// cannot be asked for it. What makes this safe is not a check in this
  /// method but where it is called from: Firebase has already verified the
  /// person against the one copy of the truth that lives off this device.
  Future<AuthError?> rekeyPassword({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    final rows = await _db.db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: [cleanEmail.toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return AuthError.emailNotFound;

    final salt = _newSalt();
    final id = rows.first['id'] as int;
    await _db.db.update(
      'users',
      {'password_hash': _hash(password, salt), 'password_salt': salt},
      where: 'id = ?',
      whereArgs: [id],
    );

    final fresh =
        await _db.db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    _current = UserAccount.fromMap(fresh.first);
    // They have a password again — the one they just set.
    _currentIsGoogle = false;
    await _saveSession(id);
    notifyListeners();
    return null;
  }

  /// Run after a sign out, so whatever is holding account-scoped state can
  /// drop it.
  ///
  /// Sign out used to clear only the session here, and the previous account's
  /// notes, subjects and exams were emptied by the profile screen calling
  /// NoteRepository.clear() straight afterwards. That worked for exactly as
  /// long as every sign out went through that one screen: the invariant lived
  /// in a caller rather than in the thing being signed out of. A hook puts it
  /// back where it belongs — a new sign-out path cannot forget.
  final List<void Function()> _signOutHooks = [];

  void addSignOutHook(void Function() hook) => _signOutHooks.add(hook);

  /// Removes this account and everything it owns from the device.
  ///
  /// Google Play requires an app that lets a person create an account to let
  /// them delete it from inside the app. This is that, for the device half.
  /// The cloud half is [CloudService.deleteCloudAccount], and the screen does
  /// the cloud first: if the cloud refuses, nothing here has happened yet.
  ///
  /// The password is asked for again on purpose. It is the last check before
  /// an action with no undo, and it is the only thing standing between a
  /// borrowed unlocked phone and somebody's whole term of notes.
  ///
  /// Everything the account owns — subjects, notes, exams, settings and
  /// attachment rows — goes with the row through ON DELETE CASCADE, which the
  /// database has on because `PRAGMA foreign_keys = ON` is set when it opens.
  /// Files on disk are not rows and do not cascade: the caller clears those
  /// first.
  Future<AuthError?> deleteAccount({required String password}) async {
    final user = _current;
    if (user?.id == null) return AuthError.emailNotFound;

    final rows = await _db.db
        .query('users', where: 'id = ?', whereArgs: [user!.id], limit: 1);
    if (rows.isEmpty) return AuthError.emailNotFound;

    final row = rows.first;
    // A Google row would fail _verify below and report a wrong password, which
    // would leave the student with no way to delete their own account at all —
    // the one thing Google Play requires this screen to be able to do.
    if (_isGoogleOnly(row['password_hash'] as String)) {
      return AuthError.googleAccount;
    }
    if (!_verify(password, row['password_salt'] as String,
        row['password_hash'] as String)) {
      return AuthError.wrongPassword;
    }

    return _removeCurrentAccount();
  }

  /// Deletes the account without a password, for one that has none.
  ///
  /// The guard this replaces is not weaker, only elsewhere: the caller has just
  /// had Firebase re-check the Google account against Google itself, seconds
  /// ago, by making the student pick their account again. Firebase refuses
  /// `user.delete()` on a stale sign-in for exactly this reason, so by the time
  /// control reaches here the proof has already been demanded and given.
  ///
  /// Refuses an account that *does* have a password, so that this can never
  /// become a quieter route past one.
  Future<AuthError?> deleteAccountVerified() async {
    final user = _current;
    if (user?.id == null) return AuthError.emailNotFound;

    final rows = await _db.db
        .query('users', where: 'id = ?', whereArgs: [user!.id], limit: 1);
    if (rows.isEmpty) return AuthError.emailNotFound;

    if (!_isGoogleOnly(rows.first['password_hash'] as String)) {
      return AuthError.wrongPassword;
    }

    return _removeCurrentAccount();
  }

  Future<AuthError?> _removeCurrentAccount() async {
    final id = _current?.id;
    if (id == null) return AuthError.emailNotFound;

    await _db.db.delete('users', where: 'id = ?', whereArgs: [id]);

    await _clearSession();
    _current = null;
    _currentIsGoogle = false;
    for (final hook in _signOutHooks) {
      hook();
    }
    notifyListeners();
    return null;
  }

  /// The stored file names of everything this account has attached.
  ///
  /// Read before the account row goes, because afterwards the rows that name
  /// the files are gone and the files would sit on disk for ever.
  Future<List<String>> attachmentFileNamesForCurrentUser() async {
    final id = _current?.id;
    if (id == null) return const [];
    final rows = await _db.db.rawQuery(
      'SELECT stored_name FROM attachments '
      'WHERE note_id IN (SELECT id FROM notes WHERE user_id = ?)',
      [id],
    );
    return [
      for (final r in rows)
        if (r['stored_name'] is String) r['stored_name'] as String,
    ];
  }

  Future<void> signOut() async {
    await _clearSession();
    _current = null;
    _currentIsGoogle = false;
    for (final hook in _signOutHooks) {
      hook();
    }
    notifyListeners();
  }

  Future<void> updateProfile({String? name, String? institution}) async {
    final user = _current;
    if (user?.id == null) return;

    await _db.db.update(
      'users',
      {
        if (name != null) 'name': name.trim(),
        if (institution != null) 'institution': institution.trim(),
      },
      where: 'id = ?',
      whereArgs: [user!.id],
    );

    _current = user.copyWith(name: name?.trim(), institution: institution?.trim());
    notifyListeners();
  }

  /// Changes the password after checking the current one.
  Future<AuthError?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _current;
    if (user?.id == null) return AuthError.emailNotFound;
    if (!isStrongPassword(newPassword)) return AuthError.weakPassword;

    final rows = await _db.db
        .query('users', where: 'id = ?', whereArgs: [user!.id], limit: 1);
    final row = rows.first;
    // Nothing to change, and nothing to ask for. The settings row is hidden
    // for these accounts, so this is the belt behind the braces.
    if (_isGoogleOnly(row['password_hash'] as String)) {
      return AuthError.googleAccount;
    }
    // Through _verify, so somebody whose row is still in the old single-round
    // form can change their password rather than being told it is wrong.
    if (!_verify(currentPassword, row['password_salt'] as String,
        row['password_hash'] as String)) {
      return AuthError.wrongPassword;
    }

    final salt = _newSalt();
    await _db.db.update(
      'users',
      {'password_hash': _hash(newPassword, salt), 'password_salt': salt},
      where: 'id = ?',
      whereArgs: [user.id],
    );
    return null;
  }
}
