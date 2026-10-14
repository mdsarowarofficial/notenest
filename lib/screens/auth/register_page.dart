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
import 'login_page.dart';

/// Create an account on this device. Requirement 2.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _name = TextEditingController();
  final _institution = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _error;
  bool _busy = false;
  bool _obscure = true;

  CloudRole _role = CloudRole.student;

  /// Whether to make the cloud account in the same step.
  ///
  /// On by default when Firebase started. The two accounts used to be made
  /// separately, which meant everybody did the same work twice with the same
  /// details — and anybody who skipped the second one was later told, wrongly,
  /// that they had no account at all.
  bool _alsoCloud = true;

  /// Set when the device account was made but the cloud one was not, so the
  /// student is told plainly instead of finding out later.
  String? _cloudNote;

  @override
  void initState() {
    super.initState();
    // The rule list updates as the student types rather than only on submit.
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Creating an account with Google, which is the same call as signing in
  /// with one — see [continueWithGoogle].
  ///
  /// Nothing on this form is read. Name and address come from the Google
  /// account, the password does not exist, and the role starts as student and
  /// is changed in the cloud screen. Reading the half-filled fields instead
  /// would mean a student who typed a different address here ends up with an
  /// account under one address and a profile under another.
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
          const SnackBar(
            content: Text(googleCancelledNotice),
            duration: Duration(seconds: 7),
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
        // Not always SetupFlow, unlike the form below. A student signing in
        // with Google on a phone they have used before has already done setup,
        // and sending them back through it would ask for a semester they
        // already chose.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => NoteRepository.instance.setupDone
                ? const HomeShell()
                : const SetupFlow(),
          ),
        );
        return;
    }
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _busy = true;
    });

    final failure = await AuthRepository.instance.register(
      name: _name.text,
      email: _email.text,
      password: _password.text,
      institution: _institution.text,
    );

    if (!mounted) return;

    if (failure != null) {
      setState(() {
        _error = failure.message;
        _busy = false;
      });
      return;
    }

    await NoteRepository.instance.load();
    await NoteRepository.instance.saveRole(_role.key);

    // The cloud account, with the same details and the same password. It runs
    // after the device account on purpose: the device account is the one that
    // owns the notes, and it must not depend on a network that may not be
    // there.
    if (_alsoCloud && CloudService.instance.isReady) {
      try {
        await CloudService.instance.createAccount(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          role: _role,
          institution: _institution.text,
        );
      } on CloudException catch (e) {
        // Not fatal, and not hidden. The notebook works either way; what fails
        // here is sharing, chat and assignments, and the student should know
        // which of the two happened.
        _cloudNote = e.message;
      }
    }

    if (!mounted) return;

    if (_cloudNote != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your notebook is ready, but the cloud account was not made: '
            '$_cloudNote You can connect one later from the drawer.',
          ),
          duration: const Duration(seconds: 7),
        ),
      );
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SetupFlow()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pw = _password.text;

    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 48, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const RiseIn(
                      delay: Duration(milliseconds: 60),
                      child: Text('GET STARTED', style: nestEyebrow),
                    ),
                    const SizedBox(height: 6),
                    PenWordmark(
                      text: 'Start a notebook',
                      style: t.displaySmall?.copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: 10),
                    RiseIn(
                      delay: const Duration(milliseconds: 200),
                      child: Text(
                        'Your notes live on this device. The cloud account is '
                        'made alongside it, with the same password.',
                        style: t.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 22),
                    RiseIn(
                      delay: const Duration(milliseconds: 280),
                      child: AuthCard(
                        children: [
                          AuthField(
                            label: 'FULL NAME',
                            hint: 'Your full name',
                            controller: _name,
                            capitalization: TextCapitalization.words,
                            accent: NestColor.tabs[0],
                          ),
                          const SizedBox(height: 18),
                          AuthField(
                            label: 'UNIVERSITY',
                            hint: 'Your university or college',
                            controller: _institution,
                            capitalization: TextCapitalization.words,
                            accent: NestColor.tabs[2],
                          ),
                          const SizedBox(height: 18),
                          AuthField(
                            label: 'EMAIL',
                            hint: 'you@university.edu',
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            accent: NestColor.tabs[3],
                          ),
                          const SizedBox(height: 18),
                          AuthField(
                            label: 'PASSWORD',
                            hint: 'Choose a password',
                            controller: _password,
                            obscure: _obscure,
                            accent: NestColor.tabs[1],
                            onToggleObscure: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          const SizedBox(height: 14),
                          _Rule(met: pw.length >= 6, text: 'At least 6 characters'),
                          _Rule(
                            met: RegExp(r'[A-Z]').hasMatch(pw),
                            text: 'One capital letter',
                          ),
                          _Rule(
                            met: RegExp(r'[^A-Za-z0-9]').hasMatch(pw),
                            text: 'One special character',
                          ),
                          const SizedBox(height: 20),
                          const Text('YOU ARE A', style: nestEyebrow),
                          const SizedBox(height: 8),
                          SegmentedButton<CloudRole>(
                            segments: const [
                              ButtonSegment(
                                value: CloudRole.student,
                                icon: Icon(Icons.school_outlined, size: 17),
                                label: Text('Student'),
                              ),
                              ButtonSegment(
                                value: CloudRole.teacher,
                                icon: Icon(Icons.cast_for_education_outlined,
                                    size: 17),
                                label: Text('Teacher'),
                              ),
                            ],
                            selected: {_role},
                            onSelectionChanged: (v) =>
                                setState(() => _role = v.first),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _role.blurb,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (CloudService.instance.isReady) ...[
                            const SizedBox(height: 16),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _alsoCloud,
                              onChanged: (v) =>
                                  setState(() => _alsoCloud = v),
                              title: const Text('Set up the cloud too'),
                              subtitle: Text(
                                _alsoCloud
                                    ? 'One account, one password. Needed for '
                                        'sharing, chat and assignments.'
                                    : 'The notebook will work on this device '
                                        'only. You can connect later.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            AuthErrorLine(message: _error!),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: Text(
                                _busy ? 'Creating...' : 'Create account',
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
                      delay: const Duration(milliseconds: 400),
                      child: Center(
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => const LoginPage(),
                                    ),
                                  ),
                          child: const Text('I already have an account'),
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

class _Rule extends StatelessWidget {
  const _Rule({required this.met, required this.text});

  final bool met;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 15,
            color: met ? NestColor.mint : NestColor.inkFaint,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              color: met ? NestColor.inkSoft : NestColor.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}
