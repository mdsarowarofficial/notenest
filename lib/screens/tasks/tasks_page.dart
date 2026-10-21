import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/note_repository.dart';
import '../../models/day_plan.dart';
import '../../models/exam.dart';
import '../../models/task.dart';
import '../../theme/nest_theme.dart';
import '../../l10n/strings.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
List<String> get _weekLetters => AppLanguage.instance.isBangla
    ? ['সো', 'ম', 'বু', 'বৃ', 'শু', 'শ', 'র']
    : ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// "Today", "Tomorrow", "Yesterday", otherwise "Wed 21 Oct".
String dayWord(DateTime day, {DateTime? now}) {
  final days = daysUntil(day, from: now ?? DateTime.now());
  if (days == 0) return tr('Today');
  if (days == 1) return tr('Tomorrow');
  if (days == -1) return tr('Yesterday');
  return localDate('${_weekdays[day.weekday - 1].substring(0, 3)} ${day.day} '
      '${_months[day.month - 1]}');
}

/// "Mon 12 Oct, 5:30 PM" — the due time as it reads in a list. A task saved
/// with no time of day shows only the day.
String taskDueLabel(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final days = daysUntil(at, from: n);
  final day = days == 0
      ? tr('Today')
      : days == 1
          ? tr('Tomorrow')
          : days == -1
              ? tr('Yesterday')
              : '${at.day} ${_months[at.month - 1]}';
  if (!hasRealClock(at)) return localDate(day);
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final m = at.minute.toString().padLeft(2, '0');
  return localDate('$day, $h:$m ${at.hour < 12 ? 'AM' : 'PM'}');
}

DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59);

/// Ink for the ruled lines: darker than [NestColor.rule], so a blank line is
/// still plainly a line to write on.
const _lineColor = Color(0xFFD3D7E4);
const _rowHeight = 46.0;

/// The small spaced-out headings of the planner sheet.
TextStyle get _sheetHeading => TextStyle(
  fontFamily: NestFont.body,
  fontSize: 12,
  fontWeight: FontWeight.w700,
  letterSpacing: ls(2),
  color: NestColor.inkSoft,
);

/// "TODAY’S URGENT TASKS", "TOMORROW’S URGENT TASKS", or for a day further
/// off "TASKS · WED 21 OCT".
String _taskHeading(DateTime d) {
  final word = dayWord(d).toUpperCase();
  const named = {'TODAY', 'TOMORROW', 'YESTERDAY'};
  return named.contains(word) ? trp('{0}’S URGENT TASKS', [word]) : trp('TASKS · {0}', [word]);
}

