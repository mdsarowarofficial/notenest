/// When a note is due to be looked at again.
///
/// Spaced repetition in its smallest form: each time a note is remembered, the
/// gap before the next look grows; each time it is forgotten, the gap starts
/// over. Revision stops being "read everything again before the exam" and
/// becomes a few notes a day, each one when it is about to be forgotten.
///
/// Plain Dart with no database or widgets, like the other models.
library;

/// Days to wait after each remembered review: the first review comes a day
/// after learning, then 3, 7, 14, 30.
const reviewGaps = [1, 3, 7, 14, 30];

/// A note remembered this many times in a row counts as mastered.
int get masteredStep => reviewGaps.length;

/// After mastery a note is still checked, but only now and then.
const masteredGap = 60;

/// How well a note was remembered.
enum Recall { forgot, hard, good }

/// Where a note stands after a review.
class ReviewResult {
  const ReviewResult({
    required this.step,
    required this.nextAt,
    required this.mastered,
  });

  /// How many times in a row it has been remembered.
  final int step;

  final DateTime nextAt;

  /// True once the last gap has been cleared.
  final bool mastered;
}

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// The date a review lands on: [days] after [from], at the start of the day,
/// so "due today" means from the morning rather than from the exact minute
/// the last review happened.
DateTime dueDay(DateTime from, int days) =>
    _startOfDay(from).add(Duration(days: days));

/// What happens to a note at [step] when it is reviewed on [now] and
/// remembered [recall].
ReviewResult applyRecall(int step, DateTime now, Recall recall) {
  final current = step.clamp(0, masteredStep);
  switch (recall) {
    case Recall.forgot:
      return ReviewResult(
        step: 0,
        nextAt: dueDay(now, reviewGaps.first),
        mastered: false,
      );
    case Recall.hard:
      // Seen again at half the usual gap, and the step does not advance.
      final gap = current >= reviewGaps.length ? reviewGaps.last : reviewGaps[current];
      return ReviewResult(
        step: current,
        nextAt: dueDay(now, (gap / 2).ceil().clamp(1, 30)),
        mastered: false,
      );
    case Recall.good:
      final next = current + 1;
      if (next >= masteredStep) {
        return ReviewResult(
          step: masteredStep,
          nextAt: dueDay(now, masteredGap),
          mastered: true,
        );
      }
      return ReviewResult(
        step: next,
        nextAt: dueDay(now, reviewGaps[next]),
        mastered: false,
      );
  }
}

/// How many days from now each answer would put the note off, for the labels
/// on the review buttons.
int daysFor(int step, DateTime now, Recall recall) {
  final r = applyRecall(step, now, recall);
  return r.nextAt.difference(_startOfDay(now)).inDays;
}

/// Whether a note scheduled for [nextAt] is due on [now].
bool isDue(DateTime? nextAt, DateTime now) =>
    nextAt != null && !nextAt.isAfter(now);
