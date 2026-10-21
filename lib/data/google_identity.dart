// The only file in NoteNest that imports `google_sign_in`.
//
// It is kept on its own for two reasons. The small one is that version 7 of
// that package was a rewrite — `GoogleSignIn()` became `GoogleSignIn.instance`,
// `signIn()` became `authenticate()`, and access tokens moved out of
// `authentication` into an authorization client of their own — so the next such
// change should touch one file rather than four.
//
// The large one is that this is the only part of signing in that can fail for
// reasons nobody at the phone can do anything about: a fingerprint that was
// never registered, a consent screen still in testing, Play services out of
// date. CloudService turns what comes back here into a Firebase session; it
// should not also have to know what Credential Manager does on a Tuesday.
//
// Nothing here touches the notebook. A student who never taps the Google
// button never loads this code.

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../l10n/strings.dart';

/// The sheet closed without an account being chosen.
///
/// Worth its own type because it is not an error. Nobody wants a red line
/// across the login screen for having changed their mind — but see
/// [GoogleIdentityError.looksLikeSetup] for why this one cannot be swallowed
/// in silence either.
class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();

  @override
  String toString() => tr('Google sign-in was closed.');
}

/// A Google sign-in failure with a message already written for the screen.
class GoogleIdentityError implements Exception {
  const GoogleIdentityError(this.message, {this.looksLikeSetup = false});

  final String message;

  /// True when the most likely cause is this project's configuration rather
  /// than anything the student did.
  ///
  /// This exists because of a trap in the Android implementation that cost a
  /// long evening to find and is documented in flutter/flutter#171761: the
  /// `canceled` code does not only mean the person cancelled. Credential
  /// Manager raises the same cancellation for a signing fingerprint that is
  /// not registered in Firebase and for a wrong server client id. The
  /// maintainer's own words are that the plugin returns `canceled` whenever it
  /// receives `GetCredentialCancellationException`, and that several reports of
  /// it turned out to be setup problems.
  ///
  /// So a cancel cannot be treated as certainly harmless, and it cannot be
  /// treated as certainly broken. The screen says both, briefly.
  final bool looksLikeSetup;

  @override
  String toString() => message;
}

/// What a completed Google sign-in hands back.
///
/// Only the token. Name and address are deliberately **not** read from the
/// Google account object: once Firebase has accepted this token it has a user
/// record with both on it, and reading them from there means one source of
/// truth instead of two that can disagree — and one less version-7 API this
/// file has to be right about.
class GoogleCredential {
  const GoogleCredential(this.idToken);

  final String idToken;
}

/// Signs in to Google, and later asks for Drive.
class GoogleAccounts {
  GoogleAccounts._();

  static final GoogleAccounts instance = GoogleAccounts._();

  /// The **web** OAuth client id, filled in only if sign-in refuses without it.
  ///
  /// Normally this stays empty. On Android the plugin reads the web client out
  /// of `android/app/google-services.json`, which Firebase writes into that
  /// file as the entry with `"client_type": 3` once the Google sign-in provider
  /// is switched on. When that entry is present, naming the id here as well
  /// would be the same value written twice, and the copy in this file is the
  /// one that would go stale.
  ///
  /// Set it only on the specific error `serverClientId must be provided on
  /// Android`, which means that entry is missing from `google-services.json`.
  /// The right fix is to re-download the file; this is the escape hatch if that
  /// cannot be done. The value is a public identifier, not a secret — it is
  /// already in the APK either way.
  static const String serverClientId = '';

  /// Per-file Drive access: the app may touch only what it created itself.
  ///
  /// Not `drive`, and not `drive.appdata`. `drive` is the whole of somebody's
  /// Drive and is a restricted scope that needs a security assessment to ship;
  /// `drive.appdata` hides the files in a folder the student cannot open, which
  /// defeats the point of putting notes in their own Drive. `drive.file` is
  /// non-sensitive, needs only basic verification, and the student can see and
  /// keep every file the app saves.
  ///
  /// Used by `drive_service.dart`. Named here so the scope lives next to the
  /// sign-in.
  static const List<String> driveScopes = <String>[
    'https://www.googleapis.com/auth/drive.file',
  ];

  Future<void>? _starting;

  /// False in a browser.
  ///
  /// `authenticate()` is not implemented on web — the web platform wants a
  /// rendered Google button instead, which is a different screen, not a
  /// different call. Rather than discovering that as a crash, the button is
  /// hidden and the email form stays.
  bool get isSupported => !kIsWeb;

