import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import '../notifications/notifications_page.dart' show NoticeBell;
import '../people/people_page.dart';
import '../semester/semester_page.dart';
import '../settings/settings_page.dart';
import '../notes/transcript_editor.dart';
import '../search/search_page.dart';
import '../capture/media_capture.dart';
import '../notes/note_editor.dart';
import '../profile/profile_page.dart';
import '../subjects/subject_form.dart';
import '../tasks/tasks_page.dart';
import '../trash/trash_page.dart';
import '../../l10n/strings.dart';
import '../study/study_timer_page.dart';

/// Holds the drawer, the navigation bar and the four destinations.
///
/// It listens to the repository, so anything written to the database anywhere
/// in the app redraws the drawer and the pages without being told.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Asks the shell to show a tab (-1 when nothing is asked), so a page pushed
  /// on top of it can send the person back to a tab, bar and all.
  static final _tabRequest = ValueNotifier<int>(-1);

  /// Switches to the To-do tab once the shell is back on top.
  static void openTodo() => _tabRequest.value = _HomeShellState._todoTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _repo = NoteRepository.instance;

  int _tab = 0;
  String _drawerSelection = '';
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _drawerOpen = false;

  /// Handles the first-run tour points at.
  final _tabKeys = List.generate(4, (_) => GlobalKey());
  final _captureKey = GlobalKey();
  final _todoKey = GlobalKey();
  final _menuKey = GlobalKey();
  final _searchKey = GlobalKey();
  final _avatarKey = GlobalKey();

  /// App-wide, not per screen: a tour already on screen must not be joined by
  /// a second one from another copy of this page.
  static bool _touring = false;

  void _onTabRequest() {
    final i = HomeShell._tabRequest.value;
    if (i < 0) return;
    HomeShell._tabRequest.value = -1;
    if (mounted) setState(() => _tab = i);
  }

  /// True while a page is being scrolled. The To-do pill floats over the
  /// lists, so it slides away rather than hide the end of a row, and comes back
  /// a moment after the scrolling stops.
  final _scrolling = ValueNotifier<bool>(false);
  Timer? _scrollIdle;

  bool _onScroll(ScrollNotification n) {
    // Only the page's own vertical lists, not the chip rows or the week strip.
    if (n.metrics.axis != Axis.vertical || n.depth != 0) return false;
    if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
      _scrollIdle?.cancel();
      _scrolling.value = true;
    } else if (n is ScrollEndNotification) {
      _scrollIdle?.cancel();
      _scrollIdle = Timer(const Duration(milliseconds: 450), () {
        _scrolling.value = false;
      });
    }
    return false;
  }

  @override
  void dispose() {
    HomeShell._tabRequest.removeListener(_onTabRequest);
    _scrollIdle?.cancel();
    _scrolling.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    HomeShell._tabRequest.addListener(_onTabRequest);
    // After the first frame, so nothing here delays the notebook appearing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      syncAccountOnOpen();
    });
  }

  bool get _teacher => _repo.isTeacher;

  /// Tab positions. The bar holds four of them; To-do is a fifth page with no
  /// place on the bar, opened from the floating To-do button, so the bar never
  /// disappears behind it.
  /// A student's People (with Classes) or a teacher's Classes.
  static const _peopleTab = 2;
  static const _examTab = 3;
  static const _todoTab = 4;

  /// On these tabs the page brings its own floating button (new chat, new
  /// group), so the To-do button steps aside rather than sit on top of it.
  bool get _tabHasOwnButton => _teacher ? _tab == 3 : _tab == 2;

  /// A teacher's four: no Exam countdown (that is a student's question), and
  /// Classes gets a tab of its own because it is most of what they do here.
  static List<NestNavItem> get _teacherItems => <NestNavItem>[
    NestNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: tr('Today'),
      accent: const Color(0xFFFFE45E),
    ),
    NestNavItem(
      icon: Icons.auto_stories_outlined,
      activeIcon: Icons.auto_stories_rounded,
      label: tr('Notes'),
      accent: const Color(0xFF7EC4F2),
    ),
    NestNavItem(
      icon: Icons.co_present_outlined,
      activeIcon: Icons.co_present_rounded,
      label: tr('Classes'),
      accent: const Color(0xFF7ED9A6),
    ),
    NestNavItem(
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      label: tr('People'),
      accent: const Color(0xFFFF9BB3),
    ),
  ];

  /// Starts the tour once per account, the first time the notebook opens —
  /// and again whenever Settings asks for it by clearing the flag.
  void _maybeStartTour() {
    if (_touring || _repo.tourDone) return;
    _touring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _touring = false;
        return;
      }
      setState(() => _tab = 0);
      // After the opening animation (1.75 s), which the tour would otherwise
      // cover, and with Today laid out so there is something to point at.
      await Future<void>.delayed(const Duration(milliseconds: 1900));
      if (!mounted) {
        _touring = false;
        return;
      }
      await showNestTour(context, _tourSteps());
      await _repo.saveTourDone(true);
      _touring = false;
    });
  }

  List<TourStep> _tourSteps() {
    final name = _repo.userName.trim().split(RegExp(r'\s+')).first;
    final hello = name.isEmpty ? tr('Welcome to NoteNest') : trp('Welcome, {0}', [name]);
    if (_teacher) {
      return [
        TourStep(
          title: hello,
          icon: Icons.waving_hand_rounded,
          body: tr('A quick look round — about a minute. Tap Next, or anywhere '
              'on the dark part of the screen.'),
        ),
        TourStep(
          target: _tabKeys[2],
          title: tr('Classes'),
          icon: Icons.co_present_rounded,
          body: tr('Make a class here and give your students its six-letter '
              'code. Inside a class: Stream for announcements, Classwork for '
              'materials and assignments, People for who has joined.'),
        ),
        TourStep(
          target: _captureKey,
          title: tr('Post or write'),
          icon: Icons.edit_rounded,
          body: tr('Post slides, a PDF or an assignment with a deadline to a '
              'class — or write a note of your own. Files are saved in your '
              'Google Drive and shared with the class by link.'),
        ),
        TourStep(
          target: _tabKeys[1],
          title: tr('Notes'),
          icon: Icons.auto_stories_rounded,
          body: tr('Your own notes, lecture plans and PDFs, filed by course.'),
        ),
        TourStep(
          target: _todoKey,
          title: tr('To-do'),
          icon: Icons.checklist_rtl_rounded,
          body: tr('Your planner: a page for every day with goals, today\'s and '
              'tomorrow\'s tasks, loose thoughts and a star rating. This '
              'button is on most screens.'),
        ),
        TourStep(
          target: _tabKeys[3],
          title: tr('People'),
          icon: Icons.people_rounded,
          body: tr('Chats, study groups, and notes shared with you. Each class '
              'also has its own chat — the speech-bubble at the top of the '
              'class.'),
        ),
        TourStep(
          target: _avatarKey,
          title: tr('Your profile'),
          icon: Icons.account_circle_rounded,
          body: tr('Tap your picture to add a profile photo. Your students see '
              'it in the class.'),
        ),
        TourStep(
          target: _menuKey,
          title: tr('Menu and Settings'),
          icon: Icons.menu_rounded,
          body: tr('Settings, Google Drive backup, switching account and signing '
              'out are in here. You can replay this tour from Settings.'),
        ),
      ];
    }
    return [
      TourStep(
        title: hello,
        icon: Icons.waving_hand_rounded,
        body: tr('A quick look round — about a minute. Tap Next, or anywhere on '
            'the dark part of the screen.'),
      ),
      TourStep(
        target: _tabKeys[0],
        title: tr('Today'),
        icon: Icons.home_rounded,
        body: tr('What to revise next, your next exam, and the notes you were '
            'last working on.'),
      ),
      TourStep(
        target: _captureKey,
        title: tr('New note'),
        icon: Icons.edit_rounded,
        body: tr('Type a note, photograph a page, attach a PDF, record a lecture '
            'or dictate. Every note belongs to a subject.'),
      ),
      TourStep(
        target: _tabKeys[1],
        title: tr('Notes'),
        icon: Icons.auto_stories_rounded,
        body: tr('Everything you have written, by subject. Mark notes as read, '
            'review or mastered to track your revision.'),
      ),
      TourStep(
        target: _todoKey,
        title: tr('To-do'),
        icon: Icons.checklist_rtl_rounded,
        body: tr('Your planner: a page for every day with goals, today\'s and '
            'tomorrow\'s tasks, loose thoughts and a star rating. This '
            'button is on most screens.'),
      ),
      TourStep(
        target: _tabKeys[2],
        title: tr('People and Classes'),
        icon: Icons.people_rounded,
        body: tr('Join your teacher\'s class with its code, then get slides and '
            'assignments and hand your work in — all under Classes. Chats, '
            'study groups and shared notes are here too.'),
      ),
      TourStep(
        target: _tabKeys[3],
        title: tr('Exam'),
        icon: Icons.timer_rounded,
        body: tr('Countdowns to exams, quizzes and deadlines. An assignment from '
            'a class can be added here with one tap.'),
      ),
      TourStep(
        target: _searchKey,
        title: tr('Search'),
        icon: Icons.search_rounded,
        body: tr('Find any note by its title, text, topic or tag.'),
      ),
      TourStep(
        target: _avatarKey,
        title: tr('Your profile'),
        icon: Icons.account_circle_rounded,
        body: tr('Tap your picture to set a profile photo.'),
      ),
      TourStep(
        target: _menuKey,
        title: tr('Menu and Settings'),
        icon: Icons.menu_rounded,
        body: tr('Subjects, semesters, cover pages, Google Drive backup, '
            'switching account and signing out. You can replay this tour '
            'from Settings.'),
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
            Text(tr('CREATE'), style: nestEyebrow),
            const SizedBox(height: 6),
            ListTile(
              leading:
                  Icon(Icons.assignment_outlined, color: NestColor.pen),
              title: Text(tr('Post to a class')),
              subtitle: Text(tr('Announcement, material or assignment')),
              onTap: () => Navigator.pop(sheetContext, 'post'),
            ),
            ListTile(
              leading:
                  Icon(Icons.edit_note_rounded, color: NestColor.pen),
              title: Text(tr('Write a note')),
              subtitle: Text(tr('Lecture notes and plans for yourself')),
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
      setState(() => _tab = _peopleTab);
      _toast(tr('Connect a cloud account to post to a class'));
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
      setState(() => _tab = _peopleTab);
      _toast(tr('Make a class first, then post to it'));
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                    child: Text(tr('POST TO WHICH CLASS?'), style: nestEyebrow),
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

  static List<NestNavItem> get _items => <NestNavItem>[
    NestNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: tr('Today'),
      accent: const Color(0xFFFFE45E),
    ),
    NestNavItem(
      icon: Icons.auto_stories_outlined,
      activeIcon: Icons.auto_stories_rounded,
      label: tr('Notes'),
      accent: const Color(0xFF7EC4F2),
    ),
    NestNavItem(
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      label: tr('People'),
      accent: const Color(0xFFFF9BB3),
    ),
    NestNavItem(
      icon: Icons.timer_outlined,
      activeIcon: Icons.timer_rounded,
      label: tr('Exam'),
      accent: const Color(0xFF7ED9A6),
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
          ? tr('Add a course from the menu first, so the note has somewhere to '
              'live')
          : tr('Add a subject first so the note has somewhere to live'));
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
    //
    // With no subject chosen in the drawer the editor shows the first subject
    // as if it were picked, so the note has to be filed there too; otherwise it
    // looks filed and is not, and no subject chip ever appears on it.
    final subjects = _repo.subjects();
    final note = await _repo.createNote(
      title: kind == CaptureKind.photo ? tr('Handwritten note') : tr('PDF note'),
      subjectId: subject?.id ?? (subjects.isNotEmpty ? subjects.first.id : null),
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
    if (added && mounted) _toast(tr('Subject added'));
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

  /// The floating To-do button: a small yellow pill at the right, above the
  /// bar, that pops in and out. Yellow is the app's "do this next" colour. It
  /// carries a count of what is overdue or due today.
  Widget _todoButton() {
    return ValueListenableBuilder<bool>(
        valueListenable: _scrolling,
        builder: (context, scrolling, _) {
      final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
      final show =
          _tab != _todoTab && !_tabHasOwnButton && !typing && !scrolling;
      final due = _repo.overdueTasks.length + _repo.tasksDueToday.length;
      final t = Theme.of(context).textTheme;
      // The button slot hands its child tight constraints; Align lets the pill
      // be just as big as its contents instead of filling the slot.
      return Align(
        widthFactor: 1,
        heightFactor: 1,
        child: IgnorePointer(
          ignoring: !show,
          child: AnimatedScale(
            scale: show ? 1 : 0,
            alignment: Alignment.bottomRight,
            duration: const Duration(milliseconds: 260),
            curve: show ? Curves.easeOutBack : Curves.easeIn,
            child: AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Semantics(
                key: _todoKey,
                button: true,
                label: due > 0 ? trp('To-do, {0} due', [due]) : tr('To-do'),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(NestRadius.pill),
                    boxShadow: NestShadow.lifted,
                  ),
                  child: Material(
                    color: NestColor.highlight,
                    borderRadius: BorderRadius.circular(NestRadius.pill),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(NestRadius.pill),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _tab = _todoTab);
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 18, 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.checklist_rounded,
                                size: 22, color: NestColor.onHighlight),
                            const SizedBox(width: 8),
                            Text(
                              tr('To-do'),
                              style: t.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: NestColor.onHighlight,
                              ),
                            ),
                            if (due > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                constraints: const BoxConstraints(
                                    minWidth: 20, minHeight: 20),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                // No `alignment` here: a Container with one
                                // fills all the height it is offered, which
                                // stretched the whole pill to the screen.
                                decoration: BoxDecoration(
                                  color: NestColor.redPen,
                                  borderRadius:
                                      BorderRadius.circular(NestRadius.pill),
                                ),
                                child: Text(
                                  trp('{0}', [due]),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _scaffold(BuildContext context) {
    // Back closes the drawer first, then returns to Today, and only then
    // leaves the app. Without this, Android 16's predictive back sent a Back
    // pressed with the drawer open straight out of the app.
    return PopScope(
      canPop: !_drawerOpen && _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_drawerOpen) {
          _scaffoldKey.currentState?.closeDrawer();
        } else {
          setState(() => _tab = 0);
        }
      },
      child: _shellScaffold(context),
    );
  }

  Widget _shellScaffold(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      onDrawerChanged: (open) => setState(() => _drawerOpen = open),
      extendBody: true,
      drawer: NestDrawer(
        userName: _repo.userName,
        userPhoto: myPhoto(),
        semester: _teacher
            ? (_repo.teachingCourse ?? _repo.university ?? tr('Teacher'))
            : shownSemester(_repo.semesterLabel ?? tr('No semester set')),
        subjects: _repo.subjects(),
        // A teacher has no semesters to look back through.
        links: _repo
            .drawerLinks()
            .where((l) => !_teacher || l.id != 'semesters')
            .toList(),
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
            case 'timer':
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StudyTimerPage()),
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
            tooltip: tr('Menu'),
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(barContext).openDrawer(),
          ),
        ),
        title: Text(
          'NoteNest',
          style: TextStyle(
            fontFamily: NestFont.display,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: ls(-0.3),
            color: NestColor.ink,
          ),
        ),
        actions: [
          IconButton(
            key: _searchKey,
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded),
            tooltip: tr('Search notes'),
          ),
          const NoticeBell(),
          const SizedBox(width: 6),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: IndexedStack(
        index: _tab,
        children: [
          TodayPage(
            avatarKey: _avatarKey,
            onOpenNotes: () => setState(() => _tab = 1),
            onCapture: _teacher ? _openTeacherCapture : _openCapture,
            onOpenExams: () => setState(() => _tab = _examTab),
            onOpenClasses: () => setState(() => _tab = _peopleTab),
            onOpenTasks: () => setState(() => _tab = _todoTab),
            onOpenCourse: (code) => setState(() {
              _drawerSelection = code;
              _tab = 1;
            }),
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
          // The fifth page: no place on the bar, reached from the floating
          // button.
          TasksPage(
            embedded: true,
            onBack: () => setState(() => _tab = 0),
          ),
        ],
        ),
      ),
      floatingActionButton: _todoButton(),
      // The planner is typed into line by line; with the keyboard up the bar
      // would take a fifth of what is left, so it steps aside there.
      bottomNavigationBar: Builder(
        builder: (barContext) =>
            _tab == _todoTab && MediaQuery.viewInsetsOf(barContext).bottom > 0
                ? const SizedBox.shrink()
                : NestNavBar(
                    items: _teacher ? _teacherItems : _items,
                    // None of the four while the To-do page is up.
                    currentIndex: _tab == _todoTab ? -1 : _tab,
                    onTap: (i) => setState(() => _tab = i),
                    onCapture: _teacher ? _openTeacherCapture : _openCapture,
                    itemKeys: _tabKeys,
                    captureKey: _captureKey,
                  ),
      ),
    );
  }
}
