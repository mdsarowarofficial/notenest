import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/exam.dart';
import '../../models/note.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_countdown_ring.dart';
import '../../widgets/nest_empty_state.dart';
import '../../widgets/note_tile.dart';
import '../notes/note_detail.dart';
import 'calendar_page.dart';
import 'exam_form.dart';

/// Exam Mode. Requirement 12, and the Gantt's "Exam Mode, countdown,
/// progress tracking".
///
/// The screen answers three questions in the order a student asks them: how
/// long have I got, how far through am I, and what should I open next. The
/// third is the part that takes work — the order comes from [revisionOrder],
/// which is written and tested on its own in `models/exam.dart`.
class ExamPage extends StatefulWidget {
  const ExamPage({super.key});

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  final _repo = NoteRepository.instance;

  /// Which exam the screen is focused on. Null means "whichever is next",
  /// which is what it should be after a date is added or removed.
  int? _focusId;

  bool _showWholeQueue = false;
  bool _showPast = false;

  /// How many of the queue are listed before the "show the rest" row. Eight is
  /// about a screenful — enough to be useful, short enough that the student is
  /// not scrolling past their own revision plan to reach anything else.
  static const _queuePreview = 8;

  Exam? _focus(List<Exam> all) {
    if (all.isEmpty) return null;
    final id = _focusId;
    if (id != null) {
      for (final e in all) {
        if (e.id == id) return e;
      }
    }
    // Nothing chosen, or the chosen one was deleted: the soonest date that has
    // not happened yet, falling back to the most recent one that has.
    return _repo.nextExam ?? all.last;
  }

  Future<void> _addDate() async {
    final saved = await showExamForm(context);
    if (saved && mounted) setState(() => _focusId = null);
  }

  Future<void> _edit(Exam exam) async {
    final saved = await showExamForm(context, existing: exam);
    if (saved && mounted) setState(() => _focusId = null);
  }

  void _openCalendar() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CalendarPage()),
    );
  }

  Future<void> _openNote(Note note) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteDetailPage(noteId: note.id!)),
    );
  }

  /// The one-tap action the revision list exists for: say a note is done, or
  /// put a finished one back because it did not stick.
  Future<void> _toggleMastered(Note note) async {
    final next = note.status == StudyStatus.mastered
        ? StudyStatus.review
        : StudyStatus.mastered;
    await _repo.setStatus(note, next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final all = _repo.exams();

        if (all.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 90),
            child: NestEmptyState(
              icon: Icons.timer_rounded,
              title: 'No dates yet',
              message: 'Add an exam, a quiz or an assignment deadline. '
                  'NoteNest will count the days down and work out which notes '
                  'to revise first.',
              actionLabel: 'Add a date',
              onAction: _addDate,
            ),
          );
        }

        final exam = _focus(all)!;
        final upcoming = _repo.upcomingExams();
        final past = all.where((e) => e.isPast).toList().reversed.toList();

        final queue = _repo.revisionQueue(exam);
        final remaining =
            queue.where((n) => n.status != StudyStatus.mastered).length;
        final mastered = queue.length - remaining;
        final share = masteredShare(queue);
        final days = exam.daysAway;
        final perDay = dailyTarget(remaining: remaining, daysLeft: days);

        final subject =
            exam.subjectId == null ? null : _repo.subjectById(exam.subjectId!);
        final accent = subject?.color ?? NestColor.pen;

        final shown = _showWholeQueue
            ? queue
            : queue.take(_queuePreview).toList(growable: false);

        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 120),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Exam mode',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  onPressed: _openCalendar,
                  icon: const Icon(Icons.calendar_month_rounded),
                  tooltip: 'Academic calendar',
                ),
                IconButton(
                  onPressed: _addDate,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  tooltip: 'Add a date',
                ),
              ],
            ),
            const SizedBox(height: 2),

            // Which date the rest of the screen is about. Only worth showing
            // when there is a choice to make.
            if (upcoming.length > 1) ...[
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final e in upcoming)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _ExamChip(
                          exam: e,
                          selected: e.id == exam.id,
                          color: e.subjectId == null
                              ? NestColor.pen
                              : _repo.subjectById(e.subjectId!)?.color ??
                                  NestColor.pen,
                          onTap: () => setState(() => _focusId = e.id),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ] else
              const SizedBox(height: 10),

            _CountdownCard(
              exam: exam,
              subjectCode: subject?.code,
              accent: accent,
              days: days,
              progress: share,
              verdict: revisionVerdict(
                remaining: remaining,
                daysLeft: days,
                total: queue.length,
              ),
              onEdit: () => _edit(exam),
            ),

            if (queue.isNotEmpty) ...[
              const SizedBox(height: 18),
              _ProgressBlock(
                mastered: mastered,
                total: queue.length,
                share: share,
                accent: accent,
                perDay: perDay,
                days: days,
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                    child: Text('REVISE IN THIS ORDER', style: nestEyebrow),
                  ),
                  Text('${queue.length}', style: nestEyebrow),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Starred notes first, then the ones marked Review, then '
                'whatever you have not opened in longest.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              for (final note in shown)
                NoteTile(
                  note: note,
                  onTap: () => _openNote(note),
                  trailing: _MasterToggle(
                    note: note,
                    onTap: () => _toggleMastered(note),
                  ),
                ),
              if (queue.length > _queuePreview)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(
                      () => _showWholeQueue = !_showWholeQueue,
                    ),
                    child: Text(
                      _showWholeQueue
                          ? 'Show fewer'
                          : 'Show all ${queue.length}',
                    ),
                  ),
                ),
            ] else ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NestColor.card,
                  boxShadow: NestShadow.resting,
                  borderRadius: BorderRadius.circular(NestRadius.tile),
                ),
                child: Text(
                  subject == null
                      ? 'There are no notes to revise yet. Anything you write '
                          'will show up here in revision order.'
                      : 'No notes filed under ${subject.code} yet. Notes you '
                          'add to that subject will show up here.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],

            if (past.isNotEmpty) ...[
              const SizedBox(height: 24),
              InkWell(
                onTap: () => setState(() => _showPast = !_showPast),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'PAST DATES · ${past.length}',
                          style: nestEyebrow,
                        ),
                      ),
                      Icon(
                        _showPast
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: NestColor.inkSoft,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showPast)
                for (final e in past)
                  _PastRow(
                    exam: e,
                    onTap: () => setState(() => _focusId = e.id),
                    onEdit: () => _edit(e),
                  ),
            ],
          ],
        );
      },
    );
  }
}

