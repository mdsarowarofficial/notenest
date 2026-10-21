import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notenest/data/app_database.dart';
import 'package:notenest/data/auth_repository.dart';
import 'package:notenest/data/note_repository.dart';
import 'package:notenest/models/note.dart';
import 'package:notenest/models/note_query.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// What a person who is trying to break the notebook (or just pastes something
/// strange) can put into it, run against the real database and repository.
void main() {
  late NoteRepository repo;
  late Directory dir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('notenest_hostile');
    await databaseFactory.setDatabasesPath(dir.path);
    await AppDatabase.instance.open();
    final err = await AuthRepository.instance.register(
      name: 'Tester',
      email: 'tester@example.com',
      password: 'Str0ng!Pass-word',
    );
    expect(err, isNull);
    repo = NoteRepository.instance;
    await repo.load();
  });

  test('SQL, wildcards, quotes and odd unicode are stored as plain text',
      () async {
    final titles = [
      "'; DROP TABLE notes; --",
      '" OR 1=1 --',
      r'50% off _ \ back\slash',
      '👩‍🎓 emoji 🎓',
      'עברית RTL ‏text',
      'zero​width‍chars',
      'tab\tand\nnewline',
      '   spaced   ',
    ];
    for (final t in titles) {
      final n = await repo.createNote(title: t, body: 'body of $t');
      expect(n.id, isNotNull);
    }
    // Every one is still there, the table survived, and each reads back.
    final all = repo.notes();
    expect(all.length, greaterThanOrEqualTo(titles.length));
    expect(all.any((n) => n.title == "'; DROP TABLE notes; --"), isTrue);
    expect(all.any((n) => n.title == '👩‍🎓 emoji 🎓'), isTrue);
  });

  test('searching for a wildcard only finds notes that contain it', () async {
    await repo.createNote(title: 'plain note alpha', body: 'nothing special');
    final percent =
        await repo.searchNotes(const NoteQuery(text: '%'), limit: 1000);
    expect(percent.every((n) => (n.title + n.body).contains('%')), isTrue);
    final underscore =
        await repo.searchNotes(const NoteQuery(text: '_'), limit: 1000);
    expect(
        underscore.every((n) => (n.title + n.body + n.tags.join()).contains('_')),
        isTrue);
    final quote =
        await repo.searchNotes(const NoteQuery(text: "'"), limit: 1000);
    expect(quote.every((n) => (n.title + n.body).contains("'")), isTrue);
    // No crash on backslashes or a lone escape character either.
    await repo.searchNotes(const NoteQuery(text: r'\'));
    await repo.searchNotes(const NoteQuery(text: r'\%\_'));
  });

  test('a huge paste is clipped, and the notebook still loads', () async {
    final huge = 'ক' * 1500000; // 4.5 MB of Bangla
    final n = await repo.createNote(title: 'T' * 5000, body: huge);
    expect(n.id, isNotNull);

    // The thing that used to be fatal: loading every note at launch.
    await repo.load();
    final back = repo.notes().firstWhere((x) => x.id == n.id);
    expect(back.body.length, Note.maxBody);
    expect(back.title.length, Note.maxTitle);
  });

  test('an emoji is not cut in half at the limit', () async {
    // The 2nd code unit of the last emoji would land on the limit.
    final body = '${'a' * (Note.maxBody - 1)}😀😀😀';
    final n = await repo.createNote(title: 'emoji edge', body: body);
    await repo.load();
    final back = repo.notes().firstWhere((x) => x.id == n.id);
    final last = back.body.codeUnitAt(back.body.length - 1);
    expect(last >= 0xD800 && last <= 0xDBFF, isFalse,
        reason: 'the body must not end on half a surrogate pair');
  });

  test('an empty title and an empty body are accepted', () async {
    final n = await repo.createNote(title: '', body: '');
    expect(n.id, isNotNull);
  });

  test('two thousand notes load and search quickly', () async {
    final uid = AuthRepository.instance.requireUserId;
    final now = DateTime.now();
    final batch = AppDatabase.instance.db.batch();
    for (var i = 0; i < 2000; i++) {
      batch.insert(
        'notes',
        Note(
          userId: uid,
          title: 'bulk note $i',
          body: 'line ${'word ' * 60} $i',
          tags: ['bulk', 'n${i % 20}'],
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );
    }
    await batch.commit(noResult: true);

    final sw = Stopwatch()..start();
    await repo.load();
    final loaded = sw.elapsedMilliseconds;
    sw
      ..reset()
      ..start();
    final hits =
        await repo.searchNotes(const NoteQuery(text: 'bulk 1999'), limit: 300);
    final searched = sw.elapsedMilliseconds;
    sw
      ..reset()
      ..start();
    await repo.createNote(title: 'one more', body: 'with 2000 already here');
    final created = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('load: ${loaded}ms, search: ${searched}ms, one create: ${created}ms');
    expect(hits.any((n) => n.title == 'bulk note 1999'), isTrue);
    expect(loaded, lessThan(3000));
    expect(searched, lessThan(2000));
    expect(created, lessThan(2000));
  });

  test('a task with no title is refused, an overlong one is kept whole',
      () async {
    expect(() => repo.addTask(title: '   '), throwsArgumentError);
    final t = await repo.addTask(title: 'x' * 20000);
    expect(t.id, isNotNull);
    await repo.load();
  });
}
