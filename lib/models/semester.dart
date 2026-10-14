/// How a university divides its year, and what that makes a semester called.
///
/// NoteNest used to ask for the semester as free text, which meant everybody
/// typed something slightly different — "5th", "Semester 5", "sem-5" — and the
/// cover page printed whatever they typed. Choosing the system first means the
/// app can offer the right numbers and write them the same way every time.
library;

enum SemesterSystem {
  /// Two a year: eight across a four-year degree.
  bi,

  /// Three a year: twelve across a four-year degree.
  tri,

  /// Anything else. Some institutions count in years, terms or trimesters,
  /// and an app that insists otherwise is wrong rather than tidy.
  custom,
}

extension SemesterSystemData on SemesterSystem {
  String get key => name;

  String get label {
    switch (this) {
      case SemesterSystem.bi:
        return 'Bi-semester';
      case SemesterSystem.tri:
        return 'Tri-semester';
      case SemesterSystem.custom:
        return 'Something else';
    }
  }

  /// How many semesters a four-year degree has under this system.
  int get count {
    switch (this) {
      case SemesterSystem.bi:
        return 8;
      case SemesterSystem.tri:
        return 12;
      case SemesterSystem.custom:
        return 0;
    }
  }

  String get blurb {
    switch (this) {
      case SemesterSystem.bi:
        return 'Two a year — 8 across four years.';
      case SemesterSystem.tri:
        return 'Three a year — 12 across four years.';
      case SemesterSystem.custom:
        return 'Write it however your university does.';
    }
  }

  /// Unknown keys fall back to [custom], which asks rather than assumes. A
  /// stored value this version does not recognise is not a reason to tell
  /// somebody their semester is wrong.
  static SemesterSystem fromKey(String? key) {
    switch (key) {
      case 'bi':
        return SemesterSystem.bi;
      case 'tri':
        return SemesterSystem.tri;
      default:
        return SemesterSystem.custom;
    }
  }
}

/// The one way a numbered semester is written down.
String semesterLabelFor(int number) => 'Semester $number';

/// The number inside a stored label, when there is one.
///
/// Used to reopen the picker where it was left rather than at 1. Deliberately
/// forgiving about what is around the number, because labels typed before this
/// screen existed are still in people's settings: "5th semester", "Semester 5"
/// and "sem 5" all give 5.
int? semesterNumberIn(String? label) {
  if (label == null) return null;
  final match = RegExp(r'\d+').firstMatch(label);
  if (match == null) return null;
  final n = int.tryParse(match.group(0)!);
  if (n == null || n < 1 || n > 20) return null;
  return n;
}

/// Whether a number makes sense under this system.
bool semesterNumberFits(SemesterSystem system, int number) {
  if (system == SemesterSystem.custom) return true;
  return number >= 1 && number <= system.count;
}

/// What is wrong with a typed semester, or null when nothing is.
String? semesterProblem(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return 'Name the semester these notes belong to.';
  if (text.length > 40) return 'Keep it under 40 characters.';
  return null;
}

/// A degree laid out on a calendar: when it started, when it ends, and how
/// many semesters are in between.
///
/// This is what lets the app answer "which semester am I in?" without asking.
/// Before it, the semester was a single piece of text in settings — change it
/// and last term's courses became indistinguishable from this term's, because
/// nothing recorded which term a course belonged to. A date range plus a count
/// gives every course a place in time and gives the student a record: this
/// semester, these courses, and under each course the notes.
class SemesterPlan {
  const SemesterPlan({
    required this.system,
    this.university,
    this.start,
    this.end,
    this.manualSemester,
  });

  final SemesterSystem system;
  final String? university;

  /// The day the degree began. Everything is measured from here.
  final DateTime? start;

  /// When it is expected to finish. Optional: without it the app falls back to
  /// a nominal semester length, because a student who knows they started in
  /// January should not have to know their graduation date to get a sensible
  /// answer.
  final DateTime? end;

  /// Set when the student has moved themselves off the computed semester.
  ///
  /// Universities slip. A term that was supposed to start in June starts in
  /// August, and an app that insists otherwise is arguing with somebody about
  /// their own degree. Once this is set it wins until they clear it.
  final int? manualSemester;

  /// How many semesters this degree has.
  ///
  /// From the system where it names one; for "something else", from the span
  /// itself at a nominal six months each, with at least one.
  int get count {
    if (system.count > 0) return system.count;
    final span = _spanDays;
    if (span == null) return 1;
    final n = (span / _nominalDays).round();
    return n < 1 ? 1 : n;
  }

  /// Nominal length of one semester under this system, in days.
  double get _nominalDays {
    switch (system) {
      case SemesterSystem.tri:
        return 365.25 / 3;
      case SemesterSystem.bi:
      case SemesterSystem.custom:
        return 365.25 / 2;
    }
  }

  int? get _spanDays {
    final a = start;
    final b = end;
    if (a == null || b == null) return null;
    final days = b.difference(a).inDays;
    return days > 0 ? days : null;
  }

  /// How long one semester lasts, in days.
  ///
  /// The real span divided by the real count when both are known, so a
  /// three-year degree does not get four-year semesters. Otherwise nominal.
  double get semesterLengthDays {
    final span = _spanDays;
    if (span != null && count > 0) return span / count;
    return _nominalDays;
  }

  /// Whether the app can work the semester out at all.
  bool get isDated => start != null;

  /// Which semester [on] falls in, or null when there is no start date.
  ///
  /// Clamped at both ends: before the degree began it is the first semester,
  /// after it should have finished it is the last. Neither is a lie worth
  /// telling differently — a student on an extended final year is still in
  /// their final semester as far as their notes are concerned.
  int? semesterOn(DateTime on) {
    final from = start;
    if (from == null) return null;

    final elapsed = on.difference(from).inDays;
    if (elapsed < 0) return 1;

    final n = (elapsed / semesterLengthDays).floor() + 1;
    if (n < 1) return 1;
    if (n > count) return count;
    return n;
  }

  /// The semester to show: what the student set if they set one, else the
  /// computed one.
  int? semesterFor(DateTime on) => manualSemester ?? semesterOn(on);

  /// When [number] begins, or null without a start date.
  DateTime? startOfSemester(int number) {
    final from = start;
    if (from == null) return null;
    final offset = (number - 1) * semesterLengthDays;
    return from.add(Duration(days: offset.round()));
  }

  SemesterPlan copyWith({
    SemesterSystem? system,
    String? university,
    DateTime? start,
    DateTime? end,
    int? manualSemester,
    bool clearManual = false,
    bool clearEnd = false,
  }) {
    return SemesterPlan(
      system: system ?? this.system,
      university: university ?? this.university,
      start: start ?? this.start,
      end: clearEnd ? null : (end ?? this.end),
      manualSemester: clearManual ? null : (manualSemester ?? this.manualSemester),
    );
  }
}

/// What is wrong with a pair of degree dates, or null when nothing is.
String? programmeDatesProblem(DateTime? start, DateTime? end) {
  if (start == null) return 'Pick the month your degree started.';
  if (end == null) return null;
  if (!end.isAfter(start)) return 'The finish has to come after the start.';
  final years = end.difference(start).inDays / 365.25;
  if (years > 12) return 'That is more than twelve years — check the dates.';
  return null;
}
