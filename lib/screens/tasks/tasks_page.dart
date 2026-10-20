import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/note_repository.dart';
import '../../models/day_plan.dart';
import '../../models/exam.dart';
import '../../models/task.dart';
import '../../theme/nest_theme.dart';

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
const _weekLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// "Today", "Tomorrow", "Yesterday", otherwise "Wed 21 Oct".
String dayWord(DateTime day, {DateTime? now}) {
  final days = daysUntil(day, from: now ?? DateTime.now());
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days == -1) return 'Yesterday';
  return '${_weekdays[day.weekday - 1].substring(0, 3)} ${day.day} '
      '${_months[day.month - 1]}';
}

/// "Mon 12 Oct, 5:30 PM" — the due time as it reads in a list. A task saved
/// with no time of day shows only the day.
String taskDueLabel(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final days = daysUntil(at, from: n);
  final day = days == 0
      ? 'Today'
      : days == 1
          ? 'Tomorrow'
          : days == -1
              ? 'Yesterday'
              : '${at.day} ${_months[at.month - 1]}';
  if (!hasRealClock(at)) return day;
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final m = at.minute.toString().padLeft(2, '0');
  return '$day, $h:$m ${at.hour < 12 ? 'AM' : 'PM'}';
}

DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59);

/// The to-do page: a week strip, goals, the chosen day's tasks and the next
/// day's, a place for loose thoughts, and a star rating for the day. Personal
/// and private: every read and write in the repository is scoped to the
/// signed-in account.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NestColor.ground,
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search tasks',
                  border: InputBorder.none,
                  filled: false,
                ),
              )
            : const Text('To-do'),
        actions: [
          IconButton(
            tooltip: 'New task with details',
            icon: const Icon(Icons.add_task_rounded),
            onPressed: () => showTaskForm(context, dueOn: _day),
          ),
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searching = !_searching;
              _search.clear();
            }),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          final searching = _searching && _search.text.trim().isNotEmpty;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              if (!searching) ...[
                _WeekStrip(day: _day, repo: _repo, onPick: _goTo),
                const SizedBox(height: 14),
                _buildProgress(),
              ],
              _buildCourseFilter(),
              if (searching) ..._buildSearch() else ..._buildSections(),
            ],
          );
        },
      ),
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
          const Center(
              child: Padding(
            padding: EdgeInsets.only(right: 10),
            child: Text('COURSE', style: nestEyebrow),
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

  Widget _buildProgress() {
    final tasks = _onDay(_day);
    final done = tasks.where((t) => t.isDone).length;
    final t = Theme.of(context).textTheme;
    final word = dayWord(_day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final late = _late();
    final String line;
    if (tasks.isEmpty) {
      line = 'Nothing planned for this day.';
    } else if (done == tasks.length) {
      line = 'All $done done. Nice work.';
    } else {
      line = '$done of ${tasks.length} done';
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.tile),
        boxShadow: NestShadow.resting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sameDay(_day, today)
                ? '${_weekdays[_day.weekday - 1]}, ${_day.day} '
                    '${_months[_day.month - 1]}'
                : '$word · ${_weekdays[_day.weekday - 1]}',
            style: t.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(line, style: t.bodySmall),
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(NestRadius.pill),
              child: LinearProgressIndicator(
                value: done / tasks.length,
                minHeight: 8,
                backgroundColor: NestColor.paper,
                color: NestColor.mint,
              ),
            ),
          ],
          if (late.isNotEmpty && !_day.isBefore(today)) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                color: NestColor.tintRed,
                borderRadius: BorderRadius.circular(NestRadius.chip),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${late.length} overdue',
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
                        content: Text(
                            'Moved $n ${n == 1 ? 'task' : 'tasks'} to ${dayWord(_day).toLowerCase()}.'),
                      ));
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: NestColor.redDeep,
                    ),
                    child: Text('Move to ${dayWord(_day).toLowerCase()}'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Open tasks due on a day before today.
  List<Task> _late() {
    final n = DateTime.now();
    final start = DateTime(n.year, n.month, n.day);
    return _scoped(_repo.tasks().where(
        (t) => !t.isDone && t.dueAt != null && t.dueAt!.isBefore(start)));
  }

  List<Widget> _buildSearch() {
    final results = _searchResults();
    if (results.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No tasks match.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ];
    }
    return [for (final t in results) TaskTile(task: t)];
  }

  List<Widget> _buildSections() {
    final next = DateTime(_day.year, _day.month, _day.day + 1);
    final late = _late()..sort(compareTasks);
    final later = _scoped(_repo.tasks().where((t) {
      if (t.isDone) return false;
      final d = t.dueAt;
      return d == null || DateTime(d.year, d.month, d.day).isAfter(next);
    }))
      ..sort(compareTasks);
    return [
      _GoalsCard(repo: _repo),
      const SizedBox(height: 14),
      if (late.isNotEmpty) ...[
        _Section(
          title: 'OVERDUE',
          count: late.length,
          accent: NestColor.redPen,
          children: [for (final t in late) TaskTile(task: t)],
        ),
        const SizedBox(height: 14),
      ],
      _Section(
        title: '${dayWord(_day).toUpperCase()}’S TASKS',
        count: _onDay(_day).length,
        emptyText: 'Nothing planned. Add the first task below.',
        quickAdd: _QuickAdd(
          hint: 'Add a task for ${dayWord(_day).toLowerCase()}',
          onAdd: (title) => _repo.addTask(title: title, dueAt: _endOfDay(_day)),
        ),
        children: [for (final t in _onDay(_day)) TaskTile(task: t)],
      ),
      const SizedBox(height: 14),
      _Section(
        title: '${dayWord(next).toUpperCase()}’S TASKS',
        count: _onDay(next).length,
        emptyText: 'Nothing planned yet.',
        quickAdd: _QuickAdd(
          hint: 'Add a task for ${dayWord(next).toLowerCase()}',
          onAdd: (title) => _repo.addTask(title: title, dueAt: _endOfDay(next)),
        ),
        children: [for (final t in _onDay(next)) TaskTile(task: t)],
      ),
      const SizedBox(height: 14),
      _Section(
        title: 'LATER & NO DATE',
        count: later.length,
        emptyText: 'Ideas and far-off tasks go here.',
        quickAdd: _QuickAdd(
          hint: 'Add a task with no date',
          onAdd: (title) => _repo.addTask(title: title),
        ),
        children: [for (final t in later) TaskTile(task: t)],
      ),
      const SizedBox(height: 14),
      _buildThoughts(),
      const SizedBox(height: 14),
      _buildRating(),
    ];
  }

  Widget _buildThoughts() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.tile),
        boxShadow: NestShadow.resting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RANDOM THOUGHTS · ${dayWord(_day).toUpperCase()}',
              style: nestEyebrow),
          const SizedBox(height: 10),
          TextField(
            controller: _thoughts,
            minLines: 4,
            maxLines: 10,
            maxLength: 2000,
            buildCounter: (_,
                    {required currentLength, required isFocused, maxLength}) =>
                null,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              _saveTimer?.cancel();
              _saveTimer = Timer(const Duration(milliseconds: 700), () {
                _flushThoughts();
              });
            },
            decoration: const InputDecoration(
              hintText: 'Ideas, worries, things to remember…',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRating() {
    final rating = _repo.dayLog(_day).rating;
    const words = ['Tap a star', 'Rough', 'Meh', 'Okay', 'Good', 'Great'];
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.tile),
        boxShadow: NestShadow.resting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('PRODUCTIVITY', style: nestEyebrow),
              const Spacer(),
              Text(words[rating], style: t.bodySmall),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i star${i == 1 ? '' : 's'}',
                  iconSize: 38,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    // Tapping the current rating again clears it.
                    _repo.saveDayLog(_day, rating: rating == i ? 0 : i);
                  },
                  icon: Icon(
                    i <= rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color:
                        i <= rating ? NestColor.highlight : NestColor.inkFaint,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Monday to Sunday of the chosen week. A dot marks a day with tasks: indigo
/// while something is open, green once all of it is done.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip(
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
    final isToday = sameDay(day, now);
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous week',
              onPressed: () =>
                  onPick(DateTime(day.year, day.month, day.day - 7)),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                '${_months[week.first.month - 1]} ${week.first.day} – '
                '${_months[week.last.month - 1]} ${week.last.day}',
                textAlign: TextAlign.center,
                style: t.titleSmall,
              ),
            ),
            if (!isToday)
              TextButton(
                  onPressed: () => onPick(now), child: const Text('Today')),
            IconButton(
              tooltip: 'Next week',
              onPressed: () =>
                  onPick(DateTime(day.year, day.month, day.day + 7)),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        Row(
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
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Semantics(
                      button: true,
                      selected: selected,
                      label: '${_weekdays[i]} ${d.day}',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(NestRadius.chip),
                        onTap: () => onPick(d),
                        child: Container(
                          height: 66,
                          decoration: BoxDecoration(
                            color: selected ? NestColor.pen : NestColor.card,
                            borderRadius:
                                BorderRadius.circular(NestRadius.chip),
                            border: today && !selected
                                ? Border.all(color: NestColor.pen, width: 1.5)
                                : null,
                            boxShadow: selected
                                ? NestShadow.glow(NestColor.pen)
                                : null,
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
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${d.day}',
                                style: t.titleSmall?.copyWith(
                                  color: selected ? Colors.white : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: mine.isEmpty
                                      ? Colors.transparent
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
        ),
      ],
    );
  }
}

/// A titled white card holding task rows and, optionally, a quick-add field.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.count,
    required this.children,
    this.emptyText,
    this.quickAdd,
    this.accent,
  });

  final String title;
  final int count;
  final List<Widget> children;
  final String? emptyText;
  final Widget? quickAdd;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.tile),
        boxShadow: NestShadow.resting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: nestEyebrow.copyWith(color: accent),
                ),
                const SizedBox(width: 8),
                if (count > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: accent == null
                          ? NestColor.tintPen
                          : NestColor.tintRed,
                      borderRadius: BorderRadius.circular(NestRadius.pill),
                    ),
                    child: Text(
                      '$count',
                      style: t.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accent == null
                            ? NestColor.penDeep
                            : NestColor.redDeep,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (children.isEmpty && emptyText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(emptyText!, style: t.bodySmall),
            )
          else
            ...children,
          if (quickAdd != null) quickAdd!,
        ],
      ),
    );
  }
}

