import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notenest/models/note.dart';
import 'package:notenest/models/note_query.dart';
import 'package:notenest/theme/nest_theme.dart';
import 'package:notenest/widgets/nest_stepper.dart';

/// Builds a note without touching the database, so the search and filter
/// rules can be tested on their own.
Note note({
  int id = 1,
  String title = 'Note',
  String body = '',
  String? topic,
  List<String> tags = const [],
  int? subjectId,
  NoteType type = NoteType.text,
  bool important = false,
  StudyStatus status = StudyStatus.newNote,
  int updatedDaysAgo = 0,
  int? openedDaysAgo,
}) {
  final now = DateTime(2026, 1, 20);
  return Note(
    id: id,
    userId: 1,
    subjectId: subjectId,
    topic: topic,
    title: title,
    body: body,
    tags: tags,
    type: type,
    important: important,
    status: status,
    createdAt: now.subtract(const Duration(days: 30)),
    updatedAt: now.subtract(Duration(days: updatedDaysAgo)),
    openedAt:
        openedDaysAgo == null ? null : now.subtract(Duration(days: openedDaysAgo)),
  );
}

/// The three-step stepper used by the tests below, with the student on step two.
Widget stepperUnderTest({bool showHeader = true}) => MaterialApp(
      theme: nestTheme(),
      home: Scaffold(
        body: NestStepper(
          steps: const [
            NestStep(title: 'One', icon: Icons.person_rounded),
            NestStep(title: 'Two', icon: Icons.folder_rounded),
            NestStep(title: 'Three', icon: Icons.alarm_rounded),
          ],
          currentIndex: 1,
          showHeader: showHeader,
        ),
      ),
    );

void main() {
  testWidgets('stepper marks completed, current and upcoming steps',
      (tester) async {
    await tester.pumpWidget(stepperUnderTest());

    // Step one is done, so its icon is replaced by a tick.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    // The current and upcoming steps still show their own icons.
    expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
    expect(find.byIcon(Icons.alarm_rounded), findsOneWidget);

    // The header counts from one, so step index 1 reads as step 02.
    expect(find.text('STEP 02 / 03'), findsOneWidget);

    // Every step has its label on the rail. The step the student is on also
    // appears as the heading above the rail, so its title is on screen twice.
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsNWidgets(2));
    expect(find.text('Three'), findsOneWidget);
  });

  testWidgets('without the header every title appears exactly once',
      (tester) async {
    await tester.pumpWidget(stepperUnderTest(showHeader: false));

    // This is the other half of the test above: the duplicate "Two" comes from
    // the heading, not from the rail drawing the current step twice.
    expect(find.text('STEP 02 / 03'), findsNothing);
    for (final title in ['One', 'Two', 'Three']) {
      expect(find.text(title), findsOneWidget);
    }
  });

  group('tag normalization', () {
    test('lower-cases, trims and drops the hash students type', () {
      expect(normalizeTag('  #DBMS '), 'dbms');
      expect(normalizeTag('Normal   Forms'), 'normal forms');
    });

    test('never lets a comma into a tag, because commas separate them', () {
      expect(normalizeTag('sql,joins').contains(','), isFalse);
    });

    test('drops blanks and duplicates and caps the list', () {
      expect(normalizeTags(['dbms', 'DBMS', '  ', 'sql']), ['dbms', 'sql']);
      expect(
        normalizeTags(['a', 'b', 'c', 'd'], limit: 2),
        ['a', 'b'],
      );
    });
  });

  group('free-text search', () {
    final notes = [
      note(id: 1, title: 'Normalization', body: 'First normal form'),
      note(id: 2, title: 'Joins', body: 'Inner join and outer join'),
      note(id: 3, title: 'Revision plan', topic: 'DBMS', tags: ['exam']),
    ];

    test('matches the title, the body, the topic and the tags', () {
      expect(const NoteQuery(text: 'normalization').apply(notes).length, 1);
      expect(const NoteQuery(text: 'outer').apply(notes).first.id, 2);
      expect(const NoteQuery(text: 'dbms').apply(notes).first.id, 3);
      expect(const NoteQuery(text: 'exam').apply(notes).first.id, 3);
    });

    test('ignores case and the order the words are typed in', () {
      expect(const NoteQuery(text: 'JOIN inner').apply(notes).first.id, 2);
    });

    test('requires every word, so two words narrow rather than widen', () {
      expect(const NoteQuery(text: 'join normal').apply(notes), isEmpty);
    });

    test('an empty query returns everything', () {
      expect(const NoteQuery().apply(notes).length, 3);
    });
  });

  group('filters', () {
    final notes = [
      note(id: 1, subjectId: 7, type: NoteType.pdf, important: true),
      note(id: 2, subjectId: 7, status: StudyStatus.mastered),
      note(id: 3, subjectId: 8, tags: ['formula']),
    ];

    test('narrow by subject, kind, status, important mark and tag', () {
      expect(const NoteQuery(subjectId: 7).apply(notes).length, 2);
      expect(const NoteQuery(type: NoteType.pdf).apply(notes).first.id, 1);
      expect(
        const NoteQuery(status: StudyStatus.mastered).apply(notes).first.id,
        2,
      );
      expect(const NoteQuery(importantOnly: true).apply(notes).first.id, 1);
      expect(const NoteQuery(tag: 'formula').apply(notes).first.id, 3);
    });

    test('a tag filter is exact, so "form" does not match "formula"', () {
      expect(const NoteQuery(tag: 'form').apply(notes), isEmpty);
    });

    test('filters combine, so a wrong pairing returns nothing', () {
      expect(
        const NoteQuery(subjectId: 8, importantOnly: true).apply(notes),
        isEmpty,
      );
    });

    test('clearing filters keeps the words and the subject', () {
      const q = NoteQuery(
        text: 'join',
        subjectId: 7,
        importantOnly: true,
        tag: 'formula',
        sort: NoteSort.titleAZ,
      );
      final cleared = q.withoutFilters();
      expect(cleared.text, 'join');
      expect(cleared.subjectId, 7);
      expect(cleared.sort, NoteSort.titleAZ);
      expect(cleared.activeFilters, 0);
    });

    test('tapping an active chip switches it off again', () {
      const q = NoteQuery(type: NoteType.pdf);
      expect(q.toggleType(NoteType.pdf).type, isNull);
      expect(q.toggleType(NoteType.image).type, NoteType.image);
    });
  });

  group('sort order', () {
    final notes = [
      note(id: 1, title: 'Beta', updatedDaysAgo: 1, openedDaysAgo: 5),
      note(id: 2, title: 'Alpha', updatedDaysAgo: 9),
      note(id: 3, title: 'Gamma', updatedDaysAgo: 4, openedDaysAgo: 1),
    ];

    List<int> idsFor(NoteSort sort) =>
        NoteQuery(sort: sort).apply(notes).map((n) => n.id!).toList();

    test('newest and oldest are mirror images', () {
      expect(idsFor(NoteSort.newest), [1, 3, 2]);
      expect(idsFor(NoteSort.oldest), [2, 3, 1]);
    });

    test('title order ignores case', () {
      expect(idsFor(NoteSort.titleAZ), [2, 1, 3]);
    });

    test('recently opened puts never-opened notes last', () {
      expect(idsFor(NoteSort.recentlyOpened), [3, 1, 2]);
    });
  });
}
