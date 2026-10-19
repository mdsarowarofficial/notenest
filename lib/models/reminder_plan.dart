/// Works out which local reminders should exist, with no plugin attached.
///
/// The phone's notification scheduler is asked to hold exactly this list and
/// nothing else; the list is rebuilt whenever tasks or exams change. Keeping
/// the rules here, as plain Dart, is what lets them be tested.
library;

import 'exam.dart';
import 'task.dart';

class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
  });

  final int id;
  final String title;
  final String body;
  final DateTime at;
}

/// Quiet hours: anything that would ring between 22:00 and 07:00 waits until
/// 07:00 instead.
DateTime adjustForQuietHours(DateTime at) {
  if (at.hour >= 22) return DateTime(at.year, at.month, at.day + 1, 7);
  if (at.hour < 7) return DateTime(at.year, at.month, at.day, 7);
  return at;
}

const _taskBase = 1000000;
const _examBase = 2000000;
const idleId = 3000000;
const maxPlanned = 40;

List<PlannedReminder> planReminders({
  required List<Task> tasks,
  required List<Exam> exams,
  required DateTime now,
  required Set<String> disabledGroups,
  bool idleNudge = false,
  int idleDays = 3,
}) {
  final out = <PlannedReminder>[];

  if (!disabledGroups.contains('tasks')) {
    for (final t in tasks) {
      final due = t.dueAt;
      if (t.isDone || due == null || t.id == null) continue;
      // An hour before when there is time, otherwise at the due moment.
      final early = due.subtract(const Duration(hours: 1));
      final useEarly = early.isAfter(now);
      final at = adjustForQuietHours(useEarly ? early : due);
      if (!at.isAfter(now)) continue;
      out.add(PlannedReminder(
        id: _taskBase + t.id!,
        title: useEarly ? 'Due in an hour' : 'Task due now',
        body: t.title,
        at: at,
      ));
    }
  }

  if (!disabledGroups.contains('exams')) {
    for (final e in exams) {
      if (e.id == null || e.isPast) continue;
      final lead = e.remindDays;
      if (lead != null && lead > 0) {
        final day = e.date.subtract(Duration(days: lead));
        final at = DateTime(day.year, day.month, day.day, 8);
        if (at.isAfter(now)) {
          out.add(PlannedReminder(
            id: _examBase + e.id! * 2,
            title: '${e.title} in $lead days',
            body: e.kind.label,
            at: at,
          ));
        }
      }
      final onDay = DateTime(e.date.year, e.date.month, e.date.day, 8);
      if (onDay.isAfter(now)) {
        out.add(PlannedReminder(
          id: _examBase + e.id! * 2 + 1,
          title: '${e.title} is today',
          body: e.kind.label,
          at: onDay,
        ));
      }
    }
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  final capped = out.take(maxPlanned).toList();

  // One quiet nudge, a few days after the app was last opened. Opening the
  // app rebuilds the plan, which pushes this back; it only ever rings for
  // someone who has stayed away.
  if (idleNudge) {
    final day = now.add(Duration(days: idleDays));
    capped.add(PlannedReminder(
      id: idleId,
      title: 'Your notes are waiting',
      body: 'Pick up where you left off.',
      at: DateTime(day.year, day.month, day.day, 18),
    ));
  }
  return capped;
}
