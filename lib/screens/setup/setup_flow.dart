import 'package:flutter/material.dart';

import '../../data/account_sync.dart';
import '../../data/auth_repository.dart';
import '../../data/note_repository.dart';
import '../../models/semester.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/semester_picker.dart';
import '../../widgets/nest_stepper.dart';
import '../cover/university_picker.dart';
import '../shell/home_shell.dart';
import '../subjects/subject_form.dart';

/// First-run setup. Requirement 1.
///
/// Everything entered here is written to the database, so the flow never runs
/// twice and the values show up in the drawer straight away.
class SetupFlow extends StatefulWidget {
  const SetupFlow({super.key});

  @override
  State<SetupFlow> createState() => _SetupFlowState();
}

class _SetupFlowState extends State<SetupFlow> {
  final _repo = NoteRepository.instance;

  /// What the picker has settled on, and under which system.
  String _semesterLabel = '';
  SemesterSystem _semesterSystem = SemesterSystem.bi;

  int _step = 0;
  String? _error;
  bool _busy = false;

  /// Student or teacher. Asked first, because it decides every step after it:
  /// a teacher has no semester and takes no subjects, so the student's three
  /// steps would be questions with no true answer.
  late String _role = _repo.roleKey;
  bool get _teacher => _role == 'teacher';

  /// Where a teacher teaches, and what — the course is optional.
  // What they typed at registration, if anything, so it is not asked twice.
  late String _university = _repo.university ??
      AuthRepository.instance.currentUser?.institution?.trim() ??
      '';
  late final _course = TextEditingController(text: _repo.teachingCourse ?? '');

  static const _roleStep = NestStep(
    title: 'Who are you',
    icon: Icons.badge_rounded,
    hint: 'NoteNest works a little differently for teachers.',
  );

  static const _teachStep = NestStep(
    title: 'Where you teach',
    icon: Icons.co_present_rounded,
    hint: 'Your university, and the course if you like. Both can change later.',
  );

  List<NestStep> get _steps =>
      _teacher ? const [_roleStep, _teachStep] : [_roleStep, ..._studentSteps];

  /// What the current index means, so the logic below reads by name rather
  /// than by a number that shifts with the role.
  String get _stepId {
    if (_step == 0) return 'role';
    if (_teacher) return 'teach';
    return const ['semester', 'subjects', 'routine'][_step - 1];
  }

  static const _studentSteps = <NestStep>[
    NestStep(
      title: 'Your semester',
      icon: Icons.school_rounded,
      hint: 'Name the semester these notes belong to.',
    ),
    NestStep(
      title: 'Your subjects',
      icon: Icons.folder_rounded,
      hint: 'Add the subjects you are taking. You can change these later.',
    ),
    NestStep(
      title: 'Study routine',
      icon: Icons.alarm_rounded,
      // Deliberately a plan, not a promise.
      //
      // This used to read "Pick when NoteNest should remind you to revise",
      // and nothing in the app ever read the answer — there is no notification
      // machinery here at all. A setting that quietly does nothing is worse
      // than no setting: the student waits for a reminder that was never
      // coming. So the question now asks what it can honestly ask, the answer
      // is shown back on the profile as their own stated routine, and when
      // scheduled reminders are built this is the setting that will drive them.
      hint: 'When do you plan to revise? Noted for you — NoteNest does not '
          'send alerts yet.',
    ),
  ];

  static const _reminders = [
    'After every class',
    'Every evening',
    'Only before exams',
  ];

  String _reminder = 'Every evening';

  @override
  void initState() {
    super.initState();
    _semesterLabel = _repo.semesterLabel ?? '';
    _semesterSystem = _repo.semesterSystem;
    _reminder = _repo.reminderChoice ?? _reminder;
  }

  @override
  void dispose() {
    _course.dispose();
    super.dispose();
  }

  /// Returns an error message when the current step is not ready.
  String? _validate() {
    switch (_stepId) {
      case 'semester':
        return semesterProblem(_semesterLabel);
      case 'subjects':
        if (!_repo.hasSubjects) return 'Add at least one subject';
        return null;
      case 'teach':
        if (_university.trim().isEmpty) return 'Pick your university';
        return null;
      default:
        return null;
    }
  }

