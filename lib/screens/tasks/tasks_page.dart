import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/exam.dart';
import '../../models/task.dart';
import '../../theme/nest_theme.dart';

/// "Mon 12 Oct, 5:30 PM" — the due time as it reads in a list.
String taskDueLabel(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final days = daysUntil(at, from: n);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final m = at.minute.toString().padLeft(2, '0');
  final clock = '$h:$m ${at.hour < 12 ? 'AM' : 'PM'}';
  final day = days == 0
      ? 'Today'
      : days == 1
          ? 'Tomorrow'
          : days == -1
              ? 'Yesterday'
              : '${at.day} ${months[at.month - 1]}';
  return '$day, $clock';
}

enum _View { open, inProgress, overdue, done, all }

enum _Sort { due, priority }

/// The full to-do list. Personal and private: every read and write in the
/// repository is scoped to the signed-in account.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _repo = NoteRepository.instance;
  final _search = TextEditingController();
  _View _view = _View.open;
  int? _subjectId;
  TaskPriority? _priority;
  _Sort _sort = _Sort.due;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Task> _visible() {
    final q = _search.text.trim().toLowerCase();
    final list = _repo.tasks().where((t) {
      switch (_view) {
        case _View.open:
          if (t.isDone) return false;
        case _View.inProgress:
          if (t.isDone || !t.inProgress) return false;
        case _View.overdue:
          if (!t.isOverdue()) return false;
        case _View.done:
          if (!t.isDone) return false;
        case _View.all:
      }
      if (_subjectId != null && t.subjectId != _subjectId) return false;
      if (_priority != null && t.priority != _priority) return false;
      if (q.isNotEmpty &&
          !t.title.toLowerCase().contains(q) &&
          !(t.description ?? '').toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
    if (_sort == _Sort.priority) {
      list.sort((a, b) {
        if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
        final c = b.priority.index.compareTo(a.priority.index);
        return c != 0 ? c : compareTasks(a, b);
      });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NestColor.paper,
      appBar: AppBar(
        title: const Text('To-do'),
        actions: [
          PopupMenuButton<_Sort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort_rounded),
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.due, child: Text('Sort by due time')),
              PopupMenuItem(value: _Sort.priority, child: Text('Sort by priority')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTaskForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add task'),
      ),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          final tasks = _visible();
          final subjects = _repo.subjects();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search tasks',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final v in _View.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(switch (v) {
                            _View.open => 'Open',
                            _View.inProgress => 'In progress',
                            _View.overdue =>
                              'Overdue (${_repo.overdueTasks.length})',
                            _View.done => 'Done',
                            _View.all => 'All',
                          }),
                          selected: _view == v,
                          onSelected: (_) => setState(() => _view = v),
                        ),
                      ),
                    for (final p in TaskPriority.values.reversed)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(p.label),
                          selected: _priority == p,
                          onSelected: (on) =>
                              setState(() => _priority = on ? p : null),
                        ),
                      ),
                    for (final s in subjects)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(s.code),
                          selected: _subjectId == s.id,
                          onSelected: (on) =>
                              setState(() => _subjectId = on ? s.id : null),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _repo.tasks().isEmpty
                                ? 'Nothing to do yet.\nTap "Add task" to start.'
                                : 'No tasks match.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: tasks.length,
                        itemBuilder: (_, i) => TaskTile(task: tasks[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One task row: tick to complete, tap to edit, swipe or edit sheet to delete.
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
    final meta = [
      if (task.dueAt != null) taskDueLabel(task.dueAt!),
      if (subject != null) subject.code,
      if (task.inProgress && !task.isDone) 'In progress',
      if (task.priority == TaskPriority.high) 'High priority',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: NestColor.card,
      elevation: 0,
      child: ListTile(
        minVerticalPadding: 6,
        leading: Checkbox(
          value: task.isDone,
          onChanged: (v) => repo.setTaskDone(task, v ?? false),
        ),
        title: Text(
          task.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.titleSmall?.copyWith(
            decoration: task.isDone ? TextDecoration.lineThrough : null,
            color: task.isDone ? NestColor.inkFaint : null,
          ),
        ),
        subtitle: meta.isEmpty
            ? null
            : Text(
                meta,
                style: t.bodySmall?.copyWith(
                  color: overdue ? NestColor.redPen : NestColor.inkSoft,
                ),
              ),
        onTap: () => showTaskForm(context, existing: task),
      ),
    );
  }
}

/// Adds or edits a task in a bottom sheet — one screen, no wizard.
Future<bool> showTaskForm(
  BuildContext context, {
  Task? existing,
  int? subjectId,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: NestColor.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _TaskForm(existing: existing, subjectId: subjectId),
  );
  return saved ?? false;
}

class _TaskForm extends StatefulWidget {
  const _TaskForm({this.existing, this.subjectId});

  final Task? existing;
  final int? subjectId;

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
    _due = e?.dueAt;
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