/// The to-do page, laid out like a printed planner sheet: the week's seven
/// day boxes, a title, the goals, the day's tasks and the next day's, a ruled
/// place for loose thoughts and a star rating for the day.
///
/// Every line of the sheet is real. A blank line is a place to type: tap it,
/// write, press Enter. A day with nothing on it shows the empty sheet, not an
/// apology. Each day keeps its own tasks (a task belongs to the day it is due),
/// so paging through the days reads back what was planned on each one.
///
/// Personal and private: every read and write in the repository is scoped to
/// the signed-in account.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.embedded = false, this.onBack});

  /// True when this is a tab of the home shell, which supplies the app bar and
  /// the navigation bar. False when pushed on its own (from a notification),
  /// where the page brings its own app bar.
  final bool embedded;

  /// Shown as a back arrow on the embedded page, since no tab of the bar leads
  /// back from it.
  final VoidCallback? onBack;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _repo = NoteRepository.instance;
  final _search = TextEditingController();
  final _thoughts = TextEditingController();
  Timer? _saveTimer;
  late DateTime _day;
  late DateTime _thoughtsDay;
  bool _searching = false;
  int? _subjectId;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _day = DateTime(n.year, n.month, n.day);
    _thoughtsDay = _day;
    _thoughts.text = _repo.dayLog(_day).thoughts;
  }

  @override
  void dispose() {
    _flushThoughts();
    _search.dispose();
    _thoughts.dispose();
    super.dispose();
  }

  void _flushThoughts() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_thoughts.text.trim() == _repo.dayLog(_thoughtsDay).thoughts.trim()) {
      return;
    }
    try {
      _repo.saveDayLog(_thoughtsDay, thoughts: _thoughts.text);
    } catch (_) {
      // Signed out while the page was closing; there is nothing to save to.
    }
  }

  void _goTo(DateTime day) {
    _flushThoughts();
    setState(() {
      _day = DateTime(day.year, day.month, day.day);
      _thoughtsDay = _day;
      _thoughts.text = _repo.dayLog(_day).thoughts;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) _goTo(picked);
  }

  List<Task> _scoped(Iterable<Task> list) => list
      .where((t) => _subjectId == null || t.subjectId == _subjectId)
      .toList();

  List<Task> _onDay(DateTime d) {
    final list = _scoped(
        _repo.tasks().where((t) => t.dueAt != null && sameDay(t.dueAt!, d)));
    list.sort(compareTasks);
    return list;
  }

  List<Task> _searchResults() {
    final q = _search.text.trim().toLowerCase();
    return _scoped(_repo.tasks().where((t) =>
        t.title.toLowerCase().contains(q) ||
        (t.description ?? '').toLowerCase().contains(q)));
  }

  /// Open tasks due on a day before today.
  List<Task> _late() {
    final n = DateTime.now();
    final start = DateTime(n.year, n.month, n.day);
    return _scoped(_repo.tasks().where(
        (t) => !t.isDone && t.dueAt != null && t.dueAt!.isBefore(start)));
  }

  Widget _searchField() => TextField(
        controller: _search,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: tr('Search tasks'),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
      );

  List<Widget> _actions() => [
        IconButton(
          tooltip: tr('New task with details'),
          icon: const Icon(Icons.add_task_rounded),
          onPressed: () => showTaskForm(context, dueOn: _day),
        ),
        IconButton(
          tooltip: _searching ? tr('Close search') : tr('Search tasks'),
          icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
          onPressed: () => setState(() {
            _searching = !_searching;
            _search.clear();
          }),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final embedded = widget.embedded;
    final body = ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final searching = _searching && _search.text.trim().isNotEmpty;
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(16, embedded ? 0 : 4, 16, embedded ? 130 : 40),
          children: [
            if (embedded)
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    if (widget.onBack != null && !_searching)
                      TextButton.icon(
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        label: Text(tr('Today')),
                      ),
                    if (_searching)
                      Expanded(child: _searchField())
                    else
                      const Spacer(),
                    ..._actions(),
                  ],
                ),
              ),
            _buildCourseFilter(),
            if (searching) _buildSearch() else _buildSheet(),
          ],
        );
      },
    );
    if (embedded) return body;
    return Scaffold(
      backgroundColor: NestColor.ground,
      appBar: AppBar(
        title: _searching ? _searchField() : Text(tr('To-do')),
        actions: _actions(),
      ),
      body: body,
    );
  }

  Widget _buildCourseFilter() {
    final subjects = _repo.subjects();
    if (subjects.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Center(
              child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(tr('COURSE'), style: nestEyebrow),
          )),
          for (final s in subjects)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
              child: FilterChip(
                label: Text(s.code),
                selected: _subjectId == s.id,
                onSelected: (on) =>
                    setState(() => _subjectId = on ? s.id : null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    final results = _searchResults();
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: _sheetDecoration,
      child: results.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr('No tasks match.'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          : Column(
              children: [
                for (final t in results)
                  TaskTile(key: ValueKey('hit-${t.id}'), task: t, ruled: true),
              ],
            ),
    );
  }

  static BoxDecoration get _sheetDecoration => BoxDecoration(
    color: NestColor.card,
    borderRadius: BorderRadius.circular(NestRadius.card),
    boxShadow: NestShadow.resting,
  );

  Widget _buildSheet() {
    final next = DateTime(_day.year, _day.month, _day.day + 1);
    final overdue = _late()..sort(compareTasks);
    final later = _scoped(_repo.tasks().where((t) {
      if (t.isDone) return false;
      final d = t.dueAt;
      return d == null || DateTime(d.year, d.month, d.day).isAfter(next);
    }))
      ..sort(compareTasks);
    final goals = _repo.goals();
    final openGoals = goals.where((g) => !g.isDone).length;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
      decoration: _sheetDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WeekBoxes(day: _day, repo: _repo, onPick: _goTo),
          const SizedBox(height: 18),
          _buildHeader(today),
          if (overdue.isNotEmpty && !_day.isBefore(today)) ...[
            const SizedBox(height: 14),
            _overdueBanner(overdue.length),
          ],
          if (overdue.isNotEmpty) ...[
            _heading(tr('OVERDUE'), count: overdue.length, accent: NestColor.redPen),
            for (final t in overdue)
              TaskTile(key: ValueKey('row-${t.id}'), task: t, ruled: true),
          ],
          _heading(_taskHeading(_day), count: _onDay(_day).length),
          _Lines(
            rows: [
              for (final t in _onDay(_day))
                TaskTile(key: ValueKey('row-${t.id}'), task: t, ruled: true),
            ],
            minLines: 6,
            hint: tr('Add a task'),
            onAdd: (title) =>
                _repo.addTask(title: title, dueAt: _endOfDay(_day)),
          ),
          _heading(tr('MY TOP 7 GOALS'), trailing: '$openGoals / $maxGoals open'),
          _Lines(
            rows: [
              for (var i = 0; i < goals.length; i++)
                _GoalRow(
                  key: ValueKey('goal-${goals[i].id}'),
                  goal: goals[i],
                  number: i + 1,
                  repo: _repo,
                ),
            ],
            minLines: maxGoals,
            numbered: true,
            canAdd: openGoals < maxGoals,
            hint: tr('Add a goal'),
            onAdd: (title) async {
              await _repo.addGoal(title);
            },
          ),
          _heading(_taskHeading(next), count: _onDay(next).length),
          _Lines(
            rows: [
              for (final t in _onDay(next))
                TaskTile(key: ValueKey('row-${t.id}'), task: t, ruled: true),
            ],
            minLines: 4,
            hint: tr('Plan ahead'),
            onAdd: (title) =>
                _repo.addTask(title: title, dueAt: _endOfDay(next)),
          ),
          _heading(trp('RANDOM THOUGHTS · {0}', [dayWord(_day).toUpperCase()])),
          _buildThoughts(),
          _heading(tr('PRODUCTIVITY')),
          _buildRating(),
          _heading(tr('SOMEDAY · NO DATE'), count: later.length),
          _Lines(
            rows: [
              for (final t in later)
                TaskTile(key: ValueKey('row-${t.id}'), task: t, ruled: true),
            ],
            minLines: 3,
            hint: tr('Ideas and far-off tasks'),
            onAdd: (title) => _repo.addTask(title: title),
          ),
        ],
      ),
    );
  }

  /// A spaced-out heading with an optional count badge and a note at the end.
  Widget _heading(String title,
      {int count = 0, Color? accent, String? trailing}) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 2),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _sheetHeading.copyWith(color: accent),
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: accent == null ? NestColor.tintPen : NestColor.tintRed,
                borderRadius: BorderRadius.circular(NestRadius.pill),
              ),
              child: Text(
                trp('{0}', [count]),
                style: t.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent == null ? NestColor.penDeep : NestColor.redDeep,
                ),
              ),
            ),
          ],
          if (trailing != null) ...[
            const Spacer(),
            Text(trailing, style: t.bodySmall),
          ],
        ],
      ),
    );
  }

  /// The title, the date (tap it to jump to any day) and how the day is going.
  /// Swiping sideways here moves a day at a time.
  Widget _buildHeader(DateTime today) {
    final t = Theme.of(context).textTheme;
    final isToday = sameDay(_day, today);
    final tasks = _onDay(_day);
    final done = tasks.where((x) => x.isDone).length;
    final week = weekOf(_day);
    final weekTasks = _scoped(_repo.tasks().where(
        (x) => x.dueAt != null && week.any((d) => sameDay(d, x.dueAt!))));
    final weekDone = weekTasks.where((x) => x.isDone).length;
    final streak = doneStreak(_repo.tasks(), today);
    final String line;
    if (tasks.isEmpty) {
      line = tr('A clear page. Tap a line to add the first task.');
    } else if (done == tasks.length) {
      line = trp('All {0} done. Nice work.', [done]);
    } else {
      line = trp('{0} of {1} done', [done, tasks.length]);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 250) return;
        _goTo(DateTime(_day.year, _day.month, _day.day + (v < 0 ? 1 : -1)));
      },
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              tr('TO DO LIST'),
              maxLines: 1,
              style: TextStyle(
                fontFamily: NestFont.display,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: ls(6),
                color: NestColor.ink,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                tooltip: tr('Previous day'),
                onPressed: () =>
                    _goTo(DateTime(_day.year, _day.month, _day.day - 1)),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Center(
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tr('Date'), style: t.bodySmall),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.only(bottom: 2),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                      color: NestColor.ink, width: 1),
                                ),
                              ),
                              child: Text(
                                localDate(
                                    '${_weekdays[_day.weekday - 1].substring(0, 3)}, '
                                    '${_day.day} ${_months[_day.month - 1]} '
                                    '${_day.year}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.titleSmall,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.edit_calendar_rounded,
                              size: 18, color: NestColor.pen),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('Next day'),
                onPressed: () =>
                    _goTo(DateTime(_day.year, _day.month, _day.day + 1)),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          if (!isToday)
            TextButton.icon(
              onPressed: () => _goTo(today),
              icon: const Icon(Icons.today_rounded, size: 18),
              label: Text(tr('Back to today')),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(line, style: t.bodySmall)),
              if (streak > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: NestColor.tintWarm,
                    borderRadius: BorderRadius.circular(NestRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_fire_department_rounded,
                          size: 15, color: NestColor.warmDeep),
                      const SizedBox(width: 3),
                      Text(
                        trp('{0}-day streak', [streak]),
                        style: t.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: NestColor.warmDeep,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(NestRadius.pill),
              child: LinearProgressIndicator(
                value: done / tasks.length,
                minHeight: 7,
                backgroundColor: NestColor.paper,
                color: NestColor.mint,
              ),
            ),
          ],
          if (weekTasks.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                trp('This week: {0} of {1} done', [weekDone, weekTasks.length]),
                style: t.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _overdueBanner(int count) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: NestColor.tintRed,
        borderRadius: BorderRadius.circular(NestRadius.chip),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              trp('{0} overdue', [count]),
              style: t.bodySmall?.copyWith(
                color: NestColor.redDeep,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final n = await _repo.moveOverdueTo(_day);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(trp('Moved {0} {1} to {2}.', [n, n == 1 ? tr('task') : tr('tasks'), dayWord(_day).toLowerCase()])),
              ));
            },
            style: TextButton.styleFrom(foregroundColor: NestColor.redDeep),
            child: Text(trp('Move to {0}', [dayWord(_day).toLowerCase()])),
          ),
        ],
      ),
    );
  }

  /// Ruled writing space: the lines are drawn behind the text, one text line
  /// per rule.
  Widget _buildThoughts() {
    const lineHeight = 34.0;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: CustomPaint(
        painter: const _RulePainter(lineHeight: lineHeight),
        child: TextField(
          controller: _thoughts,
          minLines: 6,
          maxLines: null,
          maxLength: 2000,
          buildCounter: (_,
                  {required currentLength, required isFocused, maxLength}) =>
              null,
          textCapitalization: TextCapitalization.sentences,
          strutStyle: const StrutStyle(
            fontSize: 15,
            height: lineHeight / 15,
            forceStrutHeight: true,
          ),
          style: TextStyle(
            fontFamily: NestFont.body,
            fontSize: 15,
            color: NestColor.ink,
          ),
          onChanged: (_) {
            _saveTimer?.cancel();
            _saveTimer = Timer(const Duration(milliseconds: 700), () {
              _flushThoughts();
            });
          },
          decoration: InputDecoration(
            hintText: tr('Ideas, worries, things to remember…'),
            isDense: true,
            filled: false,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }

  /// Five circled stars, as on the printed sheet. Tapping the current rating
  /// again clears it.
  Widget _buildRating() {
    final rating = _repo.dayLog(_day).rating;
    final words = [tr('Tap a star'), 'Rough', 'Meh', 'Okay', 'Good', 'Great'];
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 1; i <= 5; i++)
              Semantics(
                button: true,
                selected: i <= rating,
                label: trp('{0} star{1}', [i, i == 1 ? '' : 's']),
                child: InkResponse(
                  radius: 30,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _repo.saveDayLog(_day, rating: rating == i ? 0 : i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= rating ? NestColor.tintWarm : Colors.transparent,
                      border: Border.all(
                        color:
                            i <= rating ? NestColor.warmDeep : NestColor.inkFaint,
                        width: 1.6,
                      ),
                    ),
                    child: Icon(
                      i <= rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 26,
                      color: i <= rating
                          ? const Color(0xFFF2B600)
                          : NestColor.inkFaint,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Center(child: Text(words[rating], style: t.bodySmall)),
      ],
    );
  }
}

/// Horizontal rules every [lineHeight] pixels, ending each text line.
class _RulePainter extends CustomPainter {
  const _RulePainter({required this.lineHeight});

  final double lineHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _lineColor
      ..strokeWidth = 1;
    for (var y = lineHeight - 6; y <= size.height; y += lineHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_RulePainter old) => old.lineHeight != lineHeight;
}

/// Monday to Sunday of the chosen week as seven small boxes, like the tabs at
/// the top of a printed planner. A dot marks a day with tasks: indigo while
/// something is open, green once all of it is done; a grey dot means only a
/// note or a rating.
class _WeekBoxes extends StatelessWidget {
  const _WeekBoxes(
      {required this.day, required this.repo, required this.onPick});

  final DateTime day;
  final NoteRepository repo;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final week = weekOf(day);
    final now = DateTime.now();
    final tasks = repo.tasks();
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(builder: (context) {
              final d = week[i];
              final selected = sameDay(d, day);
              final today = sameDay(d, now);
              final mine = tasks
                  .where((x) => x.dueAt != null && sameDay(x.dueAt!, d))
                  .toList();
              final open = mine.any((x) => !x.isDone);
              final noted = mine.isEmpty && !repo.dayLog(d).isEmpty;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: localDate('${_weekdays[i]} ${d.day}'),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onPick(d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 60,
                      decoration: BoxDecoration(
                        color: selected ? NestColor.pen : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? NestColor.pen
                              : today
                                  ? NestColor.pen
                                  : const Color(0xFFB9BECE),
                          width: today && !selected ? 1.8 : 1.2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _weekLetters[i],
                            style: t.bodySmall?.copyWith(
                              color: selected
                                  ? NestColor.penPale
                                  : NestColor.inkMeta,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          Text(
                            trp('{0}', [d.day]),
                            style: t.titleSmall?.copyWith(
                              color: selected ? Colors.white : null,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: mine.isEmpty
                                  ? (noted
                                      ? NestColor.inkFaint
                                      : Colors.transparent)
                                  : open
                                      ? (selected
                                          ? NestColor.highlight
                                          : NestColor.pen)
                                      : NestColor.mint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }
}

/// One ruled line of the sheet: a mark at the start, then the content, over a
/// hairline.
class _RuledRow extends StatelessWidget {
  const _RuledRow({required this.leading, required this.child, this.onTap});

  final Widget leading;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _lineColor)),
      ),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _rowHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The filled rows of a section, then a live line to type on, then empty lines
/// up to [minLines] so a quiet day still looks like a page. Tapping any empty
/// line focuses the live one.
class _Lines extends StatefulWidget {
  const _Lines({
    required this.rows,
    required this.minLines,
    required this.hint,
    required this.onAdd,
    this.canAdd = true,
    this.numbered = false,
  });

  final List<Widget> rows;
  final int minLines;
  final String hint;
  final Future<void> Function(String title) onAdd;
  final bool canAdd;

  /// Empty lines carry a number (goals) rather than an empty tick box.
  final bool numbered;

  @override
  State<_Lines> createState() => _LinesState();
}

class _LinesState extends State<_Lines> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Widget _mark(int index) => widget.numbered
      ? Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _lineColor, width: 2),
          ),
          child: Text(
            trp('{0}', [index + 1]),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: NestColor.inkFaint,
            ),
          ),
        )
      : Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _lineColor, width: 1.8),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final filled = widget.rows.length;
    final used = filled + (widget.canAdd ? 1 : 0);
    final blanks = widget.minLines > used ? widget.minLines - used : 0;
    return Column(
      children: [
        ...widget.rows,
        if (widget.canAdd)
          _LineInput(
            key: const ValueKey('line-input'),
            focus: _focus,
            hint: widget.hint,
            onAdd: widget.onAdd,
            mark: _mark(filled),
          ),
        for (var i = 0; i < blanks; i++)
          GestureDetector(
            key: ValueKey('blank-$i'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.canAdd ? _focus.requestFocus : null,
            child: _RuledRow(
              leading: _mark(used + i),
              child: const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}

/// The live line: type, press Enter, and the next task can follow at once.
/// Text left in the line when focus moves away is added rather than lost.
class _LineInput extends StatefulWidget {
  const _LineInput({
    super.key,
    required this.focus,
    required this.hint,
    required this.onAdd,
    required this.mark,
  });

  final FocusNode focus;
  final String hint;
  final Future<void> Function(String title) onAdd;
  final Widget mark;

  @override
  State<_LineInput> createState() => _LineInputState();
}

class _LineInputState extends State<_LineInput> {
  final _c = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_onFocus);
    _c.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    widget.focus.removeListener(_onFocus);
    _c.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!widget.focus.hasFocus && _c.text.trim().isNotEmpty) {
      _submit(keepFocus: false);
    }
  }

  Future<void> _submit({bool keepFocus = true}) async {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    _c.clear();
    await widget.onAdd(text);
    if (keepFocus && mounted) widget.focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _RuledRow(
      leading: widget.mark,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _c,
              focusNode: widget.focus,
              maxLength: 120,
              buildCounter: (_,
                      {required currentLength, required isFocused, maxLength}) =>
                  null,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onEditingComplete: _submit,
              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: t.bodyMedium?.copyWith(color: NestColor.inkFaint),
                isDense: true,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          if (_c.text.trim().isNotEmpty)
            IconButton(
              tooltip: tr('Add'),
              visualDensity: VisualDensity.compact,
              onPressed: _submit,
              icon: Icon(Icons.arrow_upward_rounded,
                  color: NestColor.pen),
            ),
        ],
      ),
    );
  }
}

