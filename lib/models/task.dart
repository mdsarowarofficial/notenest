/// A to-do item, for students and teachers alike.
///
/// Plain Dart with no database or widgets, like the other models. "Overdue" is
/// never stored: it is worked out from the due time and [doneAt], so it cannot
/// disagree with them.
library;

enum TaskPriority { low, normal, high }

extension TaskPriorityData on TaskPriority {
  String get key => name;

  String get label {
    switch (this) {
      case TaskPriority.low:
        return 'Low';
      case TaskPriority.normal:
        return 'Normal';
      case TaskPriority.high:
        return 'High';
    }
  }

  static TaskPriority fromKey(String? key) {
    switch (key) {
      case 'low':
        return TaskPriority.low;
      case 'high':
        return TaskPriority.high;
      default:
        return TaskPriority.normal;
    }
  }
}

class Task {
  const Task({
    this.id,
    required this.userId,
    this.subjectId,
    required this.title,
    this.description,
    this.dueAt,
    this.priority = TaskPriority.normal,
    this.doneAt,
    this.inProgress = false,
    required this.createdAt,
  });

  final int? id;
  final int userId;
  final int? subjectId;
  final String title;
  final String? description;

  /// A moment, not a day: a task can be due at 5 pm.
  final DateTime? dueAt;
  final TaskPriority priority;

  /// Null while the task is open.
  final DateTime? doneAt;

  /// Started but not finished. Ignored once the task is done.
  final bool inProgress;
  final DateTime createdAt;

  bool get isDone => doneAt != null;

  bool isOverdue({DateTime? now}) =>
      !isDone && dueAt != null && dueAt!.isBefore(now ?? DateTime.now());

  /// Open and due at some point today (and not already past).
  bool isDueToday({DateTime? now}) {
    final n = now ?? DateTime.now();
    final d = dueAt;
    if (isDone || d == null) return false;
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  Task copyWith({
    int? id,
    int? subjectId,
    bool clearSubject = false,
    String? title,
    String? description,
    bool clearDescription = false,
    DateTime? dueAt,
    bool clearDue = false,
    TaskPriority? priority,
    DateTime? doneAt,
    bool clearDone = false,
    bool? inProgress,
  }) =>
      Task(
        id: id ?? this.id,
        userId: userId,
        subjectId: clearSubject ? null : (subjectId ?? this.subjectId),
        title: title ?? this.title,
        description:
            clearDescription ? null : (description ?? this.description),
        dueAt: clearDue ? null : (dueAt ?? this.dueAt),
        priority: priority ?? this.priority,
        doneAt: clearDone ? null : (doneAt ?? this.doneAt),
        inProgress: inProgress ?? this.inProgress,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'subject_id': subjectId,
        'title': title,
        'description': description,
        'due_at': dueAt?.millisecondsSinceEpoch,
        'priority': priority.key,
        'done_at': doneAt?.millisecondsSinceEpoch,
        'in_progress': inProgress ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Task.fromMap(Map<String, Object?> m) {
    DateTime? ms(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return Task(
      id: m['id'] as int?,
      userId: m['user_id'] as int,
      subjectId: m['subject_id'] as int?,
      title: m['title'] as String? ?? '',
      description: m['description'] as String?,
      dueAt: ms(m['due_at']),
      priority: TaskPriorityData.fromKey(m['priority'] as String?),
      doneAt: ms(m['done_at']),
      inProgress: m['in_progress'] == 1,
      createdAt: ms(m['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// How many days in a row, ending today, had tasks and every one done.
///
/// Today still being in progress does not break the run: if today is not yet
/// clear, counting starts from yesterday. A day with no tasks breaks it.
int doneStreak(Iterable<Task> tasks, DateTime today) {
  final open = <int, bool>{}; // day -> has an open task
  int key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  for (final t in tasks) {
    final d = t.dueAt;
    if (d == null) continue;
    open[key(d)] = (open[key(d)] ?? false) || !t.isDone;
  }
  bool clear(DateTime d) => open[key(d)] == false;

  var day = DateTime(today.year, today.month, today.day);
  if (!clear(day)) day = DateTime(day.year, day.month, day.day - 1);
  var n = 0;
  while (clear(day) && n < 400) {
    n++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return n;
}

/// Open tasks first (overdue, then by due time, undated last), then done ones,
/// most recently finished first. Higher priority breaks ties.
int compareTasks(Task a, Task b) {
  if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
  if (a.isDone) return b.doneAt!.compareTo(a.doneAt!);
  final ad = a.dueAt, bd = b.dueAt;
  if (ad != null && bd != null) {
    final c = ad.compareTo(bd);
    if (c != 0) return c;
  } else if (ad != null) {
    return -1;
  } else if (bd != null) {
    return 1;
  }
  return b.priority.index.compareTo(a.priority.index);
}
