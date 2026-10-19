import 'package:flutter/material.dart';

import '../../data/auth_repository.dart';
import '../../data/account_sync.dart';
import '../../data/cloud_service.dart';
import '../../data/note_repository.dart';
import '../../data/profile_photo.dart';
import '../../models/semester.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_mark_tile.dart';
import '../auth/account_switch.dart';
import '../backup/drive_backup_page.dart';
import '../cloud/cloud_page.dart';
import '../cover/university_picker.dart';
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
        listenable: Listenable.merge([repo, CloudService.instance]),
        builder: (context, _) {
          final plan = repo.semesterPlan;
          final current = repo.settledSemester ?? repo.currentSemester;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              if (repo.isTeacher) ...[
                const _Heading('TEACHING'),
                _Card(
                  children: [
                    _Row(
                      icon: Icons.account_balance_rounded,
                      tint: NestColor.tintPen,
                      ink: NestColor.penDeep,
                      title: 'University',
                      value: repo.university?.isNotEmpty == true
                          ? repo.university!
                          : 'Not set',
                      onTap: () async {
                        final picked = await showUniversityPicker(context);
                        if (picked != null) {
                          await repo.saveProgramme(university: picked.name);
                        }
                      },
                    ),
                    _Row(
                      icon: Icons.class_outlined,
                      tint: NestColor.tintWarm,
                      ink: NestColor.warmDeep,
                      title: 'Course',
                      value: repo.teachingCourse ?? 'Not set (optional)',
                      onTap: () => _editCourse(context, repo),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ] else ...[
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
              ],
              const _Heading('ACCOUNT'),
              _Card(
                children: [
                  _Row(
                    icon: Icons.badge_outlined,
                    tint: NestColor.tintPen,
                    ink: NestColor.penDeep,
                    title: 'Account type',
                    value: repo.isTeacher ? 'Teacher' : 'Student',
                    onTap: () => _pickRole(context, repo),
                  ),
                  _Row(
                    icon: Icons.account_circle_outlined,
                    tint: NestColor.tintWarm,
                    ink: NestColor.warmDeep,
                    title: 'Profile photo',
                    value: myPhoto() == null
                        ? 'Not set — tap to add one'
                        : 'Shown on Today and to your classes',
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final message = await changeMyPhoto(context);
                      if (message != null) {
                        messenger
                            .showSnackBar(SnackBar(content: Text(message)));
                      }
                    },
                  ),
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
                  // Offered only to an account that has a password. For a
                  // Google account the row used to be here too, and tapping it
                  // asked for a current password that had never been set — a
                  // dead end dressed up as a setting.
                  if (!AuthRepository.instance.currentUserUsesGoogle)
                    _Row(
                      icon: Icons.password_rounded,
                      tint: NestColor.tintRed,
                      ink: NestColor.redDeep,
                      title: 'Change password',
                      value: 'The one you use on this device',
                      onTap: () => _changePassword(context),
                    )
                  else
                    const _Row(
                      icon: Icons.verified_user_outlined,
                      tint: NestColor.tintPen,
                      ink: NestColor.penDeep,
                      title: 'Sign-in method',
                      value: 'Google — there is no password to change',
                    ),
                  _Row(
                    icon: Icons.switch_account_outlined,
                    tint: NestColor.tintMint,
                    ink: NestColor.mintDeep,
                    title: 'Switch account',
                    value: AuthRepository.instance.currentUser?.email ??
                        'Another account on this phone',
                    onTap: () => showAccountSwitcher(context),
                  ),
                  _Row(
                    icon: Icons.logout_rounded,
                    tint: NestColor.tintRed,
                    ink: NestColor.redDeep,
                    title: 'Sign out',
                    value: 'Your notes stay on this phone',
                    onTap: () => confirmSignOut(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _Heading('BACKUP'),
              _Card(
                children: [
                  _Row(
                    icon: Icons.add_to_drive_rounded,
                    tint: NestColor.tintPen,
                    ink: NestColor.penDeep,
                    title: 'Google Drive backup',
                    value: repo.lastBackupAt == null
                        ? 'Not backed up yet'
                        : 'Last backup ${_ago(repo.lastBackupAt!)}'
                            '${repo.autoBackup ? ' · daily' : ''}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const DriveBackupPage()),
                    ),
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
                        const SnackBar(
                            content: Text('Recent searches cleared.')),
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
                    icon: Icons.tour_outlined,
                    tint: NestColor.tintMint,
                    ink: NestColor.mintDeep,
                    title: 'Show the app tour again',
                    value: 'A step-by-step look at each screen',
                    onTap: () async {
                      await repo.saveTourDone(false);
                      if (!context.mounted) return;
                      // Back to the notebook, where the tour starts on its own
                      // because it is no longer marked as seen.
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                  ),
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

  static Future<void> _pickRole(
      BuildContext context, NoteRepository repo) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text('ACCOUNT TYPE', style: nestEyebrow),
            const SizedBox(height: 6),
            for (final (key, label, blurb) in const [
              (
                'student',
                'Student',
                'Semesters, subjects, exams, and classes '
                    'you join'
              ),
              ('teacher', 'Teacher', 'Make classes, post work, and grade it'),
            ])
              ListTile(
                leading: Icon(
                  repo.roleKey == key
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: repo.roleKey == key ? NestColor.pen : null,
                ),
                title: Text(label),
                subtitle: Text(blurb),
                onTap: () => Navigator.pop(sheetContext, key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == repo.roleKey) return;
    await repo.saveRole(picked);
    await syncCloudRole();
  }

  static Future<void> _editCourse(
      BuildContext context, NoteRepository repo) async {
    final controller = TextEditingController(text: repo.teachingCourse ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Course you teach'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration:
              const InputDecoration(hintText: 'CSE 211 — Data Structures'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved != null) await repo.saveTeachingCourse(saved);
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'yesterday';
    return '${d.inDays} days ago';
  }

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
    this.onTap,
  });

  final IconData icon;
  final Color tint;
  final Color ink;
  final String title;
  final String value;

  /// Null for a row that states something rather than leading somewhere. The
  /// chevron goes with it, because an arrow that points nowhere is a lie about
  /// what a tap will do.
  final VoidCallback? onTap;

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
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
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
              if (onTap != null)
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
            'Your revision plan decides what the app puts in front of you. '
            'Phone reminders for tasks and exams are off until you turn them '
            'on in the notifications settings; they ring from this phone, '
            'with no internet needed.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Notes live on this device. A cloud account is for sharing, '
            'classes and chat; notes are not copied to it. To keep them if '
            'this phone is lost, use Google Drive backup above.',
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
              decoration: const InputDecoration(labelText: 'Current password'),
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