Future<void> _editGoal(
    BuildContext context, NoteRepository repo, Goal g) async {
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (_) => _GoalDialog(initial: g.title),
  );
  if (result == null) return;
  final (action, text) = result;
  if (action == 'delete') {
    await repo.deleteGoal(g);
  } else if (action == 'save' && text.trim().isNotEmpty) {
    await repo.updateGoal(g.copyWith(title: text.trim()));
  }
}

/// The edit-goal dialog. It owns its controller: disposing one from the
/// caller as soon as the dialog closes happens while the dialog is still
/// animating out and its field is still being built.
class _GoalDialog extends StatefulWidget {
  const _GoalDialog({required this.initial});

  final String initial;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NestColor.card,
      title: Text(tr('Edit goal')),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ('delete', _c.text)),
          style: TextButton.styleFrom(foregroundColor: NestColor.redPen),
          child: Text(tr('Delete')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ('save', _c.text)),
          child: Text(tr('Save')),
        ),
      ],
    );
  }
}

/// A goal on its numbered line: tap the circle when it is reached, tap the
/// line to rename or remove it.
class _GoalRow extends StatelessWidget {
  const _GoalRow({
    super.key,
    required this.goal,
    required this.number,
    required this.repo,
  });

  final Goal goal;
  final int number;
  final NoteRepository repo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _RuledRow(
      onTap: () => _editGoal(context, repo, goal),
      leading: _TickCircle(
        done: goal.isDone,
        color: NestColor.pen,
        label: trp('{0}', [number]),
        onTap: () {
          HapticFeedback.selectionClick();
          repo.setGoalDone(goal, !goal.isDone);
        },
      ),
      child: Text(
        goal.title,
        style: t.titleSmall?.copyWith(
          decoration: goal.isDone ? TextDecoration.lineThrough : null,
          color: goal.isDone ? NestColor.inkFaint : null,
        ),
      ),
    );
  }
}

