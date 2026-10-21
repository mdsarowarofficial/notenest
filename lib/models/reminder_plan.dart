/// Works out which local reminders should exist, with no plugin attached.
///
/// The phone's notification scheduler is asked to hold exactly this list and
/// nothing else; the list is rebuilt whenever tasks or exams change. Keeping
/// the rules here, as plain Dart, is what lets them be tested.
library;

import 'exam.dart';
import 'task.dart';
import '../l10n/strings.dart';

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
const reviewId = 4000000;
const maxPlanned = 40;

List<PlannedReminder> planReminders({
  required List<Task> tasks,
  required List<Exam> exams,
  required DateTime now,
  required Set<String> disabledGroups,
  bool idleNudge = false,
  int idleDays = 3,
  List<DateTime> reviewDue = const [],
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
        title: useEarly ? tr('Due in an hour') : tr('Task due now'),
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
            title: trp('{0} in {1} days', [e.title, lead]),
            body: e.kind.label,
            at: at,
          ));
        }
      }
      final onDay = DateTime(e.date.year, e.date.month, e.date.day, 8);
      if (onDay.isAfter(now)) {
        out.add(PlannedReminder(
          id: _examBase + e.id! * 2 + 1,
          title: trp('{0} is today', [e.title]),
          body: e.kind.label,
          at: onDay,
        ));
      }
    }
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  final capped = out.take(maxPlanned).toList();

  // Notes coming round for review: one evening reminder on the first day any
  // is due (today, if some already are), saying how many will be waiting.
  if (reviewDue.isNotEmpty && !disabledGroups.contains('reviews')) {
    final first = reviewDue.reduce((a, b) => a.isBefore(b) ? a : b);
    var day = DateTime(first.year, first.month, first.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day.isBefore(today)) day = today;
    var at = DateTime(day.year, day.month, day.day, 18);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    final waiting = reviewDue.where((d) => !d.isAfter(at)).length;
    capped.add(PlannedReminder(
      id: reviewId,
      title: tr('Notes to review'),
      body: waiting == 1
          ? tr('1 note is ready for review.')
          : trp('{0} notes are ready for review.', [waiting]),
      at: at,
    ));
  }

  // One quiet nudge, a few days after the app was last opened. Opening the
  // app rebuilds the plan, which pushes this back; it only ever rings for
  // someone who has stayed away.
  if (idleNudge) {
    final day = now.add(Duration(days: idleDays));
    capped.add(PlannedReminder(
      id: idleId,
      title: tr('Your notes are waiting'),
      body: tr('Pick up where you left off.'),
      at: DateTime(day.year, day.month, day.day, 18),
    ));
  }
  return capped;
}