  /// Runs `initialize()` once, which version 7 requires before anything else.
  ///
  /// The future is kept rather than a flag being raised afterwards, so two taps
  /// in quick succession wait on the same initialisation instead of starting a
  /// second one. A failure clears it, because a cached broken future would mean
  /// the button never worked again until the app was restarted.
  Future<void> _ensureInitialised() async {
    final pending = _starting;
    if (pending != null) {
      await pending;
      return;
    }

    final started = GoogleSignIn.instance.initialize(
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
    _starting = started;
    try {
      await started;
    } catch (_) {
      _starting = null;
      rethrow;
    }
  }

  /// Opens the Google account sheet and returns a token Firebase will accept.
  ///
  /// Throws [GoogleSignInCancelled] if the sheet closed with no choice, and
  /// [GoogleIdentityError] for everything else.
  Future<GoogleCredential> signIn() async {
    if (!isSupported) {
      throw GoogleIdentityError(
        tr('Signing in with Google needs the NoteNest app. In a browser, use '
        'your email and password.'),
      );
    }

    try {
      await _ensureInitialised();
    } catch (e) {
      throw GoogleIdentityError(
        'Google sign-in could not start on this device.\n\n$e',
        looksLikeSetup: true,
      );
    }

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate(
        // A hint, not a request: it tells the sheet what the app is going to
        // want so the student is asked once. Drive is asked for separately,
        // later, and only by someone who turns that on.
        scopeHint: const <String>['email', 'profile'],
      );
    } on GoogleSignInException catch (e) {
      // `e.code.name` rather than a comparison against the enum, because
      // `GoogleSignInExceptionCode` is not exported from the package in
      // version 7 (flutter/flutter#171462) — the enum value cannot be named
      // here at all. The string is what the package's own issue thread
      // recommends, and it is checked against a name that is part of the
      // package's public behaviour even though its type is not.
      final code = e.code.name;
      if (code == 'canceled') throw const GoogleSignInCancelled();
      throw GoogleIdentityError(
        _describe(code, e.description),
        looksLikeSetup: code == 'clientConfigurationError' ||
            code == 'providerConfigurationError',
      );
    }

    final token = account.authentication.idToken;
    if (token == null || token.isEmpty) {
      throw GoogleIdentityError(
        tr('Google signed in but sent no identity token, so there is nothing to '
        'prove who you are with. This almost always means the web OAuth '
        'client is missing from google-services.json — re-download it from '
        'Firebase after switching the Google provider on.'),
        looksLikeSetup: true,
      );
    }
    return GoogleCredential(token);
  }

  /// Forgets the chosen Google account, so the sheet asks again next time.
  ///
  /// Called from sign out. Without it, signing out of NoteNest and tapping the
  /// Google button would put you straight back into the account you just left,
  /// which on a shared phone is not a convenience.
  ///
  /// Never throws: a sign out that fails because Google is unreachable must
  /// still sign the student out of NoteNest.
  Future<void> signOut() async {
    if (!isSupported) return;
    try {
      await _ensureInitialised();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nothing to tell anyone. The session that matters is Firebase's, and
      // the caller has already ended it.
    }
  }

  /// Asks for Drive, reusing permission already granted.
  ///
  /// [authorizationForScopes] returns an existing grant without showing
  /// anything; only when that is null is the student asked. Returns null if
  /// they decline — which is a real answer, not an error, and the caller is
  /// expected to carry on without Drive.
  ///
  /// Called by [DriveService] for backups and class files.
  Future<String?> authorizeDrive({bool promptIfNeeded = true}) async {
    if (!isSupported) return null;
    await _ensureInitialised();

    final client = GoogleSignIn.instance.authorizationClient;
    var grant = await client.authorizationForScopes(driveScopes);
    if (grant == null && promptIfNeeded) {
      try {
        grant = await client.authorizeScopes(driveScopes);
      } on GoogleSignInException {
        return null;
      }
    }
    return grant?.accessToken;
  }

  static String _describe(String code, String? description) {
    switch (code) {
      case 'clientConfigurationError':
        return tr('Google refused this build of the app. The signing '
            "fingerprint for this build is probably not registered in the "
            'Firebase project yet.');
      case 'providerConfigurationError':
        return tr('Google sign-in is not finished being set up for this project. '
            'Check that the Google provider is switched on in Firebase '
            'Authentication.');
      case 'uiUnavailable':
        return tr('Google could not show the sign-in sheet. Make sure Google '
            'Play services is installed and up to date, then try again.');
      case 'userMismatch':
        return tr('That is a different Google account from the one expected. '
            'Try again and pick the first one.');
      case 'interrupted':
        return tr('Google sign-in was interrupted. Try again.');
      default:
        final extra = (description == null || description.isEmpty)
            ? ''
            : '\n\n$description';
        return trp('Google sign-in did not work.{0}', [extra]);
    }
  }
}
