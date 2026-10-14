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

  UserAccount? get currentUser => _current;

  bool get isSignedIn => _current != null;

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

  static String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt::$password')).toString();

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
    if (_hash(password, salt) != row['password_hash']) {
      return AuthError.wrongPassword;
    }

    _current = UserAccount.fromMap(row);
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
    await _saveSession(id);
    notifyListeners();
    return null;
  }

  Future<void> signOut() async {
    await _clearSession();
    _current = null;
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
    if (_hash(currentPassword, row['password_salt'] as String) !=
        row['password_hash']) {
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
