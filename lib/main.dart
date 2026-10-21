import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'data/auth_repository.dart';
import 'data/cloud_service.dart';
import 'data/note_repository.dart';
import 'data/reminder_service.dart';
import 'screens/auth/login_page.dart';
import 'screens/setup/setup_flow.dart';
import 'screens/shell/home_shell.dart';
import 'theme/nest_theme.dart';
import 'l10n/strings.dart';
import 'theme/theme_controller.dart';
import 'widgets/nest_app_frame.dart';
import 'widgets/nest_opening.dart';
import 'data/app_lock.dart';
import 'screens/lock/lock_screen.dart';
import 'data/push_service.dart';
import 'screens/startup_failed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A mistake in one screen must not take the others with it, and an error
  // that escapes a future is logged rather than left unseen.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true;
  };
  ErrorWidget.builder = (details) => const _BrokenSpot();

  try {
    await _start();
  } catch (e, s) {
    // Without this a failure here (a database that will not open, say) leaves
    // a blank screen on every launch and no way out except clearing the app's
    // data, which deletes the notes.
    debugPrint('NoteNest could not start: $e\n$s');
    runApp(StartupFailedApp(error: e, retry: main));
    return;
  }
  runApp(const NoteNestApp());
}

Future<void> _start() async {
  // The database must be open and the session restored before the first frame,
  // because the first screen depends on both.
  await AppDatabase.instance.open();
  // Before anything draws, so the first frame is already in the right colours.
  await ThemeController.instance.load();
  await AppLanguage.instance.load();
  await AppLock.instance.load();
  await AuthRepository.instance.restoreSession();
  await NoteRepository.instance.load();

  // Started here so the drawer knows from the first frame whether the cloud is
  // available. It never throws and it is never required: if Firebase cannot
  // start, this returns having recorded why and the app carries on exactly as
  // it did before there was a cloud at all.
  await CloudService.instance.start();

  // Push notifications follow the cloud sign-in. Best effort; never blocks.
  PushService.instance.watch(CloudService.instance);

  // Local reminders. Rebuilt from the plan whenever tasks or exams change; a
  // no-op on the web and for anyone who has not switched them on.
  ReminderService.instance.attach(NoteRepository.instance);
  unawaited(ReminderService.instance.sync());
}

/// What a widget that failed to build shows in release mode, in place of
/// Flutter's grey box: the rest of the screen keeps working around it.
class _BrokenSpot extends StatelessWidget {
  const _BrokenSpot();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Icon(Icons.error_outline_rounded, color: Colors.black38),
        ),
      );
}

class NoteNestApp extends StatelessWidget {
  const NoteNestApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilt when the person switches light/dark; the controller has already
    // pointed NestColor at the new palette by then.
    return ListenableBuilder(
      listenable: Listenable.merge([ThemeController.instance, AppLanguage.instance]),
      builder: (context, _) => MaterialApp(
        title: 'NoteNest',
        debugShowCheckedModeBanner: false,
        theme: nestTheme(),
        // Every colour is read from NestColor, so the swap is instant; an
        // animated cross-fade would only fade the half that reads the Theme.
        themeAnimationDuration: Duration.zero,
        // Wraps the Navigator, so every route, dialog and sheet is held to a
        // phone's width on a desktop browser rather than only the first screen.
        navigatorKey: nestNavigatorKey,
        builder: (context, child) => NestAppFrame(
          child: LockGate(child: child ?? const SizedBox.shrink()),
        ),
        // The opening plays over the first screen, which is built underneath
        // it from the very first frame. By the time the fold lifts, the app is
        // already laid out — the animation costs no waiting.
        home: NestOpening(child: _firstScreen()),
      ),
    );
  }

  /// Signed out goes to login; signed in but not set up goes to setup;
  /// otherwise straight into the notebook.
  Widget _firstScreen() {
    if (!AuthRepository.instance.isSignedIn) return const LoginPage();
    if (!NoteRepository.instance.setupDone) return const SetupFlow();
    return const HomeShell();
  }
}
