import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notenest/data/doc_paginator.dart';
import 'package:notenest/models/attachment.dart';
import 'package:notenest/models/cover_spec.dart';
import 'package:notenest/models/doc_text.dart';
import 'package:notenest/models/exam.dart';
import 'package:notenest/models/university.dart';
import 'package:notenest/models/note.dart';
import 'package:notenest/models/note_bundle.dart';
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

  // -------------------------------------------- Activity 07: shared notes

  NoteBundle sample({
    String title = 'Normalization',
    String sharedBy = 'Rafi',
    List<BundleFile> files = const [],
    SharePolicy policy = SharePolicy.open,
  }) =>
      NoteBundle(
        title: title,
        body: 'First normal form means every column holds one value.',
        topic: 'Normal forms',
        tags: const ['dbms', 'exam'],
        subjectName: 'Database Systems',
        subjectCode: 'CSE112',
        sharedBy: sharedBy,
        policy: policy,
        files: files,
        writtenAt: DateTime(2026, 3, 12),
      );

  group('packing a note for a classmate', () {
    test('survives the round trip intact', () {
      final before = sample();
      final after = NoteBundle.decode(before.encode());

      expect(after.title, before.title);
      expect(after.body, before.body);
      expect(after.topic, before.topic);
      expect(after.tags, before.tags);
      expect(after.subjectCode, 'CSE112');
      expect(after.subjectName, 'Database Systems');
      expect(after.sharedBy, 'Rafi');
      expect(after.writtenAt, before.writtenAt);
    });

    test('carries attachments as bytes, not as paths', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final before = sample(files: [
        BundleFile(
          type: AttachmentType.image,
          fileName: 'page1.jpg',
          bytes: bytes,
        ),
      ]);
      final after = NoteBundle.decode(before.encode());

      expect(after.files.length, 1);
      expect(after.files.first.bytes, bytes);
      expect(after.files.first.type, AttachmentType.image);
      expect(after.fileBytes, 5);
    });

    test('the sharing request travels with the note', () {
      final after = NoteBundle.decode(
        sample(policy: SharePolicy.reference).encode(),
      );
      expect(after.policy, SharePolicy.reference);
    });

    test('names the file after the note', () {
      expect(sample(title: 'Normal Forms!').suggestedFileName,
          'normal-forms.notenest');
      expect(sample(title: '   ').suggestedFileName, 'note.notenest');
    });
  });

  group('a file from another phone is not trusted', () {
    BundleError errorFrom(String source) {
      try {
        NoteBundle.decode(source);
      } on BundleException catch (e) {
        return e.error;
      }
      fail('expected the file to be refused');
    }

    test('refuses something that is not JSON at all', () {
      expect(errorFrom('this is a photo, not a note'), BundleError.notJson);
    });

    test('refuses JSON that is not a NoteNest note', () {
      expect(errorFrom('{"hello":"world"}'), BundleError.wrongFormat);
    });

    test('refuses a note from a newer NoteNest instead of half-reading it',
        () {
      final source = sample().encode().replaceFirst(
            '"version": ${NoteBundle.formatVersion}',
            '"version": ${NoteBundle.formatVersion + 1}',
          );
      expect(errorFrom(source), BundleError.tooNew);
    });

    test('refuses a note with no title and no body', () {
      expect(
        errorFrom(
          '{"format":"${NoteBundle.formatName}","version":1,'
          '"note":{"title":"","body":""}}',
        ),
        BundleError.missingNote,
      );
    });

    test('refuses attachment data that is not really base64', () {
      expect(
        errorFrom(
          '{"format":"${NoteBundle.formatName}","version":1,'
          '"note":{"title":"Hi","body":"there"},'
          '"attachments":[{"type":"image","fileName":"a.jpg",'
          '"data":"!!!not base64!!!"}]}',
        ),
        BundleError.corrupt,
      );
    });

    test('strips directories out of an attachment name', () {
      // The "../../" trick: a crafted name must never reach the file system.
      final before = sample(files: [
        BundleFile(
          type: AttachmentType.image,
          fileName: '../../../etc/passwd',
          bytes: Uint8List.fromList([9]),
        ),
      ]);
      final after = NoteBundle.decode(before.encode());

      expect(after.files.first.fileName, 'passwd');
      expect(after.files.first.fileName.contains('/'), isFalse);
      expect(after.files.first.fileName.contains('..'), isFalse);
    });

    test('a name of only dots cannot become a file name', () {
      final after = NoteBundle.decode(
        sample(files: [
          BundleFile(
            type: AttachmentType.pdf,
            fileName: '..',
            bytes: Uint8List.fromList([9]),
          ),
        ]).encode(),
      );
      expect(after.files.first.fileName, 'attachment');
      expect(after.files.first.safeExtension, 'pdf');
    });

    test('an extension is only ever plain letters and digits', () {
      final after = NoteBundle.decode(
        sample(files: [
          BundleFile(
            type: AttachmentType.image,
            fileName: 'note.j/p g',
            bytes: Uint8List.fromList([9]),
          ),
        ]).encode(),
      );
      // Stripping the directory leaves "p g", which has no extension at all,
      // so the type's own default is used rather than anything from the name.
      expect(after.files.first.fileName, 'p g');
      expect(after.files.first.safeExtension, 'jpg');
    });

    test('an oversized note is refused rather than loaded', () {
      final big = base64Encode(
        Uint8List(NoteBundle.maxTotalBytes + 1024),
      );
      expect(
        errorFrom(
          '{"format":"${NoteBundle.formatName}","version":1,'
          '"note":{"title":"Big","body":"x"},'
          '"attachments":[{"type":"pdf","fileName":"b.pdf","data":"$big"}]}',
        ),
        BundleError.tooBig,
      );
    });

    test('an unnamed sender still gets a name to show', () {
      final after = NoteBundle.decode(
        '{"format":"${NoteBundle.formatName}","version":1,'
        '"note":{"title":"Hi","body":"there"}}',
      );
      expect(after.sharedBy, 'A classmate');
      expect(after.policy, SharePolicy.open);
    });

    test('over-long text is cut rather than rejected', () {
      final after = NoteBundle.decode(
        NoteBundle(
          title: 'T' * 400,
          body: 'b',
          sharedBy: 'Rafi',
          writtenAt: DateTime(2026),
        ).encode(),
      );
      expect(after.title.length, NoteBundle.maxTitle);
    });
  });

  group('readable sizes', () {
    test('reads the way a student expects', () {
      expect(readableBytes(0), '0 KB');
      expect(readableBytes(900), '900 B');
      expect(readableBytes(2048), '2 KB');
      expect(readableBytes(3 * 1024 * 1024), '3.0 MB');
    });
  });

  group('exam dates', () {
    test('a date is a day, not a moment', () {
      expect(atMidnight(DateTime(2026, 5, 4, 23, 59)), DateTime(2026, 5, 4));
    });

    test('whole days are counted regardless of the time of day', () {
      final from = DateTime(2026, 6, 10, 23, 30);
      expect(daysUntil(DateTime(2026, 6, 12, 1), from: from), 2);
      expect(daysUntil(DateTime(2026, 6, 10, 0, 1), from: from), 0);
      expect(daysUntil(DateTime(2026, 6, 8), from: from), -2);
    });

    test('a daylight-saving shift in between does not lose a day', () {
      // 8 March 2026 is a clocks-forward date in several timezones. Measured
      // in local hours the gap below is 47, which would round down to 1.
      expect(
        daysUntil(DateTime(2026, 3, 10), from: DateTime(2026, 3, 8)),
        2,
      );
    });

    test('the countdown reads as a sentence would', () {
      expect(countdownLabel(0), 'Today');
      expect(countdownLabel(1), 'Tomorrow');
      expect(countdownLabel(6), 'in 6 days');
      expect(countdownLabel(-1), 'Yesterday');
      expect(countdownLabel(-4), '4 days ago');
    });

    test('an exam survives the trip to the database and back', () {
      final exam = Exam(
        userId: 1,
        subjectId: 3,
        title: 'Mid term',
        date: DateTime(2026, 5, 4, 14, 30),
        kind: ExamKind.quiz,
        remindDays: 3,
        createdAt: DateTime(2026, 4, 1),
      );
      final back = Exam.fromMap({...exam.toMap(), 'id': 7});

      expect(back.id, 7);
      expect(back.title, 'Mid term');
      expect(back.subjectId, 3);
      expect(back.kind, ExamKind.quiz);
      expect(back.remindDays, 3);
      // The time of day was dropped on the way in, which is the point.
      expect(back.date, DateTime(2026, 5, 4));
    });

    test('an unrecognised kind falls back to an exam rather than crashing', () {
      expect(ExamKindData.fromKey('assignment'), ExamKind.assignment);
      expect(ExamKindData.fromKey('viva'), ExamKind.exam);
      expect(ExamKindData.fromKey(null), ExamKind.exam);
    });

    test('today is today, and last week is past', () {
      Exam on(DateTime d) => Exam(
            userId: 1,
            title: 'T',
            date: d,
            createdAt: DateTime(2026),
          );
      final now = DateTime.now();
      expect(on(now).isToday, isTrue);
      expect(on(now).isPast, isFalse);
      expect(on(now.subtract(const Duration(days: 7))).isPast, isTrue);
    });
  });

  group('reminders', () {
    Exam withReminder(int daysFromNow, int? lead) => Exam(
          userId: 1,
          title: 'Mid term',
          date: DateTime.now().add(Duration(days: daysFromNow)),
          remindDays: lead,
          createdAt: DateTime(2026),
        );

    test('no reminder is never due', () {
      expect(withReminder(1, null).hasReminder, isFalse);
      expect(withReminder(1, null).reminderIsDue, isFalse);
    });

    test('a reminder is due once its window opens', () {
      expect(withReminder(5, 3).reminderIsDue, isFalse);
      expect(withReminder(3, 3).reminderIsDue, isTrue);
      expect(withReminder(1, 3).reminderIsDue, isTrue);
      expect(withReminder(0, 3).reminderIsDue, isTrue);
    });

    test('a reminder stops once the date has passed', () {
      expect(withReminder(-1, 3).reminderIsDue, isFalse);
      expect(withReminder(-30, 7).reminderIsDue, isFalse);
    });

    test('the lead is stored as days, so moving the exam moves it', () {
      final exam = withReminder(10, 7);
      final moved = exam.copyWith(date: DateTime.now());
      expect(moved.remindDays, 7);
      expect(moved.reminderIsDue, isTrue);
    });

    test('a reminder can be cleared, which copyWith alone cannot do', () {
      final exam = withReminder(2, 1);
      expect(exam.copyWith(clearReminder: true).remindDays, isNull);
      // Passing null without the flag means "leave it as it was".
      expect(exam.copyWith(remindDays: null).remindDays, 1);
    });

    test('the lead reads the way it would be spoken', () {
      expect(reminderLabel(null), 'Off');
      expect(reminderLabel(1), '1 day before');
      expect(reminderLabel(3), '3 days before');
      expect(reminderLabel(7), '1 week before');
    });
  });

  group('revision order', () {
    test('what the student starred outranks anything the app worked out', () {
      final ordered = revisionOrder([
        note(id: 1, status: StudyStatus.read, openedDaysAgo: 1),
        note(
          id: 2,
          status: StudyStatus.mastered,
          important: true,
          openedDaysAgo: 0,
        ),
        note(id: 3, status: StudyStatus.review, openedDaysAgo: 2),
        note(id: 4, status: StudyStatus.newNote),
      ]);
      // 2 is starred even though it is Mastered and was just opened; then the
      // status ranking takes over: Review, New, Read.
      expect(ordered.map((n) => n.id), [2, 3, 4, 1]);
    });

    test('Review sits above New, because the student said so themselves', () {
      final ordered = revisionOrder([
        note(id: 1, status: StudyStatus.newNote),
        note(id: 2, status: StudyStatus.mastered),
        note(id: 3, status: StudyStatus.review),
        note(id: 4, status: StudyStatus.read),
      ]);
      expect(ordered.map((n) => n.id), [3, 1, 4, 2]);
    });

    test('a note never opened comes before one opened long ago', () {
      final ordered = revisionOrder([
        note(id: 1, status: StudyStatus.read, openedDaysAgo: 9),
        note(id: 2, status: StudyStatus.read),
        note(id: 3, status: StudyStatus.read, openedDaysAgo: 1),
      ]);
      expect(ordered.map((n) => n.id), [2, 1, 3]);
    });

    test('the order does not shuffle between builds', () {
      final ordered = revisionOrder([
        note(id: 1, updatedDaysAgo: 1),
        note(id: 2, updatedDaysAgo: 5),
      ]);
      expect(ordered.map((n) => n.id), [2, 1]);
    });

    test('mastered notes are kept at the bottom, not hidden', () {
      final ordered = revisionOrder([
        note(id: 1, status: StudyStatus.mastered),
        note(id: 2, status: StudyStatus.newNote),
      ]);
      expect(ordered.length, 2);
      expect(ordered.last.id, 1);
    });

    test('the list handed in is left alone', () {
      final input = [
        note(id: 1, status: StudyStatus.read),
        note(id: 2, status: StudyStatus.review),
      ];
      revisionOrder(input);
      expect(input.map((n) => n.id), [1, 2]);
    });
  });

  group('daily target', () {
    test('nothing left means nothing to do today', () {
      expect(dailyTarget(remaining: 0, daysLeft: 5), 0);
    });

    test('a part day still counts as a day', () {
      expect(dailyTarget(remaining: 10, daysLeft: 3), 4);
      expect(dailyTarget(remaining: 9, daysLeft: 3), 3);
      expect(dailyTarget(remaining: 1, daysLeft: 10), 1);
    });

    test('with no days left, everything is today', () {
      expect(dailyTarget(remaining: 7, daysLeft: 0), 7);
      expect(dailyTarget(remaining: 7, daysLeft: -3), 7);
    });
  });

  group('progress and verdict', () {
    test('an empty subject is not zero per cent of something', () {
      expect(masteredShare(const []), 0);
    });

    test('mastered share counts only what is marked mastered', () {
      expect(
        masteredShare([
          note(id: 1, status: StudyStatus.mastered),
          note(id: 2, status: StudyStatus.read),
          note(id: 3, status: StudyStatus.review),
          note(id: 4, status: StudyStatus.newNote),
        ]),
        0.25,
      );
    });

    test('the verdict says what is true, not what is encouraging', () {
      expect(
        revisionVerdict(remaining: 0, daysLeft: 3, total: 0),
        'No notes in this subject yet.',
      );
      expect(
        revisionVerdict(remaining: 0, daysLeft: 3, total: 5),
        'Everything here is marked Mastered.',
      );
      expect(
        revisionVerdict(remaining: 3, daysLeft: 0, total: 5),
        '3 left and the exam is today.',
      );
      expect(
        revisionVerdict(remaining: 3, daysLeft: -2, total: 5),
        '3 still not mastered.',
      );
      expect(
        revisionVerdict(remaining: 3, daysLeft: 5, total: 5),
        'One note a day clears this in time.',
      );
      expect(
        revisionVerdict(remaining: 10, daysLeft: 3, total: 12),
        '4 notes a day clears this in time.',
      );
    });
  });

  group('cover page', () {
    const filled = CoverSpec(
      institution: 'Daffodil International University',
      department: 'Department of CSE',
      courseCode: 'CSE 112',
      courseTitle: 'Data Structures',
      kind: CoverKind.labReport,
      serial: '3',
      title: 'Linked lists',
      studentName: 'Md. Sarowar Hossain',
      studentId: '221-15-1234',
      teacherName: 'Dr. A. Rahman',
    );

    test('the course line only shows a dash when both halves exist', () {
      expect(filled.courseLine, 'CSE 112 — Data Structures');
      expect(
        const CoverSpec(courseCode: 'CSE 112').courseLine,
        'CSE 112',
      );
      expect(
        const CoverSpec(courseTitle: 'Data Structures').courseLine,
        'Data Structures',
      );
      expect(const CoverSpec().courseLine, '');
    });

    test('the numbered field is named after what is being handed in', () {
      expect(CoverKind.assignment.serialLabel, 'Assignment No.');
      expect(CoverKind.labReport.serialLabel, 'Experiment No.');
      // A thesis has no number, so the field is hidden rather than invented.
      expect(CoverKind.thesis.serialLabel, isNull);
    });

    test('the numbered line is hidden when the kind has no number', () {
      expect(filled.serialLine, 'Experiment No. 3');
      expect(filled.copyWith(serial: '').serialLine, isNull);
      expect(filled.copyWith(kind: CoverKind.thesis).serialLine, isNull);
    });

    test('empty rows are left off the page rather than printed blank', () {
      expect(filled.submittedBy, const [
        CoverRow('Name', 'Md. Sarowar Hossain'),
        CoverRow('ID', '221-15-1234'),
      ]);
      expect(filled.submittedTo, const [CoverRow('Name', 'Dr. A. Rahman')]);
      expect(const CoverSpec().submittedBy, isEmpty);
    });

    test('what is missing is named, and does not block the export', () {
      expect(filled.missing, isEmpty);
      expect(filled.isComplete, isTrue);

      final bare = const CoverSpec().missing;
      expect(bare, contains('Institution'));
      expect(bare, contains('Course'));
      expect(bare, contains('Your name'));
      // The label follows the kind, as the form does.
      expect(const CoverSpec(kind: CoverKind.labReport).missing,
          contains('Experiment name'));
    });

    test('the file name is safe and readable', () {
      expect(filled.suggestedFileName, 'CSE-112-lab-report-3.pdf');
      // Nothing to name it after still produces a usable file name.
      expect(const CoverSpec().suggestedFileName, 'assignment.pdf');
      // Slashes and colons would break a file name on some systems.
      expect(
        const CoverSpec(courseCode: 'CSE/112: Part 1').suggestedFileName,
        'CSE112-Part-1-assignment.pdf',
      );
    });

    test('a draft survives being stored and read back', () {
      final back = CoverSpec.decode(filled.encode());
      expect(back.institution, filled.institution);
      expect(back.kind, CoverKind.labReport);
      expect(back.serial, '3');
      expect(back.accentIndex, filled.accentIndex);
      expect(back.showBorder, isTrue);
    });

    test('a corrupt draft hands back an empty form rather than throwing', () {
      expect(CoverSpec.decode(null).institution, '');
      expect(CoverSpec.decode('').institution, '');
      expect(CoverSpec.decode('not json at all').institution, '');
      expect(CoverSpec.decode('[1,2,3]').institution, '');
      expect(CoverSpec.decode('{"kind":42}').kind, CoverKind.assignment);
    });

    test('the next draft keeps who you are and clears what you handed in', () {
      final next = filled.copyWith(submittedOn: DateTime(2026, 3, 2)).asNextDraft;
      expect(next.institution, filled.institution);
      expect(next.studentId, filled.studentId);
      expect(next.teacherName, filled.teacherName);
      // These are the fields that would be wrong next week.
      expect(next.title, '');
      expect(next.serial, '');
      expect(next.submittedOn, isNull);
    });

    test('a date can be cleared, which copyWith alone cannot do', () {
      final dated = filled.copyWith(submittedOn: DateTime(2026, 3, 2));
      expect(dated.copyWith(clearDate: true).submittedOn, isNull);
      // Passing null without the flag means "leave it as it was" — the same
      // distinction as Exam.clearReminder, and the bug this test was written
      // after finding.
      expect(
        dated.copyWith(submittedOn: null).submittedOn,
        DateTime(2026, 3, 2),
      );
    });

    test('an accent index out of range wraps instead of crashing', () {
      expect(const CoverSpec(accentIndex: 0).accent, coverAccents.first);
      expect(
        const CoverSpec(accentIndex: 99).accent,
        coverAccents[99 % coverAccents.length],
      );
    });

    test('a mixed colour is opaque and in range at every hue', () {
      for (var h = 0.0; h < 360; h += 7) {
        final argb = argbFromHue(h);
        expect(argb >> 24 & 0xFF, 0xFF, reason: 'hue $h should be opaque');
        expect(argb & 0xFFFFFF, inInclusiveRange(0, 0xFFFFFF));
      }
    });

    test('the hue wheel wraps instead of breaking', () {
      expect(argbFromHue(360), argbFromHue(0));
      expect(argbFromHue(-120), argbFromHue(240));
      expect(argbFromHue(400), argbFromHue(40));
    });

    test('each sixth of the wheel gives a different colour', () {
      final seen = {
        for (final h in [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]) argbFromHue(h),
      };
      expect(seen.length, 6);
    });

    test('a mixed colour outranks the swatch, and clears back to it', () {
      const mixed = CoverSpec(accentIndex: 2, customAccent: 0xFF112233);
      expect(mixed.accent, 0xFF112233);
      expect(mixed.copyWith(clearCustomAccent: true).accent, coverAccents[2]);
      // Passing null without the flag leaves it alone, as everywhere else.
      expect(mixed.copyWith(customAccent: null).accent, 0xFF112233);
    });

    test('the page options survive being stored and read back', () {
      const styled = CoverSpec(
        density: CoverDensity.compact,
        signatureStyle: SignatureStyle.level,
        frameStyle: FrameStyle.corners,
        customAccent: 0xFF445566,
      );
      final back = CoverSpec.decode(styled.encode());
      expect(back.density, CoverDensity.compact);
      expect(back.signatureStyle, SignatureStyle.level);
      expect(back.frameStyle, FrameStyle.corners);
      expect(back.customAccent, 0xFF445566);
    });

    test('an unknown option falls back rather than crashing', () {
      expect(CoverDensityData.fromKey('enormous'), CoverDensity.normal);
      expect(SignatureStyleData.fromKey(null), SignatureStyle.staggered);
      expect(FrameStyleData.fromKey('zigzag'), FrameStyle.dotted);
      // Tighter really is tighter, and airier really is airier.
      expect(CoverDensity.compact.scale, lessThan(CoverDensity.normal.scale));
      expect(CoverDensity.airy.scale, greaterThan(CoverDensity.normal.scale));
    });

    test('the date is written out without a weekday', () {
      expect(coverDateLabel(DateTime(2026, 10, 12)), '12 October 2026');
    });
  });

  group('university search', () {
    const all = [
      University(name: 'City University', countryCode: 'BD', domain: 'cityuniversity.edu.bd'),
      University(name: 'City University of New York', countryCode: 'US'),
      University(name: 'Daffodil International University', countryCode: 'BD'),
      University(name: 'North South University', countryCode: 'BD'),
      University(name: 'University of Dhaka', countryCode: 'BD'),
      University(name: 'Dhaka University of Engineering and Technology',
          countryCode: 'BD'),
      University(name: 'Oxford City College', countryCode: 'GB'),
    ];

    test('an exact name beats a name that merely starts with it', () {
      expect(universityScore('City University', 'city university'), 0);
      expect(universityScore('City University of New York', 'city university'), 1);
    });

    test('a word anywhere in the name counts, but less than the first', () {
      expect(universityScore('North South University', 'north'), 1);
      expect(universityScore('North South University', 'south'), 2);
      // "versity" is inside a word, so it is the weakest kind of match.
      expect(universityScore('North South University', 'versity'), 3);
    });

    test('several words match in any order', () {
      expect(
        universityScore('Dhaka University of Engineering and Technology',
            'dhaka eng'),
        4,
      );
      expect(universityScore('University of Dhaka', 'dhaka eng'), -1);
    });

    test('no match is -1, and an empty query matches nothing', () {
      expect(universityScore('University of Dhaka', 'harvard'), -1);
      expect(universityScore('University of Dhaka', ''), -1);
    });

    test('the obvious answer comes first', () {
      final found = searchUniversities(all, 'city', preferCountry: 'BD');
      expect(found.first.name, 'City University');
      // Same score, so the student's own country breaks the tie.
      expect(found[1].name, 'City University of New York');
      // "Oxford City College" matches on its second word, which ranks below
      // the two that open with it.
      expect(found.last.name, 'Oxford City College');
    });

    test('a better match beats home country, which only breaks ties', () {
      final found = searchUniversities(all, 'university', preferCountry: 'US');
      // "University of Dhaka" opens with the query, so it wins outright even
      // though the student's country is somewhere else. Country is a
      // tie-break, not a filter.
      expect(found.first.name, 'University of Dhaka');
      // Among the equally-matching rest, the US one does come first.
      expect(found.skip(1).first.countryCode, 'US');
      expect(found.any((u) => u.countryCode == 'BD'), isTrue);
    });

    test('an empty query offers the home country rather than the alphabet', () {
      final found = searchUniversities(all, '', preferCountry: 'BD');
      expect(found.every((u) => u.countryCode == 'BD'), isTrue);
      expect(found.length, 5);
    });

    test('the limit is honoured', () {
      expect(searchUniversities(all, 'university', limit: 2).length, 2);
    });

    test('initials skip the little words', () {
      expect(initialsOf('Daffodil International University'), 'DIU');
      // "of" is not an initial anyone writes on a seal.
      expect(initialsOf('University of Dhaka'), 'UD');
      expect(initialsOf('Brac University'), 'BU');
      expect(initialsOf(''), '');
      expect(initialsOf('   '), '');
    });
  });

  group('document text', () {
    test('the ampersand is escaped first, or the escapes get escaped', () {
      expect(escapeXml('a & b'), 'a &amp; b');
      expect(escapeXml('<w:t>'), '&lt;w:t&gt;');
      // The bug this ordering avoids: escaping < first would give &amp;lt;
      expect(escapeXml('5 < 6 & 7 > 2'), '5 &lt; 6 &amp; 7 &gt; 2');
    });

    test('blank lines separate paragraphs and wrapped lines are rejoined', () {
      final blocks = blocksFromPlainText(
        'This sentence was broken\nacross two lines by the PDF.\n'
        '\n'
        'And this is the next paragraph.',
      );
      expect(blocks.length, 2);
      expect(
        blocks.first.text,
        'This sentence was broken across two lines by the PDF.',
      );
      expect(blocks.first.style, DocStyle.body);
    });

    test('bullets and numbers are recognised, and the number is kept', () {
      final blocks = blocksFromPlainText(
        '- first\n'
        '• second\n'
        '1. third\n'
        '2) fourth',
      );
      expect(blocks.map((b) => b.style), [
        DocStyle.bullet,
        DocStyle.bullet,
        DocStyle.numbered,
        DocStyle.numbered,
      ]);
      expect(blocks[0].text, 'first');
      // A numbered item keeps its number: renumbering it could contradict the
      // text, which may refer to "step 3".
      expect(blocks[2].text, '1. third');
      expect(blocks[3].text, '2. fourth');
    });

    test('a heading is only guessed when several signs agree', () {
      expect(blocksFromPlainText('METHODOLOGY').first.style, DocStyle.heading);
      expect(blocksFromPlainText('3 Results').first.style, DocStyle.heading);
      expect(
        blocksFromPlainText('3.2.1 Sample preparation').first.style,
        DocStyle.subheading,
      );
      // Ends in a full stop, so it is a sentence.
      expect(blocksFromPlainText('Results.').first.style, DocStyle.body);
      // Too long to be a heading.
      expect(
        blocksFromPlainText('A' * 80).first.style,
        DocStyle.body,
      );
    });

    test('the bullet character lives in the drawing, not in the text', () {
      const block = DocBlock(DocStyle.bullet, 'first');
      expect(block.text, 'first');
      expect(docDisplayText(block), '•   first');
      // So a round trip cannot end up with two bullets.
      expect(docDisplayText(const DocBlock.body('plain')), 'plain');
    });

    test('words are counted across every block', () {
      expect(
        wordsIn(const [
          DocBlock(DocStyle.heading, 'Two words'),
          DocBlock.body('and three more words'),
        ]),
        6,
      );
      expect(wordsIn(const []), 0);
    });
  });

  group('docx writing', () {
    test('the document is a complete, namespaced part', () {
      final xml = buildWordDocumentXml(const [DocBlock.body('Hello')]);
      expect(xml, startsWith('<?xml version="1.0"'));
      expect(xml, contains('wordprocessingml/2006/main'));
      expect(xml, contains('<w:body>'));
      // Without a sectPr Word opens the file but has no page size for it.
      expect(xml, contains('<w:sectPr>'));
      expect(xml, contains('Hello'));
    });

    test('text is escaped on the way in', () {
      final xml = buildWordDocumentXml(
        const [DocBlock.body('Tom & Jerry <b>')],
      );
      expect(xml, contains('Tom &amp; Jerry &lt;b&gt;'));
      expect(xml, isNot(contains('Tom & Jerry')));
    });

    test('a bullet keeps its leading space', () {
      final xml = buildWordDocumentXml(
        const [DocBlock(DocStyle.bullet, 'item')],
      );
      // Without xml:space="preserve" Word trims "• " down to "•".
      expect(xml, contains('xml:space="preserve"'));
      expect(xml, contains('• item'));
    });

    test('formatting is written onto the run, not left to a missing style', () {
      final heading = buildWordDocumentXml(
        const [DocBlock(DocStyle.heading, 'Methods')],
      );
      // A w:pStyle of "Heading1" would need a styles.xml this package has not
      // got, and Word would render the heading as body text.
      expect(heading, isNot(contains('pStyle')));
      expect(heading, contains('<w:b/>'));
      expect(heading, contains('<w:sz w:val="32"/>'));

      final body = buildWordDocumentXml(const [DocBlock.body('Plain')]);
      expect(body, isNot(contains('<w:b/>')));
      expect(body, contains('<w:sz w:val="22"/>'));
    });

    test('an empty document still produces an openable part', () {
      final xml = buildWordDocumentXml(const []);
      expect(xml, contains('<w:body>'));
      expect(xml, contains('<w:p>'));
    });

    test('the package parts name each other correctly', () {
      expect(contentTypesXml, contains('/word/document.xml'));
      expect(rootRelsXml, contains('Target="word/document.xml"'));
    });
  });

  group('docx reading', () {
    String doc(String body) =>
        '<w:document xmlns:w="http://schemas.openxmlformats.org/'
        'wordprocessingml/2006/main"><w:body>$body</w:body></w:document>';

    test('text is read out of the runs', () {
      final blocks = blocksFromWordXml(doc(
        '<w:p><w:r><w:t>Hello </w:t></w:r><w:r><w:t>world</w:t></w:r></w:p>',
      ));
      expect(blocks.single.text, 'Hello world');
      expect(blocks.single.style, DocStyle.body);
    });

    test('a different namespace prefix is still read', () {
      // The "w" prefix is only a convention. A file using another prefix is
      // equally valid, and matching on the name "w:p" would read it as empty.
      final blocks = blocksFromWordXml(
        '<wd:document xmlns:wd="http://schemas.openxmlformats.org/'
        'wordprocessingml/2006/main"><wd:body>'
        '<wd:p><wd:r><wd:t>Still here</wd:t></wd:r></wd:p>'
        '</wd:body></wd:document>',
      );
      expect(blocks.single.text, 'Still here');
    });

    test('a named heading style is honoured', () {
      final blocks = blocksFromWordXml(doc(
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
        '<w:r><w:t>Chapter</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:pStyle w:val="Heading3"/></w:pPr>'
        '<w:r><w:t>Detail</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr>'
        '<w:r><w:t>Front</w:t></w:r></w:p>',
      ));
      expect(blocks.map((b) => b.style),
          [DocStyle.heading, DocStyle.subheading, DocStyle.title]);
    });

    test('a numbered paragraph becomes a list item', () {
      final blocks = blocksFromWordXml(doc(
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/></w:numPr></w:pPr>'
        '<w:r><w:t>point one</w:t></w:r></w:p>',
      ));
      expect(blocks.single.style, DocStyle.bullet);
    });

    test('an all-bold line is read as a heading when nothing else says so', () {
      final blocks = blocksFromWordXml(doc(
        '<w:p><w:r><w:rPr><w:b/><w:sz w:val="32"/></w:rPr>'
        '<w:t>Introduction</w:t></w:r></w:p>',
      ));
      expect(blocks.single.style, DocStyle.heading);
    });

    test('a bullet already in the text is not doubled', () {
      final blocks = blocksFromWordXml(doc(
        '<w:p><w:r><w:t>• already bulleted</w:t></w:r></w:p>',
      ));
      expect(blocks.single.text, 'already bulleted');
    });

    test('empty paragraphs are dropped', () {
      final blocks = blocksFromWordXml(doc(
        '<w:p/><w:p><w:r><w:t>   </w:t></w:r></w:p>'
        '<w:p><w:r><w:t>Real</w:t></w:r></w:p>',
      ));
      expect(blocks.single.text, 'Real');
    });

    test('words inside a table are kept even though the table is not', () {
      final blocks = blocksFromWordXml(doc(
        '<w:tbl><w:tr><w:tc>'
        '<w:p><w:r><w:t>cell text</w:t></w:r></w:p>'
        '</w:tc></w:tr></w:tbl>',
      ));
      // Losing the shape is a stated limitation. Losing the data silently
      // would be the worse of the two.
      expect(blocks.single.text, 'cell text');
    });

    test('a tab becomes a space rather than vanishing', () {
      final blocks = blocksFromWordXml(doc(
        '<w:p><w:r><w:t>Name</w:t><w:tab/><w:t>Value</w:t></w:r></w:p>',
      ));
      expect(blocks.single.text, 'Name Value');
    });
  });

  group('pagination', () {
    test('a short document is one page', () {
      final pages = paginateBlocks(const [
        DocBlock(DocStyle.heading, 'Short'),
        DocBlock.body('One line is not a book.'),
      ]);
      expect(pages.length, 1);
      expect(pages.single.length, 2);
    });

    test('an empty document is still one page, not none', () {
      expect(paginateBlocks(const []).length, 1);
    });

    test('a long document runs onto more pages', () {
      final blocks = [
        for (var i = 0; i < 120; i++)
          DocBlock.body('Paragraph $i. ${'Filler sentence. ' * 6}'),
      ];
      final pages = paginateBlocks(blocks);
      expect(pages.length, greaterThan(1));
      // Nothing is dropped on the way: every page has something on it.
      expect(pages.every((p) => p.isNotEmpty), isTrue);
    });

    test('a paragraph too tall for one page is split, not lost', () {
      final pages = paginateBlocks([DocBlock.body('word ' * 4000)]);
      expect(pages.length, greaterThan(1));
      final total = pages.fold<int>(0, (n, p) => n + p.length);
      expect(total, greaterThan(1));
    });
  });
}
