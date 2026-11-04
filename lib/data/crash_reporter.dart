import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Sends crashes to Firebase Crashlytics, so a failure on somebody else's phone
/// is something the owner can see and not only something the student suffers.
///
/// Safe to call at any time: before Firebase has started, on the web, and in a
/// debug build it quietly does nothing. A report is the stack trace and the
/// device model and Android version, never a note, a name or an email.
class CrashReporter {
  CrashReporter._();

  static bool _on = false;

  /// Called once Firebase has started. Off in debug builds so development
  /// crashes do not pollute the real list, and off on the web, which
  /// Crashlytics does not support.
  static Future<void> enable() async {
    if (kIsWeb || kDebugMode) return;
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      _on = true;
    } catch (_) {
      // Reporting must never be the thing that breaks the app.
    }
  }

  static void flutterError(FlutterErrorDetails details) {
    if (!_on) return;
    try {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    } catch (_) {}
  }

  static void error(Object error, StackTrace stack) {
    if (!_on) return;
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } catch (_) {}
  }
}
