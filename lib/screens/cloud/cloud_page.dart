import 'package:flutter/material.dart';

import '../../data/auth_repository.dart';
import '../../data/cloud_service.dart';
import '../../models/cloud_profile.dart';
import '../../theme/nest_theme.dart';

/// Connecting this device's account to the cloud.
///
/// The screen is honest about what it is: an optional extra. Everything the
/// app already does keeps working without it, and the copy says so rather than
/// pushing a student to sign up for something they may not need.
class CloudPage extends StatefulWidget {
  const CloudPage({super.key});

  @override
  State<CloudPage> createState() => _CloudPageState();
}

class _CloudPageState extends State<CloudPage> {
  final _cloud = CloudService.instance;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _creating = true;
  bool _hidePassword = true;
  CloudRole _role = CloudRole.student;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The local account already knows these. Retyping them is busywork, and a
    // mismatched address is how two accounts for one person happen.
    final local = AuthRepository.instance.currentUser;
    _name.text = local?.name ?? '';
    _email.text = local?.email ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text;
    final password = _password.text;

    // Checked here so an obvious typo gets an instant answer instead of a
    // round trip to Firebase and a code.
    if (!looksLikeEmail(email)) {
      setState(() => _error = 'That address does not look right.');
      return;
    }
    final passwordIssue = passwordProblem(password);
    if (passwordIssue != null) {
      setState(() => _error = passwordIssue);
      return;
    }
    if (_creating && _name.text.trim().isEmpty) {
      setState(() => _error = 'Type the name classmates will see.');
      return;
    }

    setState(() => _error = null);

