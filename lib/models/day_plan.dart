/// The parts of the to-do page that are not tasks: the goals a person is
/// working toward, and a short note and star rating for each day.
///
/// Plain Dart with no database or widgets, like the other models.
library;

/// How many goals the list holds. A short list is the point: seven is a set a
/// person can keep in their head.
const maxGoals = 7;

/// A goal sits above the day-to-day tasks. It has no due time; it is simply
/// kept until it is reached or removed.
class Goal {
  const Goal({
    this.id,
    required this.userId,
    required this.title,
    this.doneAt,
    required this.createdAt,
  });

  final int? id;
  final int userId;
  final String title;

  /// Null while the goal is still being worked toward.
  final DateTime? doneAt;
  final DateTime createdAt;

  bool get isDone => doneAt != null;

  Goal copyWith({String? title, DateTime? doneAt, bool clearDone = false}) =>
      Goal(
        id: id,
        userId: userId,
        title: title ?? this.title,
        doneAt: clearDone ? null : (doneAt ?? this.doneAt),
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'title': title,
        'done_at': doneAt?.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Goal.fromMap(Map<String, Object?> m) {
    DateTime? ms(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return Goal(
      id: m['id'] as int?,
      userId: m['user_id'] as int,
      title: m['title'] as String? ?? '',
      doneAt: ms(m['done_at']),
      createdAt: ms(m['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// "2026-10-20" — the key a day is filed under. Built from the calendar date,
/// not from a moment, so a day never shifts with the time zone.
String dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// What a person wrote and how they rated one day.
class DayLog {
  const DayLog({
    required this.userId,
    required this.day,
    this.thoughts = '',
    this.rating = 0,
  });

  final int userId;

  /// A [dayKey].
  final String day;
  final String thoughts;

  /// 0 for unrated, otherwise 1 to 5 stars.
  final int rating;

  bool get isEmpty => thoughts.trim().isEmpty && rating == 0;

  DayLog copyWith({String? thoughts, int? rating}) => DayLog(
        userId: userId,
        day: day,
        thoughts: thoughts ?? this.thoughts,
        rating: rating ?? this.rating,
      );

  Map<String, Object?> toMap() => {
        'user_id': userId,
        'day': day,
        'thoughts': thoughts,
        'rating': rating,
      };

  factory DayLog.fromMap(Map<String, Object?> m) => DayLog(
        userId: m['user_id'] as int,
        day: m['day'] as String? ?? '',
        thoughts: m['thoughts'] as String? ?? '',
        rating: ((m['rating'] as int?) ?? 0).clamp(0, 5),
      );
}

/// The seven days of the week that holds [day], Monday first.
List<DateTime> weekOf(DateTime day) {
  final start = DateTime(day.year, day.month, day.day)
      .subtract(Duration(days: day.weekday - DateTime.monday));
  // Built by calendar fields, not by adding 24 hours, so a clock change does
  // not turn one date into its neighbour.
  return [
    for (var i = 0; i < 7; i++)
      DateTime(start.year, start.month, start.day + i),
  ];
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// A task saved with no time of day is stored as 11:59 PM; that is "some time
/// that day", not a real deadline, so it should not be shown as a clock time.
bool hasRealClock(DateTime at) => !(at.hour == 23 && at.minute == 59);
