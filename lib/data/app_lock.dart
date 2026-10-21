import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqflite/sqflite.dart';

import '../l10n/strings.dart';
import 'app_database.dart';

/// A four-digit PIN as stored: a random salt and the SHA-256 of salt and PIN.
/// Never the PIN itself.
String hashPin(String salt, String pin) =>
    sha256.convert(utf8.encode('$salt:$pin')).toString();

/// The app lock: a PIN, optionally a fingerprint, asked for when the app is
/// opened and again when it comes back after a while away.
///
/// Be plain about what this is. It keeps a person who picks up an unlocked
/// phone out of the notebook, which is what students want it for. It is not
/// encryption: someone with the phone's files could still read the database,
/// and the README of any app that says otherwise is wrong.
///
/// Device-wide, like the theme: one lock for the phone, not one per account.
class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  AppLock._();

  static final AppLock instance = AppLock._();

  static const _kPin = 'lock_pin';
  static const _kBio = 'lock_bio';

  /// How long the app can be away before it asks again. Long enough that
  /// switching to the camera or a file picker and back does not lock you out.
  static const grace = Duration(seconds: 60);

  static const pinLength = 4;
  static const maxTries = 5;
  static const penalty = Duration(seconds: 30);

  final _auth = LocalAuthentication();

  String? _salt;
  String? _hash;
  bool _biometric = false;
  bool _locked = false;
  DateTime? _pausedAt;

  /// True while the system fingerprint sheet is up: it sends the app to the
  /// background and back, which must not count as having been away.
  bool _prompting = false;

  int _failures = 0;
  DateTime? _blockedUntil;

  bool get enabled => _hash != null;
  bool get biometric => _biometric;
  bool get locked => enabled && _locked;

  /// Seconds left before another try is allowed, or 0.
  int get waitSeconds {
    final until = _blockedUntil;
    if (until == null) return 0;
    final left = until.difference(DateTime.now()).inSeconds + 1;
    return left > 0 ? left : 0;
  }

  Future<void> load() async {
    try {
      final rows = await AppDatabase.instance.db.query(
        'app_settings',
        where: 'key IN (?, ?)',
        whereArgs: [_kPin, _kBio],
      );
      for (final r in rows) {
        final v = r['value'] as String?;
        if (r['key'] == _kPin && v != null && v.contains(':')) {
          _salt = v.split(':').first;
          _hash = v.split(':').last;
        } else if (r['key'] == _kBio) {
          _biometric = v == '1';
        }
      }
    } catch (_) {
      // An unreadable table leaves the lock off rather than locking the person
      // out of their own notes.
    }
    // A lock that is on starts locked: this is a cold start.
    _locked = enabled;
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _put(String key, String? value) async {
    final db = AppDatabase.instance.db;
    if (value == null) {
      await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert(
        'app_settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Turns the lock on, or changes the PIN.
  Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final salt = base64Url.encode(List.generate(12, (_) => rnd.nextInt(256)));
    _salt = salt;
    _hash = hashPin(salt, pin);
    await _put(_kPin, '$salt:$_hash');
    _failures = 0;
    _blockedUntil = null;
    // Setting it from inside the app means the person is here, so it stays open
    // until they leave.
    _locked = false;
    notifyListeners();
  }

  Future<void> setBiometric(bool on) async {
    _biometric = on;
    await _put(_kBio, on ? '1' : '0');
    notifyListeners();
  }

  /// Turns the lock off.
  Future<void> disable() async {
    _salt = null;
    _hash = null;
    _biometric = false;
    _locked = false;
    _failures = 0;
    _blockedUntil = null;
    await _put(_kPin, null);
    await _put(_kBio, null);
    notifyListeners();
  }

  /// Whether [pin] is right. Five wrong answers in a row make the person wait
  /// thirty seconds, which is enough to make guessing four digits by hand
  /// pointless without ever locking them out for good.
  bool check(String pin) {
    if (!enabled || waitSeconds > 0) return false;
    if (hashPin(_salt!, pin) == _hash) {
      _failures = 0;
      return true;
    }
    _failures++;
    if (_failures >= maxTries) {
      _failures = 0;
      _blockedUntil = DateTime.now().add(penalty);
    }
    return false;
  }

  void unlock() {
    if (!_locked) return;
    _locked = false;
    _pausedAt = null;
    notifyListeners();
  }

  void lockNow() {
    if (!enabled) return;
    _locked = true;
    notifyListeners();
  }

  /// Whether this phone has a fingerprint or face enrolled that can be used.
  Future<bool> biometricsAvailable() async {
    try {
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Asks the system for a fingerprint. True if the person passed it.
  Future<bool> unlockWithBiometric() async {
    if (!enabled || !_biometric) return false;
    _prompting = true;
    try {
      final ok = await _auth.authenticate(
        localizedReason: tr('Unlock NoteNest'),
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (ok) unlock();
      return ok;
    } catch (_) {
      return false;
    } finally {
      _prompting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!enabled || _prompting) return;
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final at = _pausedAt;
      if (at != null && DateTime.now().difference(at) > grace) lockNow();
      _pausedAt = null;
    }
  }
}
