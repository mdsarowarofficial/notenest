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
