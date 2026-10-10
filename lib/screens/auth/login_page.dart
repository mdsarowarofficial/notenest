import 'package:flutter/material.dart';

import '../../data/auth_repository.dart';
import '../../data/note_repository.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_paper.dart';
import '../../widgets/pen_wordmark.dart';
import '../setup/setup_flow.dart';
import '../shell/home_shell.dart';
import 'register_page.dart';

/// Sign in to an account stored on this device. Requirement 2.
///
/// The screen is drawn as the first page of the notebook: ruled paper, a red
/// margin, subject tabs at the edge, and the form on a card laid over it.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _error;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _busy = true;
    });

    final failure = await AuthRepository.instance.signIn(
      email: _email.text,
      password: _password.text,
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
      MaterialPageRoute(
        builder: (_) => NoteRepository.instance.setupDone
            ? const HomeShell()
            : const SetupFlow(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

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
                      child: _Eyebrow('WELCOME BACK'),
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
                        'Write it, photograph it, record it. Revise what the '
                        'exam needs first.',
                        style: t.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 24),
                    RiseIn(
                      delay: const Duration(milliseconds: 260),
                      child: AuthCard(
                        children: [
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
                            hint: 'Your password',
                            controller: _password,
                            obscure: _obscure,
                            accent: NestColor.tabs[1],
                            onToggleObscure: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 18),
                            AuthErrorLine(message: _error!),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: Text(
                                _busy ? 'Opening your notebook...' : 'Sign in',
                              ),
                            ),
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
                          child: const Text('New here? Create an account'),
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
    this.accent = NestColor.highlight,
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
  final Color accent;

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
          style: const TextStyle(fontSize: 15, color: NestColor.ink),
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
                    color: NestColor.o(widget.accent, t),
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
        border: const Border(
          left: BorderSide(color: NestColor.redPen, width: 3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: NestColor.redPen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: NestColor.redPen),
            ),
          ),
        ],
      ),
    );
  }
}
