import 'package:flutter/material.dart';

import '../../data/auth_repository.dart';
import '../../data/cloud_service.dart';
import '../../data/google_identity.dart';
import '../../data/note_repository.dart';
// For CloudRoleData.key, which is an extension on CloudRole rather than a
// member of it — so it is invisible without this import even though the
// CloudProfile holding the role arrives through CloudService.
import '../../models/cloud_profile.dart';
import '../../theme/nest_theme.dart';

/// The Google button, and the one piece of work behind it.
///
/// Both auth screens show it, and both do the same thing with it, so the work
/// lives here rather than twice. Register and sign in are genuinely the same
/// action for Google: Google already knows whether this person has an account
/// with it, and whether *NoteNest* has seen them before is answered by whether
/// their profile document exists — not by which button they pressed.

/// How [continueWithGoogle] ended.
enum GoogleOutcome {
  /// Signed in. The device account is ready and the notebook is loaded.
  signedIn,

  /// The sheet closed without a choice. Say something quiet, or nothing.
  cancelled,

  /// It failed, and [GoogleResult.message] says why in words for the student.
  failed,
}

class GoogleResult {
  const GoogleResult(this.outcome, [this.message]);

  final GoogleOutcome outcome;
  final String? message;
}

/// Signs in with Google, joins it to this device's account, and loads the
/// notebook. Does not navigate — the caller owns that.
///
/// The order is the point. The cloud goes first because it is the half that can
/// refuse, and nothing on the phone is touched until Firebase has accepted the
/// token Google issued. If it refuses, the device is exactly as it was.
Future<GoogleResult> continueWithGoogle() async {
  final cloud = CloudService.instance;

  if (!GoogleAccounts.instance.isSupported) {
    return const GoogleResult(
      GoogleOutcome.failed,
      'Signing in with Google needs the NoteNest app. In a browser, use your '
      'email and password.',
    );
  }
  if (!await cloud.waitUntilReady()) {
    return GoogleResult(
      GoogleOutcome.failed,
      cloud.startupError ??
          'The cloud is not available right now, so Google sign-in cannot be '
              'checked. Everything stored on this device still works.',
    );
  }

  try {
    await cloud.signInWithGoogle();
  } on GoogleSignInCancelled {
    return const GoogleResult(GoogleOutcome.cancelled);
  } on CloudException catch (e) {
    return GoogleResult(GoogleOutcome.failed, e.message);
  }

  final profile = cloud.profile;
  if (profile == null) {
    return const GoogleResult(
      GoogleOutcome.failed,
      'Signed in with Google, but your NoteNest profile could not be read. '
      'Check your connection and try again.',
    );
  }

  // The address comes from the profile, which was built from the Firebase user
  // — never from a text field. That is the whole safety argument for
  // signInWithVerifiedEmail, which checks no password.
  final failed = await AuthRepository.instance.signInWithVerifiedEmail(
    email: profile.email,
    name: profile.name,
    institution: profile.institution.isEmpty ? null : profile.institution,
  );
  if (failed != null) {
    return GoogleResult(GoogleOutcome.failed, failed.message);
  }

  await NoteRepository.instance.saveRole(profile.role.key);
  await NoteRepository.instance.load();
  return const GoogleResult(GoogleOutcome.signedIn);
}

/// What to say when the sheet closed with nothing chosen.
///
/// Not silence, and not an error either, because nobody — including this code —
/// can tell the two apart. Android's Credential Manager raises the same
/// cancellation when the person taps away and when the signing fingerprint of
/// this build is not registered in the Firebase project; the plugin's own
/// maintainer says so in flutter/flutter#171761. A student who changed their
/// mind can ignore this line. A build with the wrong fingerprint would
/// otherwise look like a button that does nothing at all, for ever.
const String googleCancelledNotice =
    'Google sign-in closed. If you did not close it yourself, this build of '
    'the app may not be registered in Firebase yet.';

/// "Continue with Google", drawn as a sunken tile rather than a filled button.
///
/// Deliberately quieter than Sign in. The password form is the main way in and
/// should still look like it; this is the alternative beside it, not a rival to
/// it.
///
/// No Google logo. Google's branding guidelines want their own supplied asset,
/// at their own sizes, and an approximation of someone else's mark is worse
/// than none — so the button says what it does in words. Before this ships to
/// Play, drop the official asset in and put it on the left.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.busy = false,
  });

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    // Hidden rather than shown-and-broken in a browser, where authenticate()
    // has no implementation.
    if (!GoogleAccounts.instance.isSupported) return const SizedBox.shrink();

    return Column(
      children: [
        const Row(
          children: [
            Expanded(child: Divider(color: NestColor.rule, height: 1)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('OR', style: nestEyebrow),
            ),
            Expanded(child: Divider(color: NestColor.rule, height: 1)),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: Material(
            color: NestColor.paper,
            borderRadius: BorderRadius.circular(NestRadius.tile),
            child: InkWell(
              borderRadius: BorderRadius.circular(NestRadius.tile),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Center(
                  child: Text(
                    busy ? 'Asking Google...' : 'Continue with Google',
                    style: TextStyle(
                      fontFamily: NestFont.display,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: onPressed == null
                          ? NestColor.inkFaint
                          : NestColor.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
