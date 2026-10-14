import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/semester.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/semester_picker.dart';
import '../../widgets/nest_stepper.dart';
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

  static const _steps = <NestStep>[
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
      hint: 'Pick when NoteNest should remind you to revise.',
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
    super.dispose();
  }

  /// Returns an error message when the current step is not ready.
  String? _validate() {
    switch (_step) {
      case 0:
        return semesterProblem(_semesterLabel);
      case 1:
        if (!_repo.hasSubjects) return 'Add at least one subject';
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

    if (_step == 0) {
      await _repo.saveSemester(_semesterLabel, system: _semesterSystem);
    } else if (_step == 2) {
      await _repo.saveReminder(_reminder);
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
                  SizedBox(
                    width: 180,
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
    switch (step) {
      case 0:
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
      case 1:
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
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
            const Text('REVISION REMINDER', style: nestEyebrow),
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
            border: Border.all(color: NestColor.rule),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
}