/// A round tick: empty (or numbered) until done, then green with a check.
class _TickCircle extends StatelessWidget {
  const _TickCircle({
    required this.done,
    required this.color,
    required this.onTap,
    this.label,
  });

  final bool done;
  final Color color;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: done,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? NestColor.mint : Colors.transparent,
            border: Border.all(
              color: done ? NestColor.mint : color,
              width: 2,
            ),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
              : label == null
                  ? null
                  : Text(
                      label!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
        ),
      ),
    );
  }
}

/// A square tick for the ruled planner lines: an outline until done, then
/// green with a check. The outline takes the task's priority colour.
class _TickBox extends StatelessWidget {
  const _TickBox({required this.done, required this.color, required this.onTap});

  final bool done;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: done,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: done ? NestColor.mint : Colors.transparent,
            border: Border.all(color: done ? NestColor.mint : color, width: 1.8),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

/// Deletes a task and offers Undo.
Future<void> _deleteWithUndo(BuildContext context, Task task) async {
  final repo = NoteRepository.instance;
  final messenger = ScaffoldMessenger.of(context);
  await repo.deleteTask(task);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(tr('Task deleted')),
    action: SnackBarAction(
      label: tr('Undo'),
      onPressed: () async {
        final back = await repo.addTask(
          title: task.title,
          description: task.description,
          dueAt: task.dueAt,
          priority: task.priority,
          subjectId: task.subjectId,
          inProgress: task.inProgress,
        );
        if (task.isDone) await repo.setTaskDone(back, true);
      },
    ),
  ));
}

