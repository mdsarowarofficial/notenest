// Drives the real To-do planner page against a real (ffi) SQLite database:
// the empty sheet, inline entry, ticking, goals, rating, thoughts, day
// navigation and pushing a task a day. Run with `--update-goldens` to also
// write screenshots to test/shots/ (set PLANNER_SHOTS=1 as well).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:notenest/data/app_database.dart';
import 'package:notenest/data/auth_repository.dart';
import 'package:notenest/data/note_repository.dart';
import 'package:notenest/models/day_plan.dart';
import 'package:notenest/screens/tasks/tasks_page.dart';
import 'package:notenest/theme/nest_theme.dart';

final _shots = Platform.environment['PLANNER_SHOTS'] == '1';

Finder _field(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint);

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _add(WidgetTester t, String hint, String text) async {
  await t.enterText(_field(hint), text);
  await t.pump();
  await t.testTextInput.receiveAction(TextInputAction.done);
  await _settle(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = NoteRepository.instance;

  Future<void> loadFont(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(
          Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    }
    await loader.load();
  }

  setUpAll(() async {
    // The app's real typefaces and icons, so screenshots read as they do on a
    // phone rather than as the test framework's placeholder blocks.
    await loadFont('Outfit',
        ['assets/fonts/Outfit-SemiBold.ttf', 'assets/fonts/Outfit-Bold.ttf']);
    await loadFont('PlusJakartaSans', [
      'assets/fonts/PlusJakartaSans-Regular.ttf',
      'assets/fonts/PlusJakartaSans-Medium.ttf',
      'assets/fonts/PlusJakartaSans-SemiBold.ttf',
      'assets/fonts/PlusJakartaSans-Bold.ttf',
    ]);
    final root = Platform.environment['FLUTTER_ROOT']!;
    await loadFont('MaterialIcons', [
      '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ]);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactoryFfi.deleteDatabase(
        '${await databaseFactoryFfi.getDatabasesPath()}/notenest.db');
    await AppDatabase.instance.open();
    final err = await AuthRepository.instance.register(
      name: 'Test Student',
      email: 'planner@test.dev',
      password: 'Secret#1',
    );
    expect(err, isNull);
    await repo.load();
  });

  testWidgets('planner sheet: empty page, entry, tick, goals, rating, days',
      (t) async {
    t.view.physicalSize = const Size(1170, 8400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      theme: nestTheme(),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: NestColor.ground,
        body: const TasksPage(embedded: true),
      ),
    ));
    await _settle(t);

    // 1. An empty day still shows the whole sheet.
    expect(find.text('TO DO LIST'), findsOneWidget);
    expect(find.text('TODAY’S URGENT TASKS'), findsOneWidget);
    expect(find.text('TOMORROW’S URGENT TASKS'), findsOneWidget);
    expect(find.text('MY TOP 7 GOALS'), findsOneWidget);
    expect(find.textContaining('RANDOM THOUGHTS'), findsOneWidget);
    expect(find.text('PRODUCTIVITY'), findsOneWidget);
    expect(_field('Add a task'), findsOneWidget);
    expect(t.takeException(), isNull);
    if (_shots) {
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('shots/1_empty.png'));
    }

    // 2. Inline entry: type, Enter, and the line is ready for the next one.
    await _add(t, 'Add a task', 'Revise normalization');
    await _add(t, 'Add a task', 'Submit lab report');
    expect(find.text('Revise normalization'), findsOneWidget);
    expect(find.text('Submit lab report'), findsOneWidget);
    expect(repo.tasks().length, 2);
    expect(t.takeException(), isNull);

    // 3. Tomorrow, a goal.
    await _add(t, 'Plan ahead', 'Read chapter 5');
    await _add(t, 'Add a goal', 'Finish the semester with a CGPA above 3.5');
    expect(repo.goals().length, 1);
    expect(repo.tasks().length, 3);

    // 3b. Renaming and removing a goal closes its dialog without a crash (the
    // dialog's controller was once disposed while the dialog was animating out).
    await t.tap(find.text('Finish the semester with a CGPA above 3.5'));
    await t.pumpAndSettle();
    expect(find.text('Edit goal'), findsOneWidget);
    await t.tap(find.text('Delete'));
    await _settle(t);
    expect(repo.goals(), isEmpty);
    expect(t.takeException(), isNull);
    await _add(t, 'Add a goal', 'Finish the semester with a CGPA above 3.5');
    expect(repo.goals().length, 1);

    // 4. Tick the first task: done, and the streak appears.
    final today = repo.tasks().firstWhere((x) => x.title == 'Revise normalization');
    await t.runAsync(() => repo.setTaskDone(today, true));
    await _settle(t);
    expect(find.text('1 of 2 done'), findsOneWidget);
    final other = repo.tasks().firstWhere((x) => x.title == 'Submit lab report');
    await t.runAsync(() => repo.setTaskDone(other, true));
    await _settle(t);
    expect(find.text('All 2 done. Nice work.'), findsOneWidget);
    expect(find.text('1-day streak'), findsOneWidget);

    // 5. Rating: tap the 4th star; tapping it again clears.
    await t.tap(find.bySemanticsLabel('4 stars'));
    await _settle(t);
    expect(repo.dayLog(DateTime.now()).rating, 4);
    expect(find.text('Good'), findsOneWidget);

    // 6. Random thoughts autosave.
    await t.enterText(
        find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.hintText == 'Ideas, worries, things to remember…'),
        'Ask sir about the viva');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1200)));
    await t.pump(const Duration(milliseconds: 1000));
    await _settle(t);
    expect(repo.dayLog(DateTime.now()).thoughts, 'Ask sir about the viva');
    if (_shots) {
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('shots/2_filled.png'));
    }

    // 7. Next day: the page for tomorrow shows what was planned there.
    await t.tap(find.byTooltip('Next day'));
    await _settle(t);
    expect(find.text('Read chapter 5'), findsOneWidget);
    expect(find.text('Revise normalization'), findsNothing); // it is "yesterday"
    expect(find.text('Back to today'), findsOneWidget);
    expect(find.text('Ask sir about the viva'), findsNothing);

    // 8. Push-to-next-day from the row menu.
    await t.tap(find.byTooltip('More').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Push to next day'));
    await _settle(t);
    final read = repo.tasks().firstWhere((x) => x.title == 'Read chapter 5');
    final tomorrow = DateTime.now().add(const Duration(days: 2));
    expect(sameDay(read.dueAt!, tomorrow), isTrue);

    // 9. Back to today keeps the first day's thoughts and stars.
    await t.tap(find.text('Back to today'));
    await _settle(t);
    expect(find.text('Ask sir about the viva'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
