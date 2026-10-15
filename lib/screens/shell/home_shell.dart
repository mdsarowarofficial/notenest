import 'package:flutter/material.dart';

import '../../data/account_sync.dart';
import '../../data/classroom_service.dart';
import '../../data/cloud_service.dart';
import '../../data/note_repository.dart';
import '../../data/profile_photo.dart';
import '../../models/study_group.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_drawer.dart';
import '../../widgets/nest_nav_bar.dart';
import '../../widgets/nest_tour.dart';
import '../classroom/classes_page.dart';
import '../classroom/post_composer.dart';
import '../capture/capture_sheet.dart';
import '../capture/dictation_page.dart';
import '../capture/record_page.dart';
import '../cloud/cloud_page.dart';
import '../convert/convert_page.dart';
import '../cover/cover_page.dart';
import '../exam/exam_page.dart';
import '../home/today_page.dart';
import '../notes/notes_page.dart';
import '../people/people_page.dart';
import '../semester/semester_page.dart';
import '../settings/settings_page.dart';
import '../notes/transcript_editor.dart';
import '../search/search_page.dart';
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

  /// Handles the first-run tour points at.
  final _tabKeys = List.generate(4, (_) => GlobalKey());
  final _captureKey = GlobalKey();
  final _menuKey = GlobalKey();
  final _searchKey = GlobalKey();
  final _avatarKey = GlobalKey();
  bool _touring = false;

  @override
  void initState() {
    super.initState();
    // After the first frame, so nothing here delays the notebook appearing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      syncAccountOnOpen();
    });
  }

  bool get _teacher => _repo.isTeacher;

  /// A teacher's four: no Exam countdown (that is a student's question), and
  /// Classes gets a tab of its own because it is most of what they do here.
  static const _teacherItems = <NestNavItem>[
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
      icon: Icons.co_present_outlined,
      activeIcon: Icons.co_present_rounded,
      label: 'Classes',
      accent: Color(0xFF7ED9A6),
    ),
    NestNavItem(
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      label: 'People',
      accent: Color(0xFFFF9BB3),
    ),
  ];

  /// Starts the tour once per account, the first time the notebook opens —
  /// and again whenever Settings asks for it by clearing the flag.
  void _maybeStartTour() {
    if (_touring || _repo.tourDone) return;
    _touring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _tab = 0);
      // After the opening animation (1.75 s), which the tour would otherwise
      // cover, and with Today laid out so there is something to point at.
      await Future<void>.delayed(const Duration(milliseconds: 1900));
      if (!mounted) return;
      await showNestTour(context, _tourSteps());
      await _repo.saveTourDone(true);
      _touring = false;
    });
  }

  List<TourStep> _tourSteps() {
    final name = _repo.userName.trim().split(RegExp(r'\s+')).first;
    final hello = name.isEmpty ? 'Welcome to NoteNest' : 'Welcome, $name';
    if (_teacher) {
      return [
        TourStep(
          title: hello,
          icon: Icons.waving_hand_rounded,
          body: 'A quick look round — about a minute. Tap Next, or anywhere '
              'on the dark part of the screen.',
        ),
        TourStep(
          target: _tabKeys[2],
          title: 'Classes',
          icon: Icons.co_present_rounded,
          body: 'Make a class here and give your students its six-letter '
              'code. Inside a class: Stream for announcements, Classwork for '
              'materials and assignments, People for who has joined.',
        ),
        TourStep(
          target: _captureKey,
          title: 'Post or write',
          icon: Icons.edit_rounded,
          body: 'Post slides, a PDF or an assignment with a deadline to a '
              'class — or write a note of your own. Files are saved in your '
              'Google Drive and shared with the class by link.',
        ),
        TourStep(
          target: _tabKeys[1],
          title: 'Notes',
          icon: Icons.auto_stories_rounded,
          body: 'Your own notes, lecture plans and PDFs, filed by course.',
        ),
        TourStep(
          target: _tabKeys[3],
          title: 'People',
          icon: Icons.people_rounded,
          body: 'Chats, study groups, and notes shared with you. Each class '
              'also has its own chat — the speech-bubble at the top of the '
              'class.',
        ),
        TourStep(
          target: _avatarKey,
          title: 'Your profile',
          icon: Icons.account_circle_rounded,
          body: 'Tap your picture to add a profile photo. Your students see '
              'it in the class.',
        ),
        TourStep(
          target: _menuKey,
          title: 'Menu and Settings',
          icon: Icons.menu_rounded,
          body: 'Settings, Google Drive backup, switching account and signing '
              'out are in here. You can replay this tour from Settings.',
        ),
      ];
    }
    return [
      TourStep(
        title: hello,
        icon: Icons.waving_hand_rounded,
        body: 'A quick look round — about a minute. Tap Next, or anywhere on '
            'the dark part of the screen.',
      ),
      TourStep(
        target: _tabKeys[0],
        title: 'Today',
        icon: Icons.home_rounded,
        body: 'What to revise next, your next exam, and the notes you were '
            'last working on.',
      ),
      TourStep(
        target: _captureKey,
        title: 'New note',
        icon: Icons.edit_rounded,
        body: 'Type a note, photograph a page, attach a PDF, record a lecture '
            'or dictate. Every note belongs to a subject.',
      ),
      TourStep(
        target: _tabKeys[1],
        title: 'Notes',
        icon: Icons.auto_stories_rounded,
        body: 'Everything you have written, by subject. Mark notes as read, '
            'review or mastered to track your revision.',
      ),
      TourStep(
        target: _tabKeys[2],
        title: 'People and Classes',
        icon: Icons.people_rounded,
        body: 'Join your teacher\'s class with its code, then get slides and '
            'assignments and hand your work in — all under Classes. Chats, '
            'study groups and shared notes are here too.',
      ),
      TourStep(
        target: _tabKeys[3],
        title: 'Exam',
        icon: Icons.timer_rounded,
        body: 'Countdowns to exams, quizzes and deadlines. An assignment from '
            'a class can be added here with one tap.',
      ),
      TourStep(
        target: _searchKey,
        title: 'Search',
        icon: Icons.search_rounded,
        body: 'Find any note by its title, text, topic or tag.',
      ),
      TourStep(
        target: _avatarKey,
        title: 'Your profile',
        icon: Icons.account_circle_rounded,
        body: 'Tap your picture to set a profile photo.',
      ),
      TourStep(
        target: _menuKey,
        title: 'Menu and Settings',
        icon: Icons.menu_rounded,
        body: 'Subjects, semesters, cover pages, Google Drive backup, '
            'switching account and signing out. You can replay this tour '
            'from Settings.',
      ),
    ];
  }

  /// The teacher's middle button: post to a class, or write a note.
  Future<void> _openTeacherCapture() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            const Text('CREATE', style: nestEyebrow),
            const SizedBox(height: 6),
            ListTile(
              leading:
                  const Icon(Icons.assignment_outlined, color: NestColor.pen),
              title: const Text('Post to a class'),
              subtitle: const Text('Announcement, material or assignment'),
              onTap: () => Navigator.pop(sheetContext, 'post'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.edit_note_rounded, color: NestColor.pen),
              title: const Text('Write a note'),
              subtitle: const Text('Lecture notes and plans for yourself'),
              onTap: () => Navigator.pop(sheetContext, 'note'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'note') {
      await _openCapture();
      return;
    }
    final cloud = CloudService.instance;
    if (!cloud.isSignedIn) {
      setState(() => _tab = 2);
      _toast('Connect a cloud account to post to a class');
      return;
    }
    List<StudyGroup> mine;
    try {
      mine = (await ClassroomService.instance.watchClasses().first)
          .where((c) => c.isOwner(cloud.uid))
          .toList();
    } catch (_) {
      mine = const [];
    }
    if (!mounted) return;
    if (mine.isEmpty) {
      setState(() => _tab = 2);
      _toast('Make a class first, then post to it');
      return;
    }
    final target = mine.length == 1
        ? mine.first
        : await showModalBottomSheet<StudyGroup>(
            context: context,
            builder: (sheetContext) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 14),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
                    child: Text('POST TO WHICH CLASS?', style: nestEyebrow),
                  ),
                  for (final c in mine)
                    ListTile(
                      leading: const Icon(Icons.co_present_rounded),
                      title: Text(c.name),
                      subtitle: c.subject.isEmpty ? null : Text(c.subject),
                      onTap: () => Navigator.pop(sheetContext, c),
                    ),
                ],
              ),
            ),
          );
    if (target == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostComposerPage(classGroup: target)),
    );
  }

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
      label: 'People',
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
      _toast(_teacher
          ? 'Add a course from the menu first, so the note has somewhere to '
              'live'
          : 'Add a subject first so the note has somewhere to live');
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

    if (kind == CaptureKind.record) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecordPage(initialSubjectId: subject?.id),
        ),
      );
      return;
    }

    if (kind == CaptureKind.dictate) {
      final transcript = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const DictationPage()),
      );
      if (transcript == null || transcript.trim().isEmpty || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TranscriptEditorPage(
            transcript: transcript,
            initialSubjectId: subject?.id,
          ),
        ),
      );
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
      // The drawer shows whether the cloud is connected, and that can change
      // from the cloud screen, so this watches both.
      listenable: Listenable.merge([_repo, CloudService.instance]),
      builder: (context, _) {
        _maybeStartTour();
        return _scaffold(context);
      },
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      extendBody: true,
      drawer: NestDrawer(
        userName: _repo.userName,
        userPhoto: myPhoto(),
        semester: _teacher
            ? (_repo.teachingCourse ?? _repo.university ?? 'Teacher')
            : _repo.semesterLabel ?? 'No semester set',
        subjects: _repo.subjects(),
        links: _repo.drawerLinks(),
        selectedId: _drawerSelection,
        synced: CloudService.instance.isSignedIn,
        onSelectSubject: (s) {
          setState(() {
            _drawerSelection = s.code;
            _tab = 1;
          });
          Navigator.pop(context);
        },
        onSelectLink: (l) {
          Navigator.pop(context);
          switch (l.id) {
            case 'cloud':
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CloudPage()),
              );
            case 'cover':
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CoverPageScreen()),
              );
            case 'convert':
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConvertPage()),
              );
            case 'settings':
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            case 'semesters':
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SemesterPage()),
              );
            case 'trash':
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TrashPage()),
              );
            default:
              _toast('${l.label} is not built yet');
          }
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
        // Written out rather than left to the AppBar, only so the tour has
        // something to point at.
        leading: Builder(
          builder: (barContext) => IconButton(
            key: _menuKey,
            tooltip: 'Menu',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(barContext).openDrawer(),
          ),
        ),
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
            key: _searchKey,
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
            avatarKey: _avatarKey,
            onOpenNotes: () => setState(() => _tab = 1),
            onCapture: _teacher ? _openTeacherCapture : _openCapture,
            onOpenExams: () => setState(() => _tab = 3),
            onOpenClasses: () => setState(() => _tab = 2),
          ),
          NotesPage(
            subjectCode: _drawerSelection,
            onCapture: _openCapture,
            // The subject chips on the page and the subject list in the
            // drawer set the same one value, so the two can never disagree
            // about which subject you are looking at.
            onPickSubject: (code) => setState(() => _drawerSelection = code),
          ),
          if (_teacher) ...const [
            ClassesPage(),
            PeoplePage(),
          ] else ...const [
            PeoplePage(showClasses: true),
            ExamPage(),
          ],
        ],
      ),
      bottomNavigationBar: NestNavBar(
        items: _teacher ? _teacherItems : _items,
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        onCapture: _teacher ? _openTeacherCapture : _openCapture,
        itemKeys: _tabKeys,
        captureKey: _captureKey,
      ),
    );
  }
}
