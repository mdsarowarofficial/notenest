import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_drawer.dart';
import '../../widgets/nest_nav_bar.dart';
import '../capture/capture_sheet.dart';
import '../exam/exam_page.dart';
import '../home/today_page.dart';
import '../notes/notes_page.dart';
import '../search/search_page.dart';
import '../shared/shared_page.dart';
import '../capture/media_capture.dart';
import '../notes/note_editor.dart';
import '../profile/profile_page.dart';
import '../subjects/subject_form.dart';
import '../trash/trash_page.dart';

/// Holds the drawer, the navigation bar and the four destinations.
///
/// It listens to the repository, so anything written to the database anywhere
/// in the app redraws the drawer and the pages without being told.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _repo = NoteRepository.instance;

  int _tab = 0;
  String _drawerSelection = '';

  static const _items = <NestNavItem>[
    NestNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Today',
      accent: Color(0xFFFFE45E),
    ),
    NestNavItem(
      icon: Icons.auto_stories_outlined,
      activeIcon: Icons.auto_stories_rounded,
      label: 'Notes',
      accent: Color(0xFF7EC4F2),
    ),
    NestNavItem(
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      label: 'Shared',
      accent: Color(0xFFFF9BB3),
    ),
    NestNavItem(
      icon: Icons.timer_outlined,
      activeIcon: Icons.timer_rounded,
      label: 'Exam',
      accent: Color(0xFF7ED9A6),
    ),
  ];

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 104),
      ),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SearchPage()),
    );
  }

  Future<void> _openCapture() async {
    if (!_repo.hasSubjects) {
      _toast('Add a subject first so the note has somewhere to live');
      return;
    }
    final kind = await showCaptureSheet(context);
    if (kind == null || !mounted) return;

    final subject = _repo.subjectByCode(_drawerSelection);

    if (kind == CaptureKind.text) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NoteEditorPage(initialSubjectId: subject?.id),
        ),
      );
      return;
    }

    if (kind == CaptureKind.voice) {
      _toast('Lecture recording is coming in the next step');
      return;
    }

    // Photo and PDF both need a note to attach to, so one is created first and
    // the editor opens on it with the file already in place.
    final note = await _repo.createNote(
      title: kind == CaptureKind.photo ? 'Handwritten note' : 'PDF note',
      subjectId: subject?.id,
    );
    if (!mounted) return;

    var added = false;
    if (kind == CaptureKind.photo) {
      final source = await askImageSource(context);
      if (source == null) {
        await _repo.deleteNoteForever(note);
        return;
      }
      if (!mounted) return;
      added = await MediaCapture.captureHandwriting(
        context,
        note: note,
        source: source,
      );
    } else {
      added = await MediaCapture.attachPdf(context, note: note);
    }

    if (!mounted) return;

    // Nothing was picked, so the placeholder note should not survive.
    if (!added) {
      await _repo.deleteNoteForever(note);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorPage(existing: _repo.noteById(note.id!)),
      ),
    );
  }

  Future<void> _addSubject() async {
    Navigator.pop(context); // close the drawer first
    final added = await showSubjectForm(context);
    if (added && mounted) _toast('Subject added');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) => Scaffold(
        extendBody: true,
        drawer: NestDrawer(
          userName: _repo.userName,
          semester: _repo.semesterLabel ?? 'No semester set',
          subjects: _repo.subjects(),
          links: _repo.drawerLinks(),
          selectedId: _drawerSelection,
          synced: _repo.isSynced,
          onSelectSubject: (s) {
            setState(() {
              _drawerSelection = s.code;
              _tab = 1;
            });
            Navigator.pop(context);
          },
          onSelectLink: (l) {
            Navigator.pop(context);
            if (l.id == 'trash') {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TrashPage()),
              );
              return;
            }
            setState(() => _drawerSelection = l.id);
            _toast('${l.label} is not built yet');
          },
          onAddSubject: _addSubject,
          onOpenProfile: () {
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            );
          },
          onEditSemester: () {
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            );
          },
        ),
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text(
            'NoteNest',
            style: TextStyle(
              fontFamily: NestFont.display,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: NestColor.ink,
            ),
          ),
          actions: [
            IconButton(
              onPressed: _openSearch,
              icon: const Icon(Icons.search_rounded),
              tooltip: 'Search notes',
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            TodayPage(
              onOpenNotes: () => setState(() => _tab = 1),
              onCapture: _openCapture,
              onSearch: _openSearch,
            ),
            NotesPage(subjectCode: _drawerSelection, onCapture: _openCapture),
            const SharedPage(),
            const ExamPage(),
          ],
        ),
        bottomNavigationBar: NestNavBar(
          items: _items,
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
          onCapture: _openCapture,
        ),
      ),
    );
  }
}
