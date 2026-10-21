import 'package:flutter/material.dart';

import '../../data/auth_repository.dart';
import '../../data/cloud_service.dart';
import '../../data/note_repository.dart';
import '../../models/cloud_profile.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_paper.dart';
import '../../widgets/pen_wordmark.dart';
import '../setup/setup_flow.dart';
import '../shell/home_shell.dart';
import 'google_sign_in_button.dart';
import 'register_page.dart';
import '../../l10n/strings.dart';

/// Sign in to an account stored on this device. Requirement 2.
///
/// The screen is drawn as the first page of the notebook: ruled paper, a red
/// margin, subject tabs at the edge, and the form on a card laid over it.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.initialEmail});

  /// Filled in when the account switcher sent somebody here for a particular
  /// account, so they only have to type the password.
  final String? initialEmail;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _password = TextEditingController();

  String? _error;

  /// Set when this device's account was rebuilt from the cloud, so the student
  /// is told rather than left wondering why their notes are not here.
  bool _restoredFromCloud = false;

  /// Set when the stored password was brought into line after a reset.
  bool _passwordCaughtUp = false;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Signs in against the cloud and brings this device into line with it.
  ///
  /// With [rekeyExisting] the account is already on this device and only its
  /// stored password is out of date — the case after a reset by email.
  /// Without it, the device has never seen the account and one is built from
  /// the cloud profile.
  ///
  /// Returns null when it worked. Any failure returns an error rather than a
  /// reason, because the caller already has a better one: what this device
  /// said first.
  Future<AuthError?> _signInFromCloud({bool rekeyExisting = false}) async {
    final cloud = CloudService.instance;
    if (!await cloud.waitUntilReady()) return AuthError.emailNotFound;

    try {
      await cloud.signIn(email: _email.text, password: _password.text);
    } on CloudException {
      return AuthError.emailNotFound;
    }

    final profile = cloud.profile;
    if (profile == null) return AuthError.emailNotFound;

    if (rekeyExisting) {
      final failed = await AuthRepository.instance.rekeyPassword(
        email: _email.text,
        password: _password.text,
      );
      if (failed != null) return failed;
      _passwordCaughtUp = true;
    } else {
      final failed = await AuthRepository.instance.adoptCloudAccount(
        name: profile.name,
        email: _email.text,
        password: _password.text,
        institution: profile.institution,
      );
      if (failed != null) return failed;
      _restoredFromCloud = true;
    }

    await NoteRepository.instance.saveRole(profile.role.key);
    return null;
  }

  /// "Forgot password" — the only route there is, and it goes through the
  /// cloud because the device password exists nowhere else.
  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _email.text);
    final cloudReady = CloudService.instance.isReady;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NestColor.card,
        title: Text(tr('Forgot your password')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cloudReady
                  ? tr('We will email you a link to set a new one. Sign in here '
                      'with the new password afterwards and this device will '
                      'catch up on its own.')
                  : tr('The cloud is not available right now, so no email can be '
                      'sent. Check your connection and try again.'),
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(labelText: tr('Your email')),
            ),
            const SizedBox(height: 14),
            Text(
              // Said out loud rather than discovered later. A password that
              // only ever existed on one device cannot be mailed back.
              'If you never connected a cloud account, there is nothing to '
              'send: that password was only ever stored on this device.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: !cloudReady
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(dialogContext);
                    try {
                      await CloudService.instance
                          .sendPasswordReset(controller.text);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            tr('If that address has a cloud account, a reset '
                            'link is on its way. Check spam as well.'),
                          ),
                          duration: const Duration(seconds: 6),
                        ),
                      );
                    } on CloudException catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(e.message)),
                      );
                    }
                  },
            child: Text(tr('Send the link')),
          ),
        ],
      ),
    );
  }

  /// The Google button. Everything it does is in [continueWithGoogle]; this is
  /// the screen's half — the busy flag, the message, and where to go next.
  Future<void> _continueWithGoogle() async {
    setState(() {
      _error = null;
      _busy = true;
    });

    final result = await continueWithGoogle();
    if (!mounted) return;

    switch (result.outcome) {
      case GoogleOutcome.cancelled:
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(googleCancelledNotice),
            duration: const Duration(seconds: 7),
          ),
        );
        return;
      case GoogleOutcome.failed:
        setState(() {
          _error = result.message;
          _busy = false;
        });
        return;
      case GoogleOutcome.signedIn:
        _openNotebook();
        return;
    }
  }

  /// Where both ways in end up.
  void _openNotebook() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => NoteRepository.instance.setupDone
            ? const HomeShell()
            : const SetupFlow(),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _busy = true;
    });

    var failure = await AuthRepository.instance.signIn(
      email: _email.text,
      password: _password.text,
    );

    // This device does not accept it — but the cloud might.
    //
    // Two different situations, both of which used to end in a message that
    // was simply untrue:
    //
    //   emailNotFound  a new browser, a cleared cache, a second machine. The
    //                  student has an account; this device has never seen it.
    //   wrongPassword  they reset their password by email. The new one is
    //                  right and the copy stored here is the stale one.
    //
    // In both cases the cloud is asked, and only if the cloud accepts the
    // password does anything change here. If it refuses, the original local
    // answer stands — so a genuinely wrong password still says so.
    if (failure == AuthError.emailNotFound ||
        failure == AuthError.wrongPassword) {
      final viaCloud = await _signInFromCloud(
        rekeyExisting: failure == AuthError.wrongPassword,
      );
      if (viaCloud == null) failure = null;
    } else if (failure == null) {
      // Signing out of the device now signs out of the cloud as well, so a
      // returning student would otherwise land disconnected every time. Most
      // use one password for both; try it quietly, and if it is not the cloud
      // password they can still connect from the Cloud screen.
      final cloud = CloudService.instance;
      if (!cloud.isSignedIn &&
          await cloud.waitUntilReady(const Duration(seconds: 8))) {
        try {
          await cloud.signIn(email: _email.text, password: _password.text);
        } on CloudException {
          // Not connected, which is a state the app already handles.
        }
      }
    }

    if (!mounted) return;

    final problem = failure;
    if (problem != null) {
      setState(() {
        _error = problem.message;
        _busy = false;
      });
      return;
    }

    await NoteRepository.instance.load();
    if (!mounted) return;

    if (_passwordCaughtUp) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Password updated on this device too.')),
        ),
      );
    } else if (_restoredFromCloud) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('Signed in from your cloud account. Notes from another phone '
            'are not here yet — if you backed them up, use Settings → '
            'Google Drive backup → Restore.'),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }

    _openNotebook();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RiseIn(
                      delay: const Duration(milliseconds: 60),
                      child: _Eyebrow(tr('WELCOME BACK')),
                    ),
                    const SizedBox(height: 6),
                    PenWordmark(
                      text: 'NoteNest',
                      style: t.displaySmall?.copyWith(fontSize: 38),
                    ),
                    const SizedBox(height: 12),
                    RiseIn(
                      delay: const Duration(milliseconds: 900),
                      child: Text(
                        tr('Write it, photograph it, record it. Revise what the '
                        'exam needs first.'),
                        style: t.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 24),
                    RiseIn(
                      delay: const Duration(milliseconds: 260),
                      child: AuthCard(
                        children: [
                          AuthField(
                            label: tr('EMAIL'),
                            hint: 'you@university.edu',
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            accent: NestColor.tabs[3],
                          ),
                          const SizedBox(height: 18),
                          AuthField(
                            label: tr('PASSWORD'),
                            hint: tr('Your password'),
                            controller: _password,
                            obscure: _obscure,
                            accent: NestColor.tabs[1],
                            onToggleObscure: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy ? null : _forgotPassword,
                              child: Text(tr('Forgot your password?')),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            AuthErrorLine(message: _error!),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: Text(
                                _busy ? tr('Opening your notebook...') : tr('Sign in'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          GoogleSignInButton(
                            busy: _busy,
                            onPressed: _busy ? null : _continueWithGoogle,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    RiseIn(
                      delay: const Duration(milliseconds: 380),
                      child: Center(
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterPage(),
                                    ),
                                  ),
                          child: Text(tr('New here? Create an account')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small uppercase label above a heading.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: nestEyebrow);
}

/// Fades and lifts its child into place once, after [delay].
///
/// Entrance motion only. Nothing on this screen keeps moving except the
/// capability line, which is carrying information.
class RiseIn extends StatelessWidget {
  const RiseIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.distance = 14,
  });

  final Widget child;
  final Duration delay;
  final double distance;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: Future.delayed(delay),
      builder: (context, snapshot) {
        final started = snapshot.connectionState == ConnectionState.done;
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          tween: Tween(begin: 0, end: started ? 1 : 0),
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, distance * (1 - t)),
              child: child,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// The white card the form sits on, like a note laid over the page.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.card),
        border: Border.all(color: NestColor.rule),
        boxShadow: [
          BoxShadow(
            color: NestColor.o(NestColor.ink, 0.05),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// A labelled field whose underline is drawn in highlighter when focused.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.onToggleObscure,
    this.keyboardType,
    this.capitalization = TextCapitalization.none,
    this.helper,
    this.accent,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;
  final String? helper;

  /// The colour of the underline that sweeps in on focus.
  final Color? accent;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.label,
              style: nestEyebrow.copyWith(
                color: _focused ? NestColor.pen : NestColor.inkFaint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          obscureText: widget.obscure,
          keyboardType: widget.keyboardType,
          textCapitalization: widget.capitalization,
          style: TextStyle(fontSize: 15, color: NestColor.ink),
          decoration: InputDecoration(
            hintText: widget.hint,
            filled: true,
            fillColor: NestColor.paper,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            suffixIcon: widget.onToggleObscure == null
                ? null
                : IconButton(
                    onPressed: widget.onToggleObscure,
                    icon: Icon(
                      widget.obscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 20,
                      color: NestColor.inkFaint,
                    ),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NestRadius.tile),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NestRadius.tile),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NestRadius.tile),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        // The highlighter underline, drawn only while the field has focus.
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            tween: Tween(begin: 0, end: _focused ? 1 : 0),
            builder: (context, t, _) => Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: t.clamp(0.0001, 1),
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: NestColor.o(widget.accent ?? NestColor.highlight, t),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(2),
                      bottomRight: Radius.circular(3),
                      topRight: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.helper != null) ...[
          const SizedBox(height: 6),
          Text(widget.helper!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class AuthErrorLine extends StatelessWidget {
  const AuthErrorLine({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: NestColor.o(NestColor.redPen, 0.08),
        borderRadius: BorderRadius.circular(NestRadius.tile),
        border: Border(
          left: BorderSide(color: NestColor.redPen, width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 18, color: NestColor.redPen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: NestColor.redPen),
            ),
          ),
        ],
      ),
    );
  }
}
