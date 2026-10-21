/// One sitting of focused study, as recorded by the study timer.
///
/// Plain Dart with no database or widgets, like the other models.
library;

class StudySession {
  const StudySession({
    this.id,
    required this.userId,
    this.subjectId,
    required this.startedAt,
    required this.minutes,
  });

  final int? id;
  final int userId;
  final int? subjectId;
  final DateTime startedAt;
  final int minutes;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'subject_id': subjectId,
        'started_at': startedAt.millisecondsSinceEpoch,
        'minutes': minutes,
      };

  factory StudySession.fromMap(Map<String, Object?> m) => StudySession(
        id: m['id'] as int?,
        userId: m['user_id'] as int,
        subjectId: m['subject_id'] as int?,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int? ?? 0),
        minutes: (m['minutes'] as int?) ?? 0,
      );
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Minutes studied on [day].
int minutesOn(Iterable<StudySession> sessions, DateTime day) {
  final d = _day(day);
  var total = 0;
  for (final s in sessions) {
    if (_day(s.startedAt) == d) total += s.minutes;
  }
  return total;
}

/// Minutes studied on each of the [count] days ending on [today], oldest
/// first, for the week's bars.
List<int> minutesPerDay(
  Iterable<StudySession> sessions,
  DateTime today, {
  int count = 7,
}) {
  final end = _day(today);
  return [
    for (var i = count - 1; i >= 0; i--)
      minutesOn(sessions, DateTime(end.year, end.month, end.day - i)),
  ];
}

/// How many days in a row, ending today, have at least one session.
///
/// A day that has not happened yet does not break the run: if nothing has been
/// studied *today*, the count carries on from yesterday, so a streak is not
/// lost at breakfast.
int studyStreak(Iterable<StudySession> sessions, DateTime today) {
  final days = {for (final s in sessions) _day(s.startedAt)};
  var d = _day(today);
  if (!days.contains(d)) d = DateTime(d.year, d.month, d.day - 1);
  var streak = 0;
  while (days.contains(d)) {
    streak++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return streak;
}

/// "1 h 25 min", "40 min", "0 min".
String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}
