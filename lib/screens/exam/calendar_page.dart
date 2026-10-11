import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/exam.dart';
import '../../theme/nest_theme.dart';
import 'exam_form.dart';

/// The academic calendar. Requirement 12, and the Gantt's "academic calendar".
///
/// A month at a time, because that is the unit a semester is planned in. The
/// grid is built by hand rather than with a calendar package: a month is
/// arithmetic on `DateTime`, and a dependency for it would be a dependency to
/// keep updated for no gain.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, this.initialMonth});

  final DateTime? initialMonth;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final _repo = NoteRepository.instance;

  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final start = widget.initialMonth ?? DateTime.now();
    _month = DateTime(start.year, start.month);
    _selected = atMidnight(DateTime.now());
  }

  void _shift(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
  }

  void _jumpTo(DateTime day) {
    setState(() {
      _month = DateTime(day.year, day.month);
      _selected = atMidnight(day);
    });
  }

  Future<void> _addOnSelected() async {
    await showExamForm(context, on: _selected);
  }

  Future<void> _edit(Exam exam) async {
    await showExamForm(context, existing: exam);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Academic calendar')),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          final onSelected = _repo.examsOn(_selected);
          final upcoming = _repo.upcomingExams();

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
            children: [
              _MonthHeader(
                month: _month,
                onPrevious: () => _shift(-1),
                onNext: () => _shift(1),
                onToday: () => _jumpTo(DateTime.now()),
              ),
              const SizedBox(height: 10),
              const _WeekdayRow(),
              const SizedBox(height: 4),
              _MonthGrid(
                month: _month,
                selected: _selected,
                today: atMidnight(DateTime.now()),
                dotsFor: _dotsFor,
                onPick: (day) => setState(() => _selected = day),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      longDate(_selected),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addOnSelected,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (onSelected.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: NestColor.paper,
                    borderRadius: BorderRadius.circular(NestRadius.tile),
                  ),
                  child: Text(
                    'Nothing on this day.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else
                for (final exam in onSelected)
                  _ExamRow(
                    exam: exam,
                    color: _colorOf(exam),
                    subjectCode: _codeOf(exam),
                    onTap: () => _edit(exam),
                  ),
              if (upcoming.isNotEmpty) ...[
                const SizedBox(height: 26),
                const Text('COMING UP', style: nestEyebrow),
                const SizedBox(height: 4),
                for (final exam in upcoming)
                  _ExamRow(
                    exam: exam,
                    color: _colorOf(exam),
                    subjectCode: _codeOf(exam),
                    showCountdown: true,
                    onTap: () => _jumpTo(exam.date),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Color _colorOf(Exam exam) => exam.subjectId == null
      ? NestColor.pen
      : _repo.subjectById(exam.subjectId!)?.color ?? NestColor.pen;

  String? _codeOf(Exam exam) => exam.subjectId == null
      ? null
      : _repo.subjectById(exam.subjectId!)?.code;

  /// The coloured marks under a date. Capped at three, because a fourth dot in
  /// a cell that size is a smudge rather than information.
  List<Color> _dotsFor(DateTime day) {
    final exams = _repo.examsOn(day);
    return [for (final e in exams.take(3)) _colorOf(e)];
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Previous month',
        ),
        Expanded(
          child: GestureDetector(
            onTap: onToday,
            child: Center(
              child: Text(
                monthYear(month),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: 'Next month',
        ),
      ],
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Center(
              child: Text(
                labels[i],
                style: nestEyebrow.copyWith(
                  // Saturday and Sunday are not a weekend everywhere, but they
                  // are not a teaching day here either, so they are muted.
                  color: i >= 5 ? NestColor.inkFaint : NestColor.inkSoft,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.dotsFor,
    required this.onPick,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final List<Color> Function(DateTime) dotsFor;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    // Day 0 of the next month is the last day of this one — the standard way
    // to get a month's length without a table of 28/30/31 and a leap rule.
    final length = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month).weekday - 1; // Mon = 0

    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var d = 1; d <= length; d++)
        _DayCell(
          day: DateTime(month.year, month.month, d),
          selected: DateTime(month.year, month.month, d) == selected,
          isToday: DateTime(month.year, month.month, d) == today,
          dots: dotsFor(DateTime(month.year, month.month, d)),
          onTap: onPick,
        ),
    ];
    // Pad the last week so the final row keeps the same seven columns.
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }

    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(
        Row(
          children: [
            for (final cell in cells.sublist(i, i + 7)) Expanded(child: cell),
          ],
        ),
      );
    }

    return Column(children: rows);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.dots,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final List<Color> dots;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: () => onTap(day),
      radius: 26,
      child: SizedBox(
        height: 46,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? NestColor.pen : Colors.transparent,
                shape: BoxShape.circle,
                border: isToday && !selected
                    ? Border.all(color: NestColor.pen, width: 1.4)
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      selected || isToday ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : NestColor.ink,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final color in dots)
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamRow extends StatelessWidget {
  const _ExamRow({
    required this.exam,
    required this.color,
    required this.subjectCode,
    required this.onTap,
    this.showCountdown = false,
  });

  final Exam exam;
  final Color color;
  final String? subjectCode;
  final VoidCallback onTap;
  final bool showCountdown;

  @override
  Widget build(BuildContext context) {
    final meta = [
      exam.kind.label,
      if (subjectCode != null) subjectCode!,
      if (showCountdown) countdownLabel(exam.daysAway),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exam.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(meta, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: NestColor.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// "March 2026".
String monthYear(DateTime d) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${months[d.month - 1]} ${d.year}';
}
