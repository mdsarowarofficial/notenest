import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/semester.dart';
import '../../theme/nest_theme.dart';
import '../../l10n/strings.dart';

/// Where the degree is, when it runs, and how the year is divided.
///
/// Four answers, asked once. From them the app works out which semester today
/// falls in, which is the question it used to put to the student on every new
/// device — and which it could never answer itself, because a semester was a
/// piece of text rather than a point in time.
///
/// Only the start date is required. A student who has not thought about their
/// graduation date still gets a sensible answer from a nominal semester
/// length, and asking for a date nobody knows is a good way to have it made up.
Future<bool> showDegreeSheet(BuildContext context) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _DegreeSheet(),
  );
  return saved ?? false;
}

class _DegreeSheet extends StatefulWidget {
  const _DegreeSheet();

  @override
  State<_DegreeSheet> createState() => _DegreeSheetState();
}

class _DegreeSheetState extends State<_DegreeSheet> {
  final _repo = NoteRepository.instance;
  late final TextEditingController _university =
      TextEditingController(text: _repo.university ?? '');

  late SemesterSystem _system = _repo.semesterSystem;
  late DateTime? _start = _repo.programmeStart;
  late DateTime? _end = _repo.programmeEnd;

  String? _problem;

  @override
  void dispose() {
    _university.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _start : _end) ??
        (isStart ? DateTime(now.year - 1, now.month) : DateTime(now.year + 3));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // Wide enough for a student who started late and one who is planning
      // ahead, narrow enough that a mis-tap cannot land in 1800.
      firstDate: DateTime(now.year - 15),
      lastDate: DateTime(now.year + 15),
      helpText: isStart ? tr('When did your degree start?') : tr('When should it end?'),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
      _problem = null;
    });
  }

  Future<void> _save() async {
    final problem = programmeDatesProblem(_start, _end);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }

    final navigator = Navigator.of(context);
    await _repo.saveProgramme(
      university: _university.text,
      start: _start,
      end: _end,
      system: _system,
      clearEnd: _end == null,
    );
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final plan = SemesterPlan(system: _system, start: _start, end: _end);
    final wouldBe = plan.semesterOn(DateTime.now());

    return Padding(
      padding: EdgeInsets.only(
        left: 22,
        right: 22,
        top: 22,
        bottom: MediaQuery.of(context).viewInsets.bottom + 26,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Your degree'), style: t.headlineSmall),
            const SizedBox(height: 6),
            Text(
              tr('Once the app knows when your degree runs it keeps the semester '
              'current by itself, and files each course under the term you '
              'took it in.'),
              style: t.bodySmall,
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _university,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: tr('University'),
                hintText: 'City University',
              ),
            ),
            const SizedBox(height: 16),

            Text(tr('HOW THE YEAR IS DIVIDED'), style: nestEyebrow),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in SemesterSystem.values)
                  GestureDetector(
                    onTap: () => setState(() => _system = option),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 170),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: option == _system
                            ? NestColor.tintPen
                            : NestColor.paper,
                        borderRadius: BorderRadius.circular(NestRadius.pill),
                        boxShadow: option == _system
                            ? NestShadow.glow(NestColor.pen)
                            : const <BoxShadow>[],
                      ),
                      child: Text(
                        option.label,
                        style: TextStyle(
                          fontFamily: NestFont.body,
                          fontSize: 13,
                          fontWeight: option == _system
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: option == _system
                              ? NestColor.penDeep
                              : NestColor.inkSoft,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            _DateRow(
              label: tr('Started'),
              value: _start,
              hint: tr('Required'),
              onTap: () => _pick(isStart: true),
            ),
            const SizedBox(height: 10),
            _DateRow(
              label: tr('Expected finish'),
              value: _end,
              hint: tr('Optional'),
              onTap: () => _pick(isStart: false),
              onClear: _end == null ? null : () => setState(() => _end = null),
            ),

            if (wouldBe != null) ...[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: NestColor.tintMint,
                  borderRadius: BorderRadius.circular(NestRadius.tile),
                ),
                child: Text(
                  trp('By these dates you are in semester {0} of {1}, and each one runs about {2} months.', [wouldBe, plan.count, (plan.semesterLengthDays / 30.44).round()]),
                  style: TextStyle(
                    fontFamily: NestFont.body,
                    fontSize: 13,
                    height: 1.45,
                    color: NestColor.mintDeep,
                  ),
                ),
              ),
            ],

            if (_problem != null) ...[
              const SizedBox(height: 14),
              Text(
                _problem!,
                style: t.bodySmall?.copyWith(color: NestColor.redDeep),
              ),
            ],

            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: Text(tr('Save')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.hint,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final String hint;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final shown = value == null
        ? hint
        : localDate('${_months[value!.month - 1]} ${value!.year}');

    return Material(
      color: NestColor.paper,
      borderRadius: BorderRadius.circular(NestRadius.tile),
      child: InkWell(
        borderRadius: BorderRadius.circular(NestRadius.tile),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: NestFont.body,
                  fontSize: 13.5,
                  color: NestColor.inkSoft,
                ),
              ),
              const Spacer(),
              Text(
                shown,
                style: TextStyle(
                  fontFamily: NestFont.display,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color:
                      value == null ? NestColor.inkFaint : NestColor.ink,
                ),
              ),
              if (onClear != null)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 17),
                  tooltip: tr('Clear'),
                  color: NestColor.inkFaint,
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 6),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 18, color: NestColor.inkFaint),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
