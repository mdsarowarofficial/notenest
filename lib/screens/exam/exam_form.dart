import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/exam.dart';
import '../../theme/nest_theme.dart';
import '../../l10n/strings.dart';

/// Adds or edits a dated thing: an exam, a quiz, an assignment. Requirement 12.
///
/// Returns true when something was saved or removed, so the caller can refresh
/// without guessing.
Future<bool> showExamForm(
  BuildContext context, {
  Exam? existing,
  int? subjectId,
  DateTime? on,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: NestColor.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _ExamForm(
      existing: existing,
      subjectId: subjectId,
      on: on,
    ),
  );
  return saved ?? false;
}

class _ExamForm extends StatefulWidget {
  const _ExamForm({this.existing, this.subjectId, this.on});

  final Exam? existing;
  final int? subjectId;
  final DateTime? on;

  @override
  State<_ExamForm> createState() => _ExamFormState();
}

class _ExamFormState extends State<_ExamForm> {
  final _repo = NoteRepository.instance;
  final _title = TextEditingController();

  late DateTime _date;
  ExamKind _kind = ExamKind.exam;
  int? _subjectId;
  int? _remindDays;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title.text = e?.title ?? '';
    _date = e?.date ?? widget.on ?? atMidnight(DateTime.now());
    _kind = e?.kind ?? ExamKind.exam;
    _remindDays = e?.remindDays;
    _subjectId = e?.subjectId ??
        widget.subjectId ??
        (_repo.subjects().isNotEmpty ? _repo.subjects().first.id : null);
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// A sensible title when the student has not typed one — "CSE112 exam"
  /// reads better in a list than a blank row.
  String get _effectiveTitle {
    final typed = _title.text.trim();
    if (typed.isNotEmpty) return typed;
    final subject =
        _subjectId == null ? null : _repo.subjectById(_subjectId!);
    return subject == null
        ? _kind.label
        : trp('{0} {1}', [subject.code, _kind.label.toLowerCase()]);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // A year back covers "what did I sit", two years forward covers a
      // degree's worth of planning.
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() => _date = atMidnight(picked));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final existing = widget.existing;
      if (existing == null) {
        await _repo.addExam(
          title: _effectiveTitle,
          date: _date,
          subjectId: _subjectId,
          kind: _kind,
          remindDays: _remindDays,
        );
      } else {
        await _repo.updateExam(
          existing.copyWith(
            title: _effectiveTitle,
            date: _date,
            kind: _kind,
            subjectId: _subjectId,
            clearSubject: _subjectId == null,
            remindDays: _remindDays,
            clearReminder: _remindDays == null,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('That could not be saved. Try again.');
        });
      }
    }
  }

  Future<void> _delete() async {
    final exam = widget.existing;
    if (exam == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NestColor.card,
        title: Text(tr('Remove this date?')),
        content: Text(trp('{0} will be taken off your calendar. Your notes are not touched.', [exam.title])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('Remove')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _repo.deleteExam(exam);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _repo.subjects();
    final days = daysUntil(_date);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            22,
            18,
            22,
            22 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: NestColor.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.existing == null ? tr('Add a date') : tr('Edit this date'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 18),
              Text(tr('WHAT IS IT'), style: nestEyebrow),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kind in ExamKind.values)
                    _PlainChip(
                      label: kind.label,
                      selected: _kind == kind,
                      onTap: () => setState(() => _kind = kind),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(tr('WHEN'), style: nestEyebrow),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(NestRadius.tile),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: NestColor.paper,
                    borderRadius: BorderRadius.circular(NestRadius.tile),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_rounded,
                          size: 18, color: NestColor.pen),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          longDate(_date),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        countdownLabel(days).toUpperCase(),
                        style: nestEyebrow.copyWith(
                          color: days < 0
                              ? NestColor.inkFaint
                              : days <= 3
                                  ? NestColor.redPen
                                  : NestColor.pen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (subjects.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(tr('SUBJECT'), style: nestEyebrow),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: NestColor.paper,
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _subjectId,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(NestRadius.tile),
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(tr('Everything — all subjects'),
                              style: const TextStyle(fontSize: 14)),
                        ),
                        for (final s in subjects)
                          DropdownMenuItem<int?>(
                            value: s.id,
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: s.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    s.code,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _subjectId = v),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _subjectId == null
                      ? tr('Revision will cover every note you have.')
                      : tr('Revision will cover that subject only.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 18),
              Text(tr('REMIND ME'), style: nestEyebrow),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PlainChip(
                    label: reminderLabel(null),
                    selected: _remindDays == null,
                    onTap: () => setState(() => _remindDays = null),
                  ),
                  for (final lead in reminderChoices)
                    _PlainChip(
                      label: reminderLabel(lead),
                      selected: _remindDays == lead,
                      onTap: () => setState(() => _remindDays = lead),
                    ),
                ],
              ),
              if (_remindDays != null) ...[
                const SizedBox(height: 6),
                // Said plainly, because a reminder the student believes will
                // wake their phone and does not is worse than no reminder.
                Text(
                  trp('Shown inside NoteNest from {0}. It also rings from this phone when phone reminders are switched on in the notifications settings.', [reminderLabel(_remindDays).toLowerCase()]),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 18),
              Text(tr('CALL IT'), style: nestEyebrow),
              const SizedBox(height: 6),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: _effectiveTitle,
                  filled: true,
                  fillColor: NestColor.paper,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: NestColor.redPen),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  if (widget.existing != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _delete,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 54),
                          foregroundColor: NestColor.redPen,
                        ),
                        child: Text(tr('Remove')),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? tr('Saving…') : tr('Save')),
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
}

/// A chip that is on or off. Used for both the kind and the reminder lead, so
/// the two rows cannot drift apart visually.
class _PlainChip extends StatelessWidget {
  const _PlainChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? NestColor.tintPen : NestColor.paper,
          borderRadius: BorderRadius.circular(NestRadius.pill),
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

/// "Thursday, 12 March 2026" — written out, because a date a student is
/// planning around should not need decoding.
String longDate(DateTime d) {
  const days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return localDate("${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}");
}