/// The card at the top: the dial, the date, and one honest line about where
/// the revision stands.
class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.exam,
    required this.subjectCode,
    required this.accent,
    required this.days,
    required this.progress,
    required this.verdict,
    required this.onEdit,
  });

  final Exam exam;
  final String? subjectCode;
  final Color accent;
  final int days;
  final double progress;
  final String verdict;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final urgent = days >= 0 && days <= 3;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.card),
        // The one card on this screen you are meant to feel, so when the exam
        // is close it is lit from under in red rather than ringed in it. A
        // border says "boundary"; a glow says "this is the thing".
        boxShadow: urgent
            ? NestShadow.glow(NestColor.redPen)
            : NestShadow.resting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              NestCountdownRing(
                days: days,
                progress: progress,
                accent: accent,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: NestColor.o(accent, 0.2),
                            borderRadius:
                                BorderRadius.circular(NestRadius.pill),
                          ),
                          child: Text(
                            exam.kind.label.toUpperCase(),
                            style: nestEyebrow.copyWith(color: accent),
                          ),
                        ),
                        if (subjectCode != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              subjectCode!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nestEyebrow,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      exam.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      longDate(exam.date),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit this date',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: urgent ? NestColor.tintRed : NestColor.tintPen,
              borderRadius: BorderRadius.circular(NestRadius.tile),
            ),
            child: Row(
              children: [
                Icon(
                  urgent
                      ? Icons.priority_high_rounded
                      : Icons.insights_rounded,
                  size: 17,
                  color: urgent ? NestColor.redDeep : NestColor.penDeep,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    verdict,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          if (exam.hasReminder) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  exam.reminderIsDue
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  size: 15,
                  color: exam.reminderIsDue
                      ? NestColor.pen
                      : NestColor.inkFaint,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    exam.reminderIsDue
                        ? 'Reminder is showing on Today.'
                        : 'Reminder set for '
                            '${reminderLabel(exam.remindDays).toLowerCase()}.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "9 of 24 mastered", the bar, and today's target.
class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({
    required this.mastered,
    required this.total,
    required this.share,
    required this.accent,
    required this.perDay,
    required this.days,
  });

  final int mastered;
  final int total;
  final double share;
  final Color accent;
  final int perDay;
  final int days;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text('PROGRESS', style: nestEyebrow)),
            Text(
              '$mastered of $total mastered',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: share.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 10,
              backgroundColor: NestColor.paperDeep,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ),
        if (perDay > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.flag_outlined, size: 15, color: NestColor.pen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  days <= 0
                      ? 'All $perDay left for today.'
                      : 'Today: $perDay '
                          '${perDay == 1 ? 'note' : 'notes'} to stay on track.',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One of the exams across the top, when there is more than one coming.
class _ExamChip extends StatelessWidget {
  const _ExamChip({
    required this.exam,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final Exam exam;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? NestColor.o(color, 0.32) : NestColor.card,
          borderRadius: BorderRadius.circular(NestRadius.pill),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F1B1E2B),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                exam.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: NestColor.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              countdownLabel(exam.daysAway),
              style: nestEyebrow.copyWith(
                color: exam.daysAway <= 3 ? NestColor.redPen : NestColor.pen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tick at the end of a revision row.
class _MasterToggle extends StatelessWidget {
  const _MasterToggle({required this.note, required this.onTap});

  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = note.status == StudyStatus.mastered;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!done) StatusDot(status: note.status),
        IconButton(
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            done ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 22,
            color: done ? NestColor.mint : NestColor.inkFaint,
          ),
          tooltip: done ? 'Put back for review' : 'Mark mastered',
        ),
      ],
    );
  }
}

/// A date that has been and gone. Kept because "what did I sit last week" is
/// a fair question, and because deleting history for the student is not the
/// app's call.
class _PastRow extends StatelessWidget {
  const _PastRow({
    required this.exam,
    required this.onTap,
    required this.onEdit,
  });

  final Exam exam;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.history_rounded,
                size: 16, color: NestColor.inkFaint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exam.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: NestColor.inkSoft,
                    ),
                  ),
                  Text(
                    '${exam.kind.label} · '
                    '${countdownLabel(exam.daysAway)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onEdit,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.more_horiz_rounded, size: 18),
              tooltip: 'Edit or remove',
            ),
          ],
        ),
      ),
    );
  }
}