/// One line that adds a task on Enter and stays focused for the next one.
class _QuickAdd extends StatefulWidget {
  const _QuickAdd({required this.hint, required this.onAdd});

  final String hint;
  final Future<void> Function(String title) onAdd;

  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  final _c = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    _c.clear();
    await widget.onAdd(text);
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: TextField(
        controller: _c,
        focusNode: _focus,
        maxLength: 120,
        buildCounter: (_,
                {required currentLength, required isFocused, maxLength}) =>
            null,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: widget.hint,
          isDense: true,
          prefixIcon: const Icon(Icons.add_rounded),
          suffixIcon: IconButton(
            tooltip: 'Add',
            onPressed: _submit,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ),
      ),
    );
  }
}

/// Up to seven goals, each ticked off when reached.
class _GoalsCard extends StatefulWidget {
  const _GoalsCard({required this.repo});

  final NoteRepository repo;

  @override
  State<_GoalsCard> createState() => _GoalsCardState();
}

class _GoalsCardState extends State<_GoalsCard> {
  Future<void> _edit(Goal g) async {
    final c = TextEditingController(text: g.title);
    final action = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: NestColor.card,
        title: const Text('Edit goal'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, 'delete'),
            style: TextButton.styleFrom(foregroundColor: NestColor.redPen),
            child: const Text('Delete'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final text = c.text;
    c.dispose();
    if (action == 'delete') {
      await widget.repo.deleteGoal(g);
    } else if (action == 'save' && text.trim().isNotEmpty) {
      await widget.repo.updateGoal(g.copyWith(title: text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = widget.repo.goals();
    final open = goals.where((g) => !g.isDone).length;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.tile),
        boxShadow: NestShadow.resting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                const Text('MY TOP 7 GOALS', style: nestEyebrow),
                const Spacer(),
                Text('$open / $maxGoals', style: t.bodySmall),
              ],
            ),
          ),
          if (goals.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                'What matters most this term? Add up to seven.',
                style: t.bodySmall,
              ),
            ),
          for (var i = 0; i < goals.length; i++)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: _TickCircle(
                done: goals[i].isDone,
                color: NestColor.pen,
                label: '${i + 1}',
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.repo.setGoalDone(goals[i], !goals[i].isDone);
                },
              ),
              title: Text(
                goals[i].title,
                style: t.titleSmall?.copyWith(
                  decoration:
                      goals[i].isDone ? TextDecoration.lineThrough : null,
                  color: goals[i].isDone ? NestColor.inkFaint : null,
                ),
              ),
              onTap: () => _edit(goals[i]),
            ),
          if (open < maxGoals)
            _QuickAdd(
              hint: 'Add a goal',
              onAdd: (title) async {
                await widget.repo.addGoal(title);
              },
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text(
                'Seven open goals. Finish one to add another.',
                style: t.bodySmall,
              ),
            ),
        ],
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