/// Moves an open task to the day after the one it is on; an overdue one comes
/// to today instead, since a day after a missed day is still missed.
Future<void> _pushToNextDay(Task task) {
  final now = DateTime.now();
  final due = task.dueAt;
  final DateTime to;
  if (due == null || task.isOverdue()) {
    to = DateTime(now.year, now.month, now.day, 23, 59);
  } else {
    to = DateTime(due.year, due.month, due.day + 1, due.hour, due.minute);
  }
  return NoteRepository.instance.updateTask(task.copyWith(dueAt: to));
}

/// One task row: tap the circle to complete, tap the row to edit, swipe right
/// to complete or left to delete (with Undo).
///
/// [ruled] draws it as a line of the planner sheet — a square tick, a hairline
/// underneath and a menu to push it a day — instead of the soft card used on
/// the Today page.
class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, this.ruled = false});

  final Task task;
  final bool ruled;

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;
    final t = Theme.of(context).textTheme;
    final overdue = task.isOverdue();
    final subject =
        task.subjectId == null ? null : repo.subjectById(task.subjectId!);
    final ringColor = switch (task.priority) {
      TaskPriority.high => NestColor.redPen,
      TaskPriority.normal => NestColor.inkFaint,
      TaskPriority.low => NestColor.pen,
    };

    Widget chip(String text, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(NestRadius.pill),
          ),
          child: Text(
            text,
            style: t.bodySmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        );

    final chips = <Widget>[
      if (task.dueAt != null && (hasRealClock(task.dueAt!) || overdue))
        chip(
          taskDueLabel(task.dueAt!),
          overdue ? NestColor.tintRed : NestColor.paper,
          overdue ? NestColor.redDeep : NestColor.inkSoft,
        ),
      if (subject != null)
        chip(subject.code, NestColor.tintPen, NestColor.penDeep),
      if (task.inProgress && !task.isDone)
        chip(tr('In progress'), NestColor.tintWarm, NestColor.warmDeep),
      if (task.priority == TaskPriority.high && !task.isDone)
        chip(tr('High'), NestColor.tintRed, NestColor.redDeep),
    ];

    final gap = ruled ? 0.0 : 6.0;

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.titleSmall?.copyWith(
            decoration: task.isDone ? TextDecoration.lineThrough : null,
            color: task.isDone ? NestColor.inkFaint : null,
          ),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: chips),
        ],
      ],
    );

    void toggle() {
      HapticFeedback.selectionClick();
      repo.setTaskDone(task, !task.isDone);
    }

    return Dismissible(
      key: ValueKey('task-${task.id}'),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: EdgeInsets.only(bottom: gap),
        decoration: BoxDecoration(
          color: NestColor.tintMint,
          borderRadius: BorderRadius.circular(NestRadius.chip),
        ),
        child: Icon(
          task.isDone ? Icons.undo_rounded : Icons.check_rounded,
          color: NestColor.mintDeep,
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: EdgeInsets.only(bottom: gap),
        decoration: BoxDecoration(
          color: NestColor.tintRed,
          borderRadius: BorderRadius.circular(NestRadius.chip),
        ),
        child:
            Icon(Icons.delete_outline_rounded, color: NestColor.redDeep),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await repo.setTaskDone(task, !task.isDone);
          return false;
        }
        await _deleteWithUndo(context, task);
        return false;
      },
      child: ruled
          ? _RuledRow(
              onTap: () => showTaskForm(context, existing: task),
              leading: _TickBox(
                done: task.isDone,
                color: ringColor,
                onTap: toggle,
              ),
              child: Row(
                children: [
                  Expanded(child: title),
                  PopupMenuButton<String>(
                    tooltip: tr('More'),
                    icon: Icon(Icons.more_horiz_rounded,
                        color: NestColor.inkFaint),
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      switch (v) {
                        case 'push':
                          _pushToNextDay(task);
                        case 'edit':
                          showTaskForm(context, existing: task);
                        case 'delete':
                          _deleteWithUndo(context, task);
                      }
                    },
                    itemBuilder: (_) => [
                      if (!task.isDone)
                        PopupMenuItem(
                          value: 'push',
                          child: Text(overdue || task.dueAt == null
                              ? tr('Move to today')
                              : tr('Push to next day')),
                        ),
                      PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                      PopupMenuItem(
                          value: 'delete', child: Text(tr('Delete'))),
                    ],
                  ),
                ],
              ),
            )
          : Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: NestColor.ground,
                borderRadius: BorderRadius.circular(NestRadius.chip),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(NestRadius.chip),
                onTap: () => showTaskForm(context, existing: task),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: _TickCircle(
                          done: task.isDone,
                          color: ringColor,
                          onTap: toggle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: title),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// Adds or edits a task in a bottom sheet — one screen, no wizard.
