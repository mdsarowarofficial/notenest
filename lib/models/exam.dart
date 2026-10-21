/// Exams, and the rule that decides what to revise first.
///
/// The ordering in [revisionOrder] is the whole point of Exam Mode, so it
/// lives here as plain Dart with no database and no widgets attached — it can
/// be read, argued with, and tested on its own.
library;

import 'note.dart';
import '../l10n/strings.dart';

/// What is on the date. Quizzes and assignments share the countdown and the
/// calendar with exams; only the wording changes.
enum ExamKind { exam, quiz, assignment, other }

extension ExamKindData on ExamKind {
  String get key => name;

  String get label {
    switch (this) {
      case ExamKind.exam:
        return tr('Exam');
      case ExamKind.quiz:
        return tr('Quiz');
      case ExamKind.assignment:
        return tr('Assignment');
      case ExamKind.other:
        return tr('Other');
    }
  }

  static ExamKind fromKey(String? key) {
    switch (key) {
      case 'quiz':
        return ExamKind.quiz;
      case 'assignment':
        return ExamKind.assignment;
      case 'other':
        return ExamKind.other;
      default:
        return ExamKind.exam;
    }
  }
}

/// A dated thing the student is working towards.
class Exam {
  const Exam({
    this.id,
    required this.userId,
    this.subjectId,
    required this.title,
    required this.date,
    this.kind = ExamKind.exam,
    this.note,
    this.remindDays,
    required this.createdAt,
  });

  final int? id;
  final int userId;
  final int? subjectId;
  final String title;

  /// Stored at midnight. An exam is a day, not a moment — carrying a time
  /// would make "2 days away" depend on what o'clock it was added.
  final DateTime date;

  final ExamKind kind;
  final String? note;
  final DateTime createdAt;

  /// How many days before the date the student asked to be reminded. Null
  /// means no reminder.
  ///
  /// Stored as a number of days rather than a timestamp so that moving the
  /// exam moves the reminder with it, instead of leaving a stale alarm behind
  /// pointing at a date that no longer has anything on it.
  final int? remindDays;

  int get daysAway => daysUntil(date);

  bool get isPast => daysAway < 0;

  bool get isToday => daysAway == 0;

  bool get hasReminder => remindDays != null;

  /// True once the reminder window has opened and the date has not passed.
  bool get reminderIsDue {
    final lead = remindDays;
    if (lead == null) return false;
    final days = daysAway;
    return days >= 0 && days <= lead;
  }