/// One task row: tap the circle to complete, tap the row to edit, swipe right
/// to complete or left to delete (with Undo).
class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task});

  final Task task;

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
        chip('In progress', NestColor.tintWarm, NestColor.warmDeep),
      if (task.priority == TaskPriority.high && !task.isDone)
        chip('High', NestColor.tintRed, NestColor.redDeep),
    ];

    return Dismissible(
      key: ValueKey('task-${task.id}'),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.only(bottom: 6),
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
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: NestColor.tintRed,
          borderRadius: BorderRadius.circular(NestRadius.chip),
        ),
        child:
            const Icon(Icons.delete_outline_rounded, color: NestColor.redDeep),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await repo.setTaskDone(task, !task.isDone);
          return false;
        }
        final messenger = ScaffoldMessenger.of(context);
        await repo.deleteTask(task);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: const Text('Task deleted'),
          action: SnackBarAction(
            label: 'Undo',
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
        return false;
      },
      child: Container(
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
                    onTap: () {
                      HapticFeedback.selectionClick();
                      repo.setTaskDone(task, !task.isDone);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall?.copyWith(
                          decoration:
                              task.isDone ? TextDecoration.lineThrough : null,
                          color: task.isDone ? NestColor.inkFaint : null,
                        ),
                      ),
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 4, children: chips),
                      ],
                    ],
                  ),
                ),
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
      setState(() => _error = 'Give the task a title.');
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
          _error = 'That could not be saved. Try again.';
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
        title: const Text('Delete this task?'),
        content: Text('"${task.title}" will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
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
              widget.existing == null ? 'New task' : 'Edit task',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _desc,
              maxLines: 3,
              maxLength: 1000,
              decoration:
                  const InputDecoration(labelText: 'Details (optional)'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDue,
                    icon: const Icon(Icons.event_rounded),
                    label: Text(
                      _due == null ? 'Set due date' : taskDueLabel(_due!),
                    ),
                  ),
                ),
                if (_due != null)
                  IconButton(
                    tooltip: 'Clear due date',
                    onPressed: () => setState(() => _due = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('PRIORITY', style: nestEyebrow),
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
              title: const Text('In progress'),
              value: _inProgress,
              onChanged: (v) => setState(() => _inProgress = v),
            ),
            if (subjects.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('COURSE', style: nestEyebrow),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('None'),
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
                style: const TextStyle(color: NestColor.redPen),
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
                    child: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save'),
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
  const TasksCard({super.key});

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
              Expanded(child: Text('To-do', style: t.titleMedium)),
              IconButton(
                tooltip: 'Add a task',
                onPressed: () => showTaskForm(context),
                icon: const Icon(Icons.add_rounded),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TasksPage()),
                ),
                child: const Text('See all'),
              ),
            ],
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, right: 8),
              child: Text(
                repo.openTasks.isEmpty
                    ? 'Nothing planned. Add a task to keep track of work.'
                    : 'Nothing due today. ${repo.openTasks.length} open in total.',
                style: t.bodySmall,
              ),
            )
          else ...[
            for (final task in shown) TaskTile(task: task),
            if (more > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text('+ $more more', style: t.bodySmall),
              ),
          ],
        ],
      ),
    );
  }
}
