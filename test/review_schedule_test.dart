import 'package:flutter_test/flutter_test.dart';
import 'package:notenest/models/reminder_plan.dart';
import 'package:notenest/models/review_schedule.dart';

void main() {
  final now = DateTime(2026, 10, 21, 15, 30);

  group('applyRecall', () {
    test('remembered notes come back after longer and longer gaps', () {
      var step = 0;
      final gaps = <int>[];
      for (var i = 0; i < 4; i++) {
        final r = applyRecall(step, now, Recall.good);
        gaps.add(r.nextAt.difference(DateTime(2026, 10, 21)).inDays);
        step = r.step;
      }
      expect(gaps, [3, 7, 14, 30]);
    });

    test('the last remembered review masters the note', () {
      final r = applyRecall(masteredStep - 1, now, Recall.good);
      expect(r.mastered, isTrue);
      expect(r.step, masteredStep);
      expect(r.nextAt.difference(DateTime(2026, 10, 21)).inDays, masteredGap);
    });

    test('forgetting starts over, due tomorrow', () {
      final r = applyRecall(3, now, Recall.forgot);
      expect(r.step, 0);
      expect(r.nextAt, DateTime(2026, 10, 22));
      expect(r.mastered, isFalse);
    });

    test('hard keeps the step and halves the gap', () {
      final r = applyRecall(2, now, Recall.hard);
      expect(r.step, 2);
      // gap at step 2 is 7 days, half rounded up is 4
      expect(r.nextAt, DateTime(2026, 10, 25));
    });

    test('reviews land on the start of a day', () {
      expect(applyRecall(0, now, Recall.good).nextAt.hour, 0);
    });
  });

  group('isDue', () {
    test('null is never due, past and now are, tomorrow is not', () {
      expect(isDue(null, now), isFalse);
      expect(isDue(DateTime(2026, 10, 20), now), isTrue);
      expect(isDue(DateTime(2026, 10, 21), now), isTrue);
      expect(isDue(DateTime(2026, 10, 22), now), isFalse);
    });
  });

  group('review reminder', () {
    List<PlannedReminder> plan(List<DateTime> due, {Set<String> off = const {}}) =>
        planReminders(
          tasks: const [],
          exams: const [],
          now: now,
          disabledGroups: off,
          reviewDue: due,
        );

    test('nothing due, nothing planned', () {
      expect(plan(const []), isEmpty);
    });

    test('notes due today get this evening at six', () {
      final p = plan([DateTime(2026, 10, 20), DateTime(2026, 10, 21)]);
      expect(p.single.id, reviewId);
      expect(p.single.at, DateTime(2026, 10, 21, 18));
    });

    test('if six has passed, tomorrow evening', () {
      final late = planReminders(
        tasks: const [],
        exams: const [],
        now: DateTime(2026, 10, 21, 19),
        disabledGroups: const {},
        reviewDue: [DateTime(2026, 10, 21)],
      );
      expect(late.single.at, DateTime(2026, 10, 22, 18));
    });

    test('a later due date waits for that day', () {
      expect(plan([DateTime(2026, 10, 25)]).single.at, DateTime(2026, 10, 25, 18));
    });

    test('can be switched off', () {
      expect(plan([DateTime(2026, 10, 21)], off: {'reviews'}), isEmpty);
    });
  });
}