  Exam copyWith({
    int? id,
    int? subjectId,
    bool clearSubject = false,
    String? title,
    DateTime? date,
    ExamKind? kind,
    String? note,
    int? remindDays,
    bool clearReminder = false,
  }) =>
      Exam(
        id: id ?? this.id,
        userId: userId,
        subjectId: clearSubject ? null : (subjectId ?? this.subjectId),
        title: title ?? this.title,
        date: date ?? this.date,
        kind: kind ?? this.kind,
        note: note ?? this.note,
        remindDays: clearReminder ? null : (remindDays ?? this.remindDays),
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'subject_id': subjectId,
        'title': title,
        'exam_date': atMidnight(date).millisecondsSinceEpoch,
        'kind': kind.key,
        'note': note,
        'remind_days': remindDays,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Exam.fromMap(Map<String, Object?> m) => Exam(
        id: m['id'] as int?,
        userId: m['user_id'] as int,
        subjectId: m['subject_id'] as int?,
        title: m['title'] as String? ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(
          m['exam_date'] as int? ?? 0,
        ),
        kind: ExamKindData.fromKey(m['kind'] as String?),
        note: m['note'] as String?,
        remindDays: m['remind_days'] as int?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
      );
}

/// The reminder leads offered in the form. Days, not hours: a student planning
/// revision thinks in days, and a lead time of "90 minutes" before an exam is
/// not a reminder, it is a jump scare.
const reminderChoices = <int>[1, 3, 7];

String reminderLabel(int? days) {
  if (days == null) return tr('Off');
  if (days == 1) return tr('1 day before');
  if (days == 7) return tr('1 week before');
  return trp('{0} days before', [days]);
}

/// Strips the time off a date, so two dates on the same day compare equal.
DateTime atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole days from today to [date]. Negative once the date has passed.
int daysUntil(DateTime date, {DateTime? from}) {
  final today = atMidnight(from ?? DateTime.now());
  final target = atMidnight(date);
  // The two days are compared in UTC on purpose. Subtracting local midnights
  // measures elapsed hours, so in a timezone that puts its clocks forward
  // between them a two-day gap is 47 hours and `inDays` rounds it down to 1.
  // Bangladesh has no daylight saving, but a countdown that is wrong once a
  // year somewhere else is still wrong.
  final a = DateTime.utc(today.year, today.month, today.day);
  final b = DateTime.utc(target.year, target.month, target.day);
  return b.difference(a).inDays;
}

/// "Today", "Tomorrow", "in 6 days", "2 days ago".
String countdownLabel(int days) {
  if (days == 0) return tr('Today');
  if (days == 1) return tr('Tomorrow');
  if (days == -1) return tr('Yesterday');
  if (days > 0) return trp('in {0} days', [days]);
  return trp('{0} days ago', [-days]);
}

/// Orders notes by what deserves attention first before an exam.
///
/// The rule, in order, and why each step is where it is:
///
/// 1. **Starred notes first.** The student marked those themselves. An app
///    guessing what matters should never outrank the student saying it.
/// 2. **Then by how far through the revision cycle the note is**, worst
///    first: Review, then New, then Read, then Mastered. Review sits above
///    New for the same reason as step 1 — "Review" is the student's own note
///    to themselves that this one did not stick, and that is a stronger
///    signal than the app noticing a note was never opened.
/// 3. **Then least recently opened**, with never-opened counting as longest
///    ago, so nothing sits at the bottom of the list forever.
/// 4. **Then oldest first**, purely so the order is stable and does not
///    shuffle between builds.
///
/// Mastered notes are kept rather than dropped: the day before an exam a
/// student may well want to skim them, and a list that silently hides work is
/// worse than one that puts it last.
List<Note> revisionOrder(List<Note> notes) {
  final out = List<Note>.of(notes);
  out.sort((a, b) {
    if (a.important != b.important) return a.important ? -1 : 1;

    final byStatus = _statusRank(a.status).compareTo(_statusRank(b.status));
    if (byStatus != 0) return byStatus;

    final ao = a.openedAt;
    final bo = b.openedAt;
    if (ao == null && bo != null) return -1;
    if (ao != null && bo == null) return 1;
    if (ao != null && bo != null) {
      final byOpened = ao.compareTo(bo);
      if (byOpened != 0) return byOpened;
    }

    return a.updatedAt.compareTo(b.updatedAt);
  });
  return out;
}

int _statusRank(StudyStatus status) {
  switch (status) {
    case StudyStatus.review:
      return 0;
    case StudyStatus.newNote:
      return 1;
    case StudyStatus.read:
      return 2;
    case StudyStatus.mastered:
      return 3;
  }
}

/// How many notes to get through today to finish in time.
///
/// Returns 0 when there is nothing left. With the exam today or already past,
/// the answer is everything that remains — there is no later to spread it
/// over.
int dailyTarget({required int remaining, required int daysLeft}) {
  if (remaining <= 0) return 0;
  if (daysLeft <= 0) return remaining;
  return (remaining + daysLeft - 1) ~/ daysLeft;
}

/// How far through the subject the student is, 0..1.
double masteredShare(List<Note> notes) {
  if (notes.isEmpty) return 0;
  final done = notes.where((n) => n.status == StudyStatus.mastered).length;
  return done / notes.length;
}

/// A short, honest line about where the revision stands.
///
/// Deliberately never congratulatory when it is not warranted: a student two
/// days from an exam with most of the subject untouched should be told that,
/// not cheered along.
String revisionVerdict({
  required int remaining,
  required int daysLeft,
  required int total,
}) {
  if (total == 0) return tr('No notes in this subject yet.');
  if (remaining == 0) return tr('Everything here is marked Mastered.');

  final perDay = dailyTarget(remaining: remaining, daysLeft: daysLeft);

  if (daysLeft < 0) return trp('{0} still not mastered.', [remaining]);
  if (daysLeft == 0) {
    return trp('{0} left and the exam is today.', [remaining]);
  }
  if (perDay == 1) return tr('One note a day clears this in time.');
  return trp('{0} notes a day clears this in time.', [perDay]);
}