Future<bool> showTaskForm(
  BuildContext context, {
  Task? existing,
  int? subjectId,
  DateTime? dueOn,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: NestColor.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) =>
        _TaskForm(existing: existing, subjectId: subjectId, dueOn: dueOn),
  );
  return saved ?? false;
}

class _TaskForm extends StatefulWidget {
  const _TaskForm({this.existing, this.subjectId, this.dueOn});

  final Task? existing;
  final int? subjectId;

  /// The day a new task starts out due on.
  final DateTime? dueOn;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  final _repo = NoteRepository.instance;
  final _title = TextEditingController();
  final _desc = TextEditingController();
  DateTime? _due;
  TaskPriority _priority = TaskPriority.normal;
  bool _inProgress = false;
  int? _subjectId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title.text = e?.title ?? '';
    _desc.text = e?.description ?? '';
    _due = e?.dueAt ?? (widget.dueOn == null ? null : _endOfDay(widget.dueOn!));
    _priority = e?.priority ?? TaskPriority.normal;
    _inProgress = e?.inProgress ?? false;
    _subjectId = e?.subjectId ?? widget.subjectId;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3, 12, 31),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due ?? now),
    );
    if (!mounted) return;
    setState(() {
      _due = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 23,
        time?.minute ?? 59,
      );
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _error = tr('Give the task a title.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final e = widget.existing;
      if (e == null) {
        await _repo.addTask(
          title: _title.text,
          description: _desc.text,
          dueAt: _due,
          priority: _priority,
          subjectId: _subjectId,
          inProgress: _inProgress,
        );
      } else {
        final desc = _desc.text.trim();
        await _repo.updateTask(e.copyWith(
          title: _title.text.trim(),
          description: desc,
          clearDescription: desc.isEmpty,
          dueAt: _due,
          clearDue: _due == null,
          priority: _priority,
          inProgress: _inProgress,
          subjectId: _subjectId,
          clearSubject: _subjectId == null,
        ));
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
    final task = widget.existing;
    if (task == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: NestColor.card,
        title: Text(tr('Delete this task?')),
        content: Text(trp('"{0}" will be removed.', [task.title])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteTask(task);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _repo.subjects();
    return SafeArea(
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
            Text(
              widget.existing == null ? tr('New task') : tr('Edit task'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              decoration: InputDecoration(labelText: tr('Title')),
            ),
            TextField(
              controller: _desc,
              maxLines: 3,
              maxLength: 1000,
              decoration:
                  InputDecoration(labelText: tr('Details (optional)')),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDue,
                    icon: const Icon(Icons.event_rounded),
                    label: Text(
                      _due == null ? tr('Set due date') : taskDueLabel(_due!),
                    ),
                  ),
                ),
                if (_due != null)
                  IconButton(
                    tooltip: tr('Clear due date'),
                    onPressed: () => setState(() => _due = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(tr('PRIORITY'), style: nestEyebrow),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final p in TaskPriority.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: _priority == p,
                    onSelected: (_) => setState(() => _priority = p),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('In progress')),
              value: _inProgress,
              onChanged: (v) => setState(() => _inProgress = v),
            ),
            if (subjects.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(tr('COURSE'), style: nestEyebrow),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(tr('None')),
                    selected: _subjectId == null,
                    onSelected: (_) => setState(() => _subjectId = null),
                  ),
                  for (final s in subjects)
                    ChoiceChip(
                      label: Text(s.code),
                      selected: _subjectId == s.id,
                      onSelected: (_) => setState(() => _subjectId = s.id),
                    ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: NestColor.redPen),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                if (widget.existing != null)
                  TextButton(
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                      foregroundColor: NestColor.redPen,
                    ),
                    child: Text(tr('Delete')),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? tr('Saving…') : tr('Save')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The Today dashboard section: overdue and today's open tasks, a quick add,
/// and a way into the full list. Hidden detail stays on the tasks page.
class TasksCard extends StatelessWidget {
  const TasksCard({super.key, this.onSeeAll});

  /// Switches to the To-do tab. Without it the page is pushed on its own.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;
    final t = Theme.of(context).textTheme;
    final focus = [...repo.overdueTasks, ...repo.tasksDueToday];
    final shown = focus.take(3).toList();
    final more = focus.length - shown.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NestColor.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(tr('To-do'), style: t.titleMedium)),
              IconButton(
                tooltip: tr('Add a task'),
                onPressed: () => showTaskForm(context),
                icon: const Icon(Icons.add_rounded),
              ),
              TextButton(
                onPressed: onSeeAll ??
                    () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const TasksPage()),
                        ),
                child: Text(tr('See all')),
              ),
            ],
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, right: 8),
              child: Text(
                repo.openTasks.isEmpty
                    ? tr('Nothing planned. Add a task to keep track of work.')
                    : trp('Nothing due today. {0} open in total.', [repo.openTasks.length]),
                style: t.bodySmall,
              ),
            )
          else ...[
            for (final task in shown) TaskTile(task: task),
            if (more > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(trp('+ {0} more', [more]), style: t.bodySmall),
              ),
          ],
        ],
      ),
    );
  }
}