    try {
      if (_creating) {
        await _cloud.createAccount(
          name: _name.text,
          email: email,
          password: password,
          role: _role,
          institution: AuthRepository.instance.currentUser?.institution ?? '',
        );
      } else {
        await _cloud.signIn(email: email, password: password);
      }
      if (!mounted) return;
      _password.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connected to the cloud'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on CloudException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'That did not work. Try again in a moment.');
      }
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NestColor.card,
        title: const Text('Disconnect from the cloud?'),
        content: const Text(
          'Your notes, subjects and exams are stored on this device and are '
          'not touched. Only the cloud features stop until you connect again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _cloud.signOutOfCloud();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud account')),
      body: ListenableBuilder(
        listenable: _cloud,
        builder: (context, _) {
          if (!_cloud.isReady) return _unavailable(context);
          if (_cloud.isSignedIn) return _connected(context);
          return _form(context);
        },
      ),
    );
  }

  // ---------------------------------------------------------- unavailable

  Widget _unavailable(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
      children: [
        const _Banner(
          icon: Icons.cloud_off_rounded,
          colour: NestColor.redPen,
          title: 'The cloud is not available',
          body: 'Everything stored on this device still works — notes, '
              'subjects, exams, cover pages, conversions. Only sharing, chat '
              'and assignments need the cloud.',
        ),
        const SizedBox(height: 18),
        const Text('WHAT FIREBASE SAID', style: nestEyebrow),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NestColor.paper,
            borderRadius: BorderRadius.circular(NestRadius.tile),
          ),
          child: SelectableText(
            _cloud.startupError ?? 'Firebase did not start.',
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ connected

  Widget _connected(BuildContext context) {
    final profile = _cloud.profile;

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: NestColor.card,
            borderRadius: BorderRadius.circular(NestRadius.card),
            boxShadow: NestShadow.resting,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: NestColor.o(NestColor.mint, 0.16),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  profile?.initials ?? '?',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: NestColor.mint,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cloud_done_rounded,
                            size: 15, color: NestColor.mint),
                        const SizedBox(width: 6),
                        Text(
                          'CONNECTED',
                          style: nestEyebrow.copyWith(color: NestColor.mint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      profile?.name.isNotEmpty == true
                          ? profile!.name
                          : 'No name set',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      profile?.email ?? '',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (!_cloud.emailVerified) ...[
          const SizedBox(height: 16),
          _Banner(
            icon: Icons.mark_email_unread_rounded,
            colour: NestColor.redPen,
            title: 'Confirm your email',
            body: 'We sent a link to ${profile?.email ?? 'your address'}. '
                'Until you open it, classmates cannot find you by email. '
                'Check spam as well.',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _cloud.isBusy ? null : _checkVerified,
                child: const Text('I have confirmed it'),
              ),
              OutlinedButton(
                onPressed: _cloud.isBusy ? null : _resendVerification,
                child: const Text('Send the link again'),
              ),
            ],
          ),
        ],

        const SizedBox(height: 20),
        const Text('YOU ARE HERE AS', style: nestEyebrow),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final role in CloudRole.values)
              _Chip(
                label: role.label,
                selected: (profile?.role ?? CloudRole.student) == role,
                onTap: _cloud.isBusy ? null : () => _setRole(role),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          (profile?.role ?? CloudRole.student).blurb,
          style: Theme.of(context).textTheme.bodySmall,
        ),

        const SizedBox(height: 24),
        const Text('WHAT THIS UNLOCKS', style: nestEyebrow),
        const SizedBox(height: 10),
        const _Unlock(
          icon: Icons.send_rounded,
          title: 'Send a note to a classmate',
          body: 'Straight into their Shared inbox, with an Accept step — no '
              'file to save and find.',
        ),
        const _Unlock(
          icon: Icons.forum_rounded,
          title: 'Chat',
          body: 'One to one, and in a study group.',
        ),
        const _Unlock(
          icon: Icons.groups_rounded,
          title: 'Study groups',
          body: 'A group that lives somewhere both phones can see.',
        ),
        const _Unlock(
          icon: Icons.assignment_rounded,
          title: 'Assignments',
          body: 'A teacher sets one with a deadline; students hand work in.',
        ),
        const SizedBox(height: 10),
        Text(
          'These arrive in the next step. This screen is the account they '
          'will all run on.',
          style: Theme.of(context).textTheme.bodySmall,
        ),

        const SizedBox(height: 26),
        OutlinedButton.icon(
          onPressed: _cloud.isBusy ? null : _disconnect,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Disconnect'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            foregroundColor: NestColor.redPen,
          ),
        ),
      ],
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _checkVerified() async {
    try {
      final verified = await _cloud.refreshVerification();
      _say(verified
          ? 'Email confirmed. Classmates can find you now.'
          : 'Not confirmed yet. Open the link in the email, then try again.');
    } on CloudException catch (e) {
      _say(e.message);
    }
  }

  Future<void> _resendVerification() async {
    try {
      await _cloud.sendVerificationEmail();
      _say('Sent. It can take a minute to arrive.');
    } on CloudException catch (e) {
      _say(e.message);
    }
  }

  Future<void> _setRole(CloudRole role) async {
    try {
      await _cloud.updateProfile(role: role);
    } on CloudException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ----------------------------------------------------------------- form

  Widget _form(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
      children: [
        const _Banner(
          icon: Icons.cloud_queue_rounded,
          colour: NestColor.pen,
          title: 'The cloud is optional',
          body: 'NoteNest works without it. Connect only if you want to send '
              'notes to classmates, chat, or hand work in to a teacher.',
        ),
        const SizedBox(height: 20),

        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Create')),
            ButtonSegment(value: false, label: Text('Sign in')),
          ],
          selected: {_creating},
          onSelectionChanged: (set) => setState(() {
            _creating = set.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 20),

        if (_creating) ...[
          _Field(
            label: 'Name classmates will see',
            controller: _name,
            capitalize: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
        ],

        _Field(
          label: 'Email',
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          capitalize: TextCapitalization.none,
          // Fixed to the device account's address. The cloud account is the
          // same person, and letting it be a different address is how one
          // student's phone ended up connected to another student's cloud.
          readOnly: AuthRepository.instance.currentUser != null,
        ),
        const SizedBox(height: 14),

        _Field(
          label: 'Password',
          controller: _password,
          obscure: _hidePassword,
          capitalize: TextCapitalization.none,
          suffix: IconButton(
            onPressed: () => setState(() => _hidePassword = !_hidePassword),
            icon: Icon(
              _hidePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 19,
            ),
          ),
        ),
        if (_creating) ...[
          const SizedBox(height: 4),
          Text(
            'At least $minPasswordLength characters. This is a separate '
            'password from the one you use to open the app.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          const Text('I AM A', style: nestEyebrow),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final role in CloudRole.values)
                _Chip(
                  label: role.label,
                  selected: _role == role,
                  onTap: () => setState(() => _role = role),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _role.blurb,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],

        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NestColor.o(NestColor.redPen, 0.08),
              borderRadius: BorderRadius.circular(NestRadius.tile),
            ),
            child: Text(
              _error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: NestColor.redPen),
            ),
          ),
        ],

        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _cloud.isBusy ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
            child: Text(
              _cloud.isBusy
                  ? 'Working…'
                  : _creating
                      ? 'Create cloud account'
                      : 'Sign in',
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- small parts

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.colour,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color colour;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NestColor.o(colour, 0.07),
        borderRadius: BorderRadius.circular(NestRadius.card),
        border: Border.all(color: NestColor.o(colour, 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colour),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Unlock extends StatelessWidget {
  const _Unlock({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: NestColor.pen),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.capitalize = TextCapitalization.none,
    this.readOnly = false,
  });

  final String label;
  final TextEditingController controller;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextCapitalization capitalize;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: NestColor.inkSoft,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          readOnly: readOnly,
          obscureText: obscure,
          keyboardType: keyboardType,
          textCapitalization: capitalize,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: NestColor.paper,
            isDense: true,
            suffixIcon: suffix,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NestRadius.chip),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? NestColor.tintPen : NestColor.paper,
          borderRadius: BorderRadius.circular(NestRadius.tile),
          boxShadow:
              selected ? NestShadow.glow(NestColor.pen) : const <BoxShadow>[],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: NestColor.ink,
          ),
        ),
      ),
    );
  }
}
