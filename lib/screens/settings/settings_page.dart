import 'package:flutter/material.dart';

import '../../data/auth_repository.dart';
import '../../data/note_repository.dart';
import '../../models/semester.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_mark_tile.dart';
import '../cloud/cloud_page.dart';
import '../semester/degree_sheet.dart';
import '../semester/semester_page.dart';
import '../trash/trash_page.dart';

/// The gear in the drawer used to say "Settings is not built yet", because it
/// was not. This is it.
///
/// It is deliberately not a dumping ground for every switch somebody can think
/// of. Everything here is something the app could already do but had nowhere
/// to offer:
///
///   * the degree dates, which until now were only reachable through the
///     Semesters screen;
///   * changing the device password, which existed in AuthRepository and was
///     reachable from no screen at all;
///   * clearing recent searches, likewise;
///   * the open-source licences, which Google Play expects an app to show and
///     which nothing in NoteNest displayed.
///
/// What it does not do is invent preferences. A setting nobody asked for is a
/// decision pushed onto the student.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final plan = repo.semesterPlan;
          final current = repo.settledSemester ?? repo.currentSemester;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              const _Heading('YOUR DEGREE'),
              _Card(
                children: [
                  _Row(
                    icon: Icons.school_rounded,
                    tint: NestColor.tintPen,
                    ink: NestColor.penDeep,
                    title: plan.university?.isNotEmpty == true
                        ? plan.university!
                        : 'University and dates',
                    value: plan.isDated
                        ? '${current == null ? '—' : semesterLabelFor(current)}'
                            ' · ${plan.system.label}'
                        : 'Not set up yet',
                    onTap: () => showDegreeSheet(context),
                  ),
                  _Row(
                    icon: Icons.menu_book_rounded,
                    tint: NestColor.tintWarm,
                    ink: NestColor.warmDeep,
                    title: 'Semesters and courses',
                    value: 'What each term held',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SemesterPage()),
                    ),
                  ),
                  _Row(
                    icon: Icons.alarm_rounded,
                    tint: NestColor.tintMint,
                    ink: NestColor.mintDeep,
                    title: 'Revision plan',
                    value: repo.reminderChoice ?? 'Not chosen',
                    onTap: () => _pickReminder(context, repo),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              const _Heading('ACCOUNT'),
              _Card(
                children: [
                  _Row(
                    icon: Icons.cloud_queue_rounded,
                    tint: NestColor.tintPen,
                    ink: NestColor.penDeep,
                    title: 'Cloud account',
                    value: 'Sharing, groups and chat',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CloudPage()),
                    ),
                  ),
                  _Row(
                    icon: Icons.password_rounded,
                    tint: NestColor.tintRed,
                    ink: NestColor.redDeep,
                    title: 'Change password',
                    value: 'The one you use on this device',
                    onTap: () => _changePassword(context),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              const _Heading('ON THIS DEVICE'),
              _Card(
                children: [
                  _Row(
                    icon: Icons.delete_outline_rounded,
                    tint: NestColor.tintWarm,
                    ink: NestColor.warmDeep,
                    title: 'Trash',
                    value: 'Notes you deleted',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TrashPage()),
                    ),
                  ),
                  _Row(
                    icon: Icons.search_off_rounded,
                    tint: NestColor.tintMint,
                    ink: NestColor.mintDeep,
                    title: 'Clear recent searches',
                    value: 'Only the list of what you typed',
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await repo.clearRecentSearches();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Recent searches cleared.')),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 24),
              const _Heading('ABOUT'),
              _Card(
                children: [
                  _Row(
                    icon: Icons.article_outlined,
                    tint: NestColor.tintPen,
                    ink: NestColor.penDeep,
                    title: 'Open-source licences',
                    value: 'The packages NoteNest is built on',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'NoteNest',
                      applicationVersion: _version,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const _Honesty(),
            ],
          );
        },
      ),
    );
  }

  /// Kept in step with pubspec.yaml by hand. Reading it at runtime would mean
  /// another package for one string.
  static const _version = '1.0.0';

  static Future<void> _pickReminder(
      BuildContext context, NoteRepository repo) async {
    const options = [
      'After every class',
      'Every evening',
      'Only before exams',
    ];

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 18),
            const Text('YOUR REVISION PLAN', style: nestEyebrow),
            const SizedBox(height: 14),
            for (final option in options)
              ListTile(
                title: Text(option),
                trailing: repo.reminderChoice == option
                    ? const Icon(Icons.check_rounded, color: NestColor.pen)
                    : null,
                onTap: () => Navigator.pop(sheetContext, option),
              ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
    if (picked != null) await repo.saveReminder(picked);
  }

  static Future<void> _changePassword(BuildContext context) async {
    final result = await showDialog<_PasswordPair>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (result == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final error = await AuthRepository.instance.changePassword(
      currentPassword: result.current,
      newPassword: result.next,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(error == null ? 'Password changed.' : error.message),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(text, style: nestEyebrow),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: NestColor.card,
          borderRadius: BorderRadius.circular(NestRadius.card),
          boxShadow: NestShadow.resting,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.tint,
    required this.ink,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final Color ink;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              MarkTile.tool(icon, tint: tint, ink: ink, size: 40),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: NestFont.body,
                        fontSize: 12,
                        color: NestColor.inkMeta,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: NestColor.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the app does not do, said where somebody looking for a switch will
/// read it.
///
/// Two of these come up repeatedly and both are easy to assume: that a
/// "revision plan" rings an alarm, and that notes are backed up somewhere.
/// Neither is true, and a student who finds out the hard way has lost
/// something.
class _Honesty extends StatelessWidget {
  const _Honesty();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: NestColor.paper,
        borderRadius: BorderRadius.circular(NestRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Worth knowing', style: t.titleSmall),
          const SizedBox(height: 8),
          Text(
            'Your revision plan decides what the app puts in front of you — it '
            'does not send phone notifications. Those are not built yet.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Notes live on this device. A cloud account is for sharing and '
            'chat; it is not a backup, and notes are not copied to it. Delete '
            'the app and the notes go with it.',
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PasswordPair {
  const _PasswordPair(this.current, this.next);

  final String current;
  final String next;
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  void _submit() {
    if (_next.text.length < 6) {
      setState(() => _problem = 'Six characters at least.');
      return;
    }
    if (_next.text != _again.text) {
      setState(() => _problem = 'The two new passwords are different.');
      return;
    }
    Navigator.pop(context, _PasswordPair(_current.text, _next.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This is the password for this device. Your cloud password is '
              'separate and is changed by email.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _current,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _again,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'New password again'),
            ),
            if (_problem != null) ...[
              const SizedBox(height: 12),
              Text(
                _problem!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: NestColor.redDeep),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Change')),
      ],
    );
  }
}