  Future<void> _next() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });

    switch (_stepId) {
      case 'role':
        await _repo.saveRole(_role);
        // The cloud profile carries the role too, and the rules read it there
        // before letting anybody make a class. Best effort: setup must not
        // stall on a network.
        await syncCloudRole();
      case 'semester':
        await _repo.saveSemester(_semesterLabel, system: _semesterSystem);
      case 'routine':
        await _repo.saveReminder(_reminder);
      case 'teach':
        await _repo.saveProgramme(university: _university);
        await _repo.saveTeachingCourse(_course.text);
    }

    if (!mounted) return;

    if (_step < _steps.length - 1) {
      setState(() {
        _step++;
        _busy = false;
      });
    } else {
      await _repo.completeSetup();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    }
  }

  Future<void> _pickUniversity() async {
    final picked = await showUniversityPicker(context);
    if (picked == null || !mounted) return;
    setState(() {
      _university = picked.name;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NestStepper(
                steps: _steps,
                currentIndex: _step,
                onStepTapped: (i) => setState(() {
                  _step = i;
                  _error = null;
                }),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListenableBuilder(
                  listenable: _repo,
                  builder: (context, _) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: _body(_step),
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 17, color: NestColor.redPen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: NestColor.redPen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _step--;
                                _error = null;
                              }),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  ConstrainedBox(
                    // A floor, not a fixed width: "Open my notebook" wrapped onto
                    // two lines inside 180px at a normal text size.
                    constraints: const BoxConstraints(minWidth: 180),
                    child: FilledButton(
                      onPressed: _busy ? null : _next,
                      child: Text(
                        _step == _steps.length - 1
                            ? 'Open my notebook'
                            : 'Continue',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(int step) {
    switch (_stepId) {
      case 'role':
        return _Sheet(
          children: [
            const Text('I AM A', style: nestEyebrow),
            const SizedBox(height: 12),
            _RoleCard(
              icon: Icons.backpack_rounded,
              title: 'Student',
              blurb: 'Notes by semester and subject, exam countdowns, and '
                  'classes you join with a code.',
              selected: !_teacher,
              onTap: () => setState(() {
                _role = 'student';
                _error = null;
              }),
            ),
            const SizedBox(height: 10),
            _RoleCard(
              icon: Icons.co_present_rounded,
              title: 'Teacher',
              blurb: 'Make classes, share slides and PDFs, set assignments '
                  'with a deadline, and grade what comes back.',
              selected: _teacher,
              onTap: () => setState(() {
                _role = 'teacher';
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            Text(
              'You can change this later in Settings.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      case 'teach':
        return _Sheet(
          children: [
            const Text('UNIVERSITY', style: nestEyebrow),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(NestRadius.tile),
              onTap: _pickUniversity,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: NestColor.paper,
                  borderRadius: BorderRadius.circular(NestRadius.tile),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_rounded,
                        color: NestColor.pen),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _university.isEmpty
                            ? 'Pick your university'
                            : _university,
                        style: TextStyle(
                          fontSize: 14.5,
                          color: _university.isEmpty
                              ? NestColor.inkFaint
                              : NestColor.ink,
                        ),
                      ),
                    ),
                    const Icon(Icons.search_rounded, color: NestColor.inkFaint),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text('COURSE (OPTIONAL)', style: nestEyebrow),
            const SizedBox(height: 8),
            TextField(
              controller: _course,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'CSE 211 — Data Structures',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No semester to choose: that is a student\'s question. You make '
              'classes from the Classes tab, and students join with the code.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      case 'semester':
        return _Sheet(
          children: [
            SemesterPicker(
              system: _semesterSystem,
              label: _semesterLabel,
              onChanged: (system, label) => setState(() {
                _semesterSystem = system;
                _semesterLabel = label;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            Text(
              'Notes and subjects are filed under this semester, and a cover '
              'page prints it. You can change it later from your profile.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      case 'subjects':
        final subjects = _repo.subjects();
        return _Sheet(
          children: [
            Row(
              children: [
                const Text('SUBJECTS', style: nestEyebrow),
                const Spacer(),
                if (subjects.isNotEmpty)
                  Text('${subjects.length}', style: nestEyebrow),
              ],
            ),
            const SizedBox(height: 10),
            if (subjects.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'No subjects added yet.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in subjects)
                  GestureDetector(
                    onTap: () => showSubjectForm(context, existing: s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: NestColor.o(s.color, 0.3),
                        borderRadius: BorderRadius.circular(NestRadius.chip),
                      ),
                      child: Text(
                        s.code,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: NestColor.ink,
                        ),
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: () async {
                    final added = await showSubjectForm(context);
                    if (added && mounted) setState(() => _error = null);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(NestRadius.chip),
                      border: Border.all(color: NestColor.rule),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 16, color: NestColor.pen),
                        SizedBox(width: 4),
                        Text(
                          'Add subject',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: NestColor.pen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Tap a subject to rename it or change its index tab colour.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      default:
        return _Sheet(
          children: [
            const Text('YOUR REVISION PLAN', style: nestEyebrow),
            const SizedBox(height: 12),
            for (final r in _reminders)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(NestRadius.tile),
                  onTap: () => setState(() => _reminder = r),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NestColor.paper,
                      borderRadius: BorderRadius.circular(NestRadius.tile),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          r == _reminder
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 20,
                          color: r == _reminder
                              ? NestColor.pen
                              : NestColor.inkFaint,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          r,
                          style: const TextStyle(
                            fontSize: 14.5,
                            color: NestColor.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'Your choice is saved now. Reminders start arriving once '
              'notifications are added to the app.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
    }
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: NestColor.card,
            borderRadius: BorderRadius.circular(NestRadius.card),
            boxShadow: NestShadow.resting,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.blurb,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String blurb;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(NestRadius.tile),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? NestColor.tintPen : NestColor.paper,
            borderRadius: BorderRadius.circular(NestRadius.tile),
            border: Border.all(
              color: selected ? NestColor.pen : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 30,
                  color: selected ? NestColor.pen : NestColor.inkSoft),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(blurb, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? NestColor.pen : NestColor.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
