import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'data/auth_repository.dart';
import 'data/cloud_service.dart';
import 'data/note_repository.dart';
import 'screens/auth/login_page.dart';
import 'screens/setup/setup_flow.dart';
import 'screens/shell/home_shell.dart';
import 'theme/nest_theme.dart';
import 'widgets/nest_app_frame.dart';
import 'widgets/nest_opening.dart';

Future<void> main() async {
  // The database must be open and the session restored before the first frame,
  // because the first screen depends on both.
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.open();
  await AuthRepository.instance.restoreSession();
  await NoteRepository.instance.load();

  // Started here so the drawer knows from the first frame whether the cloud is
  // available. It never throws and it is never required: if Firebase cannot
  // start, this returns having recorded why and the app carries on exactly as
  // it did before there was a cloud at all.
  await CloudService.instance.start();

  runApp(const NoteNestApp());
}

class NoteNestApp extends StatelessWidget {
  const NoteNestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoteNest',
      debugShowCheckedModeBanner: false,
      theme: nestTheme(),
      // Wraps the Navigator, so every route, dialog and sheet is held to a
      // phone's width on a desktop browser rather than only the first screen.
      builder: (context, child) =>
          NestAppFrame(child: child ?? const SizedBox.shrink()),
      // The opening plays over the first screen, which is built underneath it
      // from the very first frame. By the time the fold lifts, the app is
      // already laid out — the animation costs no waiting.
      home: NestOpening(child: _firstScreen()),
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
