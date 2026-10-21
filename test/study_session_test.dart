import 'package:flutter_test/flutter_test.dart';
import 'package:notenest/models/study_session.dart';

StudySession s(DateTime at, int minutes) =>
    StudySession(userId: 1, startedAt: at, minutes: minutes);

void main() {
  final today = DateTime(2026, 10, 21, 20);

  test('minutes are totalled per day', () {
    final list = [
      s(DateTime(2026, 10, 21, 9), 25),
      s(DateTime(2026, 10, 21, 18), 45),
      s(DateTime(2026, 10, 20, 9), 30),
    ];
    expect(minutesOn(list, today), 70);
    expect(minutesOn(list, DateTime(2026, 10, 20)), 30);
    expect(minutesOn(list, DateTime(2026, 10, 19)), 0);
  });

  test('the week is seven days, oldest first, ending today', () {
    final list = [
      s(DateTime(2026, 10, 21), 10),
      s(DateTime(2026, 10, 15), 5),
    ];
    final week = minutesPerDay(list, today);
    expect(week.length, 7);
    expect(week.last, 10);
    expect(week.first, 5);
  });

  test('a streak counts consecutive days ending today', () {
    final list = [
      s(DateTime(2026, 10, 21), 5),
      s(DateTime(2026, 10, 20), 5),
      s(DateTime(2026, 10, 19), 5),
      s(DateTime(2026, 10, 17), 5),
    ];
    expect(studyStreak(list, today), 3);
  });

  test('nothing yet today does not break yesterday\'s run', () {
    final list = [
      s(DateTime(2026, 10, 20), 5),
      s(DateTime(2026, 10, 19), 5),
    ];
    expect(studyStreak(list, today), 2);
  });

  test('a missed day ends the run', () {
    expect(studyStreak([s(DateTime(2026, 10, 18), 5)], today), 0);
  });

  test('minutes read naturally', () {
    expect(formatMinutes(40), '40 min');
    expect(formatMinutes(60), '1 h');
    expect(formatMinutes(85), '1 h 25 min');
  });

  test('a session survives the database map', () {
    final a = s(DateTime(2026, 10, 21, 9), 25);
    final b = StudySession.fromMap(a.toMap());
    expect(b.minutes, 25);
    expect(b.startedAt, a.startedAt);
  });
}
