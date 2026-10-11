import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notenest/models/note.dart';
import 'package:notenest/models/note_query.dart';
import 'package:notenest/models/transcript.dart';
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

  // ------------------------------------------------- Activity 06: transcripts

  group('tidying a transcript', () {
    test('collapses spacing and closes the last sentence', () {
      expect(cleanTranscript('hello    world'), 'hello world.');
      expect(cleanTranscript('hello , world .'), 'hello, world.');
    });

    test('leaves an empty transcript empty rather than a bare full stop', () {
      expect(cleanTranscript('   '), '');
    });

    test('counts words, not punctuation', () {
      expect(wordCount('hello world .'), 2);
      expect(wordCount('   '), 0);
    });
  });

  group('splitting speech into sentences', () {
    test('splits where the recogniser supplied full stops', () {
      expect(
        splitSentences('First normal form. Second normal form.').length,
        2,
      );
    });

    test('splits a long unpunctuated run at a spoken list cue', () {
      // This is the normal case for dictation: the recogniser returns one
      // enormous run of words with no punctuation at all. Without the cue
      // fallback the whole lecture would stay a single sentence and nothing
      // below could structure it.
      final sentences = splitSentences(
        'we will cover normalization today and it removes redundancy from '
        'tables next we will look at joins which combine rows from two tables',
      );
      expect(sentences.length, 2);
      expect(sentences.first.endsWith('.'), isTrue);
      expect(sentences.last.startsWith('next'), isTrue);
    });

    test('leaves a short sentence alone even when it holds a cue word', () {
      expect(splitSentences('first normal form.').length, 1);
    });
  });

  group('spotting what the lecturer flagged', () {
    test('finds an emphasis cue anywhere in the sentence', () {
      expect(hasEmphasisCue('This is important.'), isTrue);
      expect(hasEmphasisCue('Remember to normalize first.'), isTrue);
      expect(hasEmphasisCue('This one comes up for the exam.'), isTrue);
      expect(hasEmphasisCue('We looked at three tables.'), isFalse);
    });

    test('a list cue only counts at the start of the sentence', () {
      expect(startsListItem('First, every column holds one value.'), isTrue);
      expect(startsListItem('Next we normalize.'), isTrue);
      expect(startsListItem('The first form is the simple one.'), isFalse);
    });
  });

  group('suggesting a title', () {
    test('drops the throat-clearing a speaker starts with', () {
      expect(
        suggestTitle(
          ['Okay so normalization in database systems means organizing '
              'tables.'],
        ),
        'Normalization in database systems means organizing tables',
      );
    });

    test('stops at the word limit', () {
      expect(
        suggestTitle(['one two three four five six seven eight nine ten.']),
        'One two three four five six seven eight',
      );
    });

    test('gives nothing back when the opening was all filler', () {
      expect(suggestTitle(['Okay so.']), '');
      expect(suggestTitle([]), '');
    });
  });

  group('structuring a dictation', () {
    const spoken = 'Today we will cover normalization. '
        'First, every column must hold one value. '
        'Second, no partial dependency. '
        'This is important for the exam.';

    test('lifts the flagged sentence into key points', () {
      final structured = structureTranscript(spoken);
      expect(structured.sentenceCount, 4);
      expect(structured.keyPoints.length, 1);
      expect(structured.keyPoints.first, contains('important'));
    });

    test('groups consecutive spoken list items into one block', () {
      final structured = structureTranscript(spoken);
      expect(structured.blocks.length, 3);
      expect(structured.blocks[0].bulleted, isFalse);
      expect(structured.blocks[1].bulleted, isTrue);
      expect(structured.blocks[1].lines.length, 2);
      expect(structured.blocks[2].bulleted, isFalse);
    });

    test('key points lead, and the transcript still keeps every sentence', () {
      final body = structuredBody(structureTranscript(spoken));
      expect(body.startsWith('KEY POINTS'), isTrue);
      expect(body, contains('• First, every column must hold one value.'));
      expect(body, contains('TRANSCRIPT'));

      // The flagged sentence is deliberately in both places: key points are a
      // summary to revise from, and removing it from the transcript would
      // leave a gap where the lecturer actually said it.
      final occurrences =
          'for the exam'.allMatches(body).length;
      expect(occurrences, 2);
    });

    test('no Key points heading when it would repeat the whole transcript',
        () {
      // What the recogniser actually returns when it supplies no punctuation:
      // one long sentence, which is both the only key point and the entire
      // transcript. Printing both sections would show the same line twice.
      final structured = structureTranscript(
        'normalisation removes redundancy this is important for the exam.',
      );
      expect(structured.sentenceCount, 1);
      expect(structured.keyPoints.length, 1);

      final body = structuredBody(structured);
      expect(body.contains('KEY POINTS'), isFalse);
      expect(body.contains('TRANSCRIPT'), isFalse);
      expect('for the exam'.allMatches(body).length, 1);
    });

    test('nothing in, nothing out', () {
      final structured = structureTranscript('   ');
      expect(structured.isEmpty, isTrue);
      expect(structuredBody(structured), '');
    });
  });

  group('tags and clock', () {
    test('only suggests a tag whose words were actually spoken', () {
      expect(
        suggestedTagsFor(
          'we studied normalization and joins today',
          ['dbms', 'joins', 'formula'],
        ),
        ['joins'],
      );
      expect(suggestedTagsFor('anything at all', const []), isEmpty);
    });

    test('formats a length the way a player does', () {
      expect(formatClock(const Duration(seconds: 7)), '0:07');
      expect(formatClock(const Duration(minutes: 7, seconds: 4)), '7:04');
      expect(
        formatClock(const Duration(hours: 1, minutes: 2, seconds: 11)),
        '1:02:11',
      );
    });
  });
}
