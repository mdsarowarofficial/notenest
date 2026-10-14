import 'package:flutter/material.dart';

import '../../data/auth_repository.dart';
import '../../data/note_repository.dart';
import '../../models/semester.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/semester_picker.dart';
import '../../widgets/nest_marks.dart';
import '../auth/login_page.dart';
import '../subjects/subject_form.dart';

/// The account screen. Requirement 15.
///
/// The email cannot be changed, because it identifies the account.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _auth = AuthRepository.instance;
  final _repo = NoteRepository.instance;

  bool _editing = false;
  late TextEditingController _name;
  late TextEditingController _institution;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _auth.currentUser?.name ?? '');
    _institution =
        TextEditingController(text: _auth.currentUser?.institution ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    await _auth.updateProfile(
      name: _name.text,
      institution: _institution.text,
    );
    if (!mounted) return;
    setState(() => _editing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile updated'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// The same picker the first-run setup uses, so a semester is written the
  /// same way whether it was chosen on day one or changed in March.
  Future<void> _editSemester() async {
    var system = _repo.semesterSystem;
    var label = _repo.semesterLabel ?? '';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: NestColor.paper,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: NestColor.rule,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Semester',
                  style: Theme.of(sheetContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                SemesterPicker(
                  system: system,
                  label: label,
                  onChanged: (s, l) => setSheet(() {
                    system = s;
                    label = l;
                  }),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true && semesterProblem(label) == null) {
      await _repo.saveSemester(label, system: system);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NestColor.card,
        title: const Text('Sign out?'),
        content: const Text(
          'Your notes stay on this device. You can sign back in any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _auth.signOut();
    _repo.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(
            fontFamily: NestFont.display,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: NestColor.ink,
          ),
        ),
        actions: [
          if (!_editing)
            TextButton(
              onPressed: () => setState(() => _editing = true),
              child: const Text('Edit'),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_auth, _repo]),
        builder: (context, _) {
          final user = _auth.currentUser;
          if (user == null) return const SizedBox.shrink();

          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
            children: [
              Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NestColor.pen,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      user.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name, style: t.headlineSmall),
                        const SizedBox(height: 4),
                        Text(user.email, style: t.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              if (_editing) ...[
                AuthField(
                  label: 'FULL NAME',
                  hint: 'Your full name',
                  controller: _name,
                  capitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                AuthField(
                  label: 'UNIVERSITY',
                  hint: 'Your university or college',
                  controller: _institution,
                  capitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _name.text = user.name;
                          _institution.text = user.institution ?? '';
                          setState(() => _editing = false);
                        },
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _save,
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                _row('UNIVERSITY', user.institution ?? 'Not set'),
                const PaperRule(),
                _row(
                  'SEMESTER',
                  _repo.semesterLabel ?? 'Not set',
                  onTap: _editSemester,
                ),
                const PaperRule(),
                _row(
                  'REVISION PLAN',
                  _repo.reminderChoice ?? 'Not set',
                ),
                const PaperRule(),
                _row('SUBJECTS', '${_repo.subjects().length}'),
              ],

              const SizedBox(height: 30),
              Row(
                children: [
                  const Text('YOUR SUBJECTS', style: nestEyebrow),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(height: 1, color: NestColor.rule),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_repo.subjects().isEmpty)
                Text('No subjects yet.', style: t.bodySmall)
              else
                for (final s in _repo.subjects())
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 5,
                      height: 32,
                      decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    title: Text(s.name, style: t.titleSmall),
                    subtitle: Text(
                      s.code,
                      style: nestEyebrow.copyWith(fontSize: 11),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_rounded,
                          size: 18, color: NestColor.inkFaint),
                      onPressed: () => showSubjectForm(context, existing: s),
                    ),
                  ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => showSubjectForm(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add subject'),
              ),

              const SizedBox(height: 36),
              TextButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout_rounded,
                    size: 18, color: NestColor.redPen),
                label: const Text(
                  'Sign out',
                  style: TextStyle(color: NestColor.redPen),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          children: [
            Expanded(child: Text(label, style: nestEyebrow)),
            Text(
              value,
              style: const TextStyle(fontSize: 14, color: NestColor.ink),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: NestColor.inkFaint),
            ],
          ],
        ),
      ),
    );
  }
}
