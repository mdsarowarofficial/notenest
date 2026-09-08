import 'package:flutter/material.dart';

import '../../data/auth_repository.dart';
import '../../data/note_repository.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_paper.dart';
import '../../widgets/pen_wordmark.dart';
import '../setup/setup_flow.dart';
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
    if (!mounted) return;

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
                        'Your notes stay on this device until you connect a '
                        'cloud account later.',
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
