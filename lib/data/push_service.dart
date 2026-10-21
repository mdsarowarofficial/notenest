import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'cloud_service.dart';
import 'reminder_service.dart';

/// Registers this phone for push notifications, so a message, a class post or
/// a note sent to you reaches you when the app is closed.
///
/// The phone's address (its FCM token) is written to `pushTokens/{uid}`, which
/// only its owner can read or write. A Cloud Function (see `functions/`) reads
/// it when something addressed to this person is written to Firestore.
///
/// Everything here is best-effort: no cloud, no permission, no Play services,
/// or a project where the function is not deployed yet, and the app simply
/// carries on without push. Nothing in the app depends on it.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  /// How many phones one account keeps a token for. The rules cap the list at
  /// five, so the newest four are kept and the fifth is the one being added.
  static const maxTokens = 5;

  String? _uid;
  String? _token;
  StreamSubscription<String>? _refresh;

  /// Off until the Cloud Function in `functions/` is deployed (it needs the
  /// Firebase Blaze plan). With it off the app never asks for the notification
  /// permission or registers a token, so nobody is asked to allow something
  /// that cannot arrive yet. Set to true after following docs/PUSH_SETUP.md.
  static const enabled = false;

  bool get supported =>
      enabled && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Follows the cloud sign-in: registers when somebody signs in, and starts
  /// again if the account changes.
  void watch(CloudService cloud) {
    if (!supported) return;
    void check() {
      final uid = cloud.isSignedIn ? cloud.uid : null;
      if (uid != null && uid != _uid) {
        unawaited(_register(uid));
      }
    }

    cloud.addListener(check);
    check();
  }

  Future<void> _register(String uid) async {
    _uid = uid;
    try {
      await ReminderService.instance.ensureMessagesChannel();
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token == null) return;
      _token = token;
      await _save(uid, token);

      await _refresh?.cancel();
      _refresh = messaging.onTokenRefresh.listen((t) {
        _token = t;
        unawaited(_save(uid, t));
      });
    } catch (e) {
      // Left as it is, so this is tried once per sign-in and not on every
      // cloud update: with the rules not published yet, or no Play services,
      // trying again would fail the same way each time.
      debugPrint('Push notifications unavailable: $e');
    }
  }

  Future<void> _save(String uid, String token) async {
    final ref = FirebaseFirestore.instance.doc('pushTokens/$uid');
    final snap = await ref.get();
    final existing = [
      for (final t in (snap.data()?['tokens'] as List?) ?? const [])
        if (t is String && t != token) t,
    ];
    final keep = existing.length >= maxTokens
        ? existing.sublist(existing.length - (maxTokens - 1))
        : existing;
    await ref.set({
      'tokens': [...keep, token],
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Takes this phone off the account's list. Called before signing out of the
  /// cloud, while the sign-in can still be used to write.
  Future<void> detach() async {
    final uid = _uid;
    final token = _token;
    _uid = null;
    _token = null;
    await _refresh?.cancel();
    _refresh = null;
    if (!supported || uid == null || token == null) return;
    try {
      final ref = FirebaseFirestore.instance.doc('pushTokens/$uid');
      final snap = await ref.get();
      final left = [
        for (final t in (snap.data()?['tokens'] as List?) ?? const [])
          if (t is String && t != token) t,
      ];
      if (left.isEmpty) {
        await ref.delete();
      } else {
        await ref.set({
          'tokens': left,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('Could not unregister push: $e');
    }
  }
}
