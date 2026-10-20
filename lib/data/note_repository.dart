import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/attachment.dart';
import '../models/exam.dart';
import '../models/day_plan.dart';
import '../models/task.dart';
import '../models/course_file.dart';
import '../models/note.dart';
import '../models/semester.dart';
import '../models/note_bundle.dart';
import '../models/note_query.dart';
import '../models/subject.dart';
import '../widgets/nest_drawer.dart';
import 'app_database.dart';
import 'attachment_store.dart';
import 'brand_store.dart';
import 'auth_repository.dart';
import 'drive_service.dart';

/// SQLite treats `%` and `_` inside LIKE as wildcards, so a student searching
/// for "50%" would otherwise match every note. Each needle escapes them with a
/// backslash and every LIKE declares that backslash as its escape character.
const _likeEscape = "ESCAPE '\\'";

/// The one place every screen asks for data.
///
/// Everything is scoped to the signed-in account, so two students sharing a
/// phone never see each other's subjects or notes.
class NoteRepository extends ChangeNotifier {
  NoteRepository._() {
    // Registered here rather than left to whichever screen happens to sign
    // out: the account's rows leave memory because the account left, not
    // because a particular button remembered to ask.
    AuthRepository.instance.addSignOutHook(clear);
  }

  static final NoteRepository instance = NoteRepository._();

  static const _kSemester = 'semester_label';
  static const _kSemesterSystem = 'semester_system';
  static const _kUniversity = 'university';
  static const _kProgrammeStart = 'programme_start';
  static const _kProgrammeEnd = 'programme_end';
  static const _kManualSemester = 'manual_semester';
  static const _kRole = 'account_role';
  static const _kReminder = 'revision_reminder';
  static const _kSetupDone = 'setup_done';
  static const _kRecentSearches = 'recent_searches';
  static const _kCoverDraft = 'cover_draft';
  static const _kBrandLogo = 'brand_logo';
  static const _kImportedShares = 'imported_shares';
  static const _kPhoto = 'profile_photo';
  static const _kTourDone = 'tour_done';
  static const _kHiddenChats = 'hidden_chats';
  static const _kNoticeSeen = 'notice_seen';
  static const _kRemindOn = 'remind_on';
  static const _kRemindIdle = 'remind_idle';
  static const _kNoticeOff = 'notice_off';
  static const _kCourse = 'teaching_course';
  static const _kBackupAt = 'drive_backup_at';
  static const _kBackupAuto = 'drive_backup_auto';

  final _db = AppDatabase.instance;
  final _auth = AuthRepository.instance;

  // ------------------------------------------------------------------ state

  String? semesterLabel;

  /// How this student's university counts semesters, so the picker reopens
  /// where they left it rather than at the top of the list.
  SemesterSystem semesterSystem = SemesterSystem.bi;

  /// Where the degree is being taken, when it started, when it is expected to
  /// end. Together with the system these are what let the app work out which
  /// semester today falls in instead of asking every time.
  String? university;
  DateTime? programmeStart;
  DateTime? programmeEnd;

  /// Set only when the student has moved off the computed semester. Terms
  /// slip; an app that argues with somebody about their own degree is wrong.
  int? manualSemester;

  /// Student or teacher, kept on the device as well as in the cloud profile.
  ///
  /// The cloud is optional, so the answer has to live somewhere that works
  /// without it — otherwise a teacher who has not connected an account would
  /// be offered a student's screens.
  String roleKey = 'student';

  String? reminderChoice;
  bool setupDone = false;

  /// The university logo the student picked once, as PNG bytes.
  ///
  /// Null until they choose one. Kept decoded in memory because every cover
  /// page preview rebuild would otherwise decode the same base64 again.
  Uint8List? brandLogo;

  /// The last cover page the student filled in, as JSON.
  ///
  /// Kept so the institution, department, their name and their ID do not have
  /// to be retyped for every assignment. [CoverSpec.asNextDraft] decides what
  /// carries over and what is cleared.
  String? coverDraft;

  /// The account's own photo, a small square JPEG. Null shows initials.
  Uint8List? profilePhoto;

  /// True once the first-run tour has been shown to this account.
  bool tourDone = false;

  /// What a teacher said they teach at setup, free text. Optional, and only a
  /// teacher is asked: it fills the subject line of a new class.
  String? teachingCourse;

  /// When this account's notes were last copied to Google Drive, and whether
  /// that should happen on its own once a day.
  DateTime? lastBackupAt;
  bool autoBackup = false;

  List<Subject> _subjects = const [];

  String get userName => _auth.currentUser?.name ?? '';

  List<Subject> subjects() => List.unmodifiable(_subjects);

  bool get hasSubjects => _subjects.isNotEmpty;

  /// Case-insensitive, because the database is: the unique index on subjects
  /// is on `LOWER(code)`. An exact comparison here meant an imported note for
  /// "cse112" found no "CSE112", tried to create a second one, and the insert
  /// failed on that index — taking the whole import down with it.
  Subject? subjectByCode(String code) {
    final wanted = code.trim().toLowerCase();
    for (final s in _subjects) {
      if (s.code.trim().toLowerCase() == wanted) return s;
    }
    return null;
  }

  Subject? subjectById(int id) {
    for (final s in _subjects) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ------------------------------------------------------------------- load

  /// Reads everything belonging to the signed-in account.
  Future<void> load() async {
    if (!_auth.isSignedIn) {
      clear();
      return;
    }

    final rows = await _db.db.query(
      'user_settings',
      where: 'user_id = ?',
      whereArgs: [_auth.requireUserId],
    );
    final map = {
      for (final r in rows) r['key'] as String: r['value'] as String?,
    };
    semesterLabel = map[_kSemester];
    semesterSystem = SemesterSystemData.fromKey(map[_kSemesterSystem]);
    university = map[_kUniversity];
    programmeStart = _readDate(map[_kProgrammeStart]);
    programmeEnd = _readDate(map[_kProgrammeEnd]);
    manualSemester = int.tryParse(map[_kManualSemester] ?? '');
    roleKey = map[_kRole] == 'teacher' ? 'teacher' : 'student';
    reminderChoice = map[_kReminder];
    setupDone = map[_kSetupDone] == '1';
    coverDraft = map[_kCoverDraft];
    brandLogo = BrandStore.decode(map[_kBrandLogo]);
    _recentSearches = _splitSearches(map[_kRecentSearches]);
    _importedShares = _splitSearches(map[_kImportedShares]).toSet();
    profilePhoto = BrandStore.decode(map[_kPhoto]);
    tourDone = map[_kTourDone] == '1';
    _hiddenChats = _parseHidden(map[_kHiddenChats]);
    noticeSeenAt = _readDate(map[_kNoticeSeen]);
    remindersOn = map[_kRemindOn] == '1';
    idleReminder = map[_kRemindIdle] == '1';
    noticeOff = (map[_kNoticeOff] ?? '')
        .split(',')
        .where((g) => g.isNotEmpty)
        .toSet();
    teachingCourse = map[_kCourse];
    lastBackupAt = _readDate(map[_kBackupAt]);
    autoBackup = map[_kBackupAuto] == '1';

    await _reloadSubjects();
    await _reloadNotes();
    await _reloadExams();
    await _reloadTasks();
    await _reloadDayPlan();
    notifyListeners();
  }

  /// Clears in-memory state on sign out.
  void clear() {
    _subjects = const [];
    _allSubjects = const [];
    _notes = const [];
    _exams = const [];
    _tasks = const [];
    _goals = const [];
    _dayLogs = const {};
    _hiddenChats = const {};
    noticeSeenAt = null;
    remindersOn = false;
    idleReminder = false;
    noticeOff = const {};
    _recentSearches = const [];
    _importedShares = {};
    semesterLabel = null;
    semesterSystem = SemesterSystem.bi;
    university = null;
    programmeStart = null;
    programmeEnd = null;
    manualSemester = null;
    roleKey = 'student';
    reminderChoice = null;
    setupDone = false;
    coverDraft = null;
    brandLogo = null;
    profilePhoto = null;
    tourDone = false;
    teachingCourse = null;
    lastBackupAt = null;
    autoBackup = false;
    notifyListeners();
  }

  /// Every course this account has ever had, archived ones included.
  ///
  /// The semester record is a history, so it has to contain courses that are
  /// no longer current — a student looking back at semester 3 wants the five
  /// courses that were there, not the two they have not archived yet.
  List<Subject> _allSubjects = const [];

  Future<void> _reloadSubjects() async {
    final rows = await _db.db.query(
      'subjects',
      where: 'user_id = ?',
      whereArgs: [_auth.requireUserId],
      orderBy: 'created_at ASC',
    );
    _allSubjects = rows.map(Subject.fromMap).toList();
    // The working list stays what it always was: what is current.
    _subjects = _allSubjects.where((s) => !s.archived).toList();
    _applyCounts();
  }

  /// Fills each subject's note count and mastery from the loaded notes.
  void _applyCounts() {
    Subject counted(Subject s) => s.copyWith(
          noteCount: noteCountForSubject(s.id),
          mastery: masteryForSubject(s.id),
        );
    _allSubjects = _allSubjects.map(counted).toList();
    _subjects = _subjects.map(counted).toList();
  }

  Future<void> _setSetting(String key, String? value) async {
    await _db.db.insert(
      'user_settings',
      {'user_id': _auth.requireUserId, 'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --------------------------------------------------------------- semester

  /// Milliseconds in a settings row, or null when it is absent or nonsense.
  static DateTime? _readDate(String? raw) {
    final ms = int.tryParse(raw ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// The degree as a span of time. Built fresh each read so it can never
  /// disagree with the settings it comes from.
  SemesterPlan get semesterPlan => SemesterPlan(
        system: semesterSystem,
        university: university,
        start: programmeStart,
        end: programmeEnd,
        manualSemester: manualSemester,
      );

  /// Which semester today falls in, or null when the degree has no start date.
  int? get currentSemester => semesterPlan.semesterFor(DateTime.now());

  /// The semester the student last agreed to, which is what courses are filed
  /// under until they accept a new one.
  int? get settledSemester =>
      manualSemester ?? semesterNumberIn(semesterLabel);

  /// A semester has begun that the student has not acknowledged yet.
  ///
  /// The screen asks rather than moving them, because university dates slip by
  /// weeks and being told you are in semester 5 while you are still sitting
  /// semester 4's exams is worse than being asked.
  int? get semesterAwaitingAcceptance {
    final now = currentSemester;
    if (now == null) return null;
    final settled = settledSemester;
    if (settled == null) return now;
    return now > settled ? now : null;
  }

  /// Records the degree itself. Courses are not touched.
  Future<void> saveProgramme({
    String? university,
    DateTime? start,
    DateTime? end,
    SemesterSystem? system,
    bool clearEnd = false,
  }) async {
    if (university != null) {
      this.university = university.trim();
      await _setSetting(_kUniversity, this.university);
    }
    if (start != null) {
      programmeStart = start;
      await _setSetting(
          _kProgrammeStart, start.millisecondsSinceEpoch.toString());
    }
    if (clearEnd) {
      programmeEnd = null;
      await _setSetting(_kProgrammeEnd, null);
    } else if (end != null) {
      programmeEnd = end;
      await _setSetting(_kProgrammeEnd, end.millisecondsSinceEpoch.toString());
    }
    if (system != null) {
      semesterSystem = system;
      await _setSetting(_kSemesterSystem, system.key);
    }
    notifyListeners();
  }

  /// Moves to [number] and remembers that the student agreed to it.
  ///
  /// Courses already filed under earlier semesters stay where they are. That
  /// is the whole point of the record: semester 3 keeps its five courses and
  /// their notes for good, and semester 4 starts empty.
  Future<void> enterSemester(int number) async {
    manualSemester = number;
    await _setSetting(_kManualSemester, number.toString());
    semesterLabel = semesterLabelFor(number);
    await _setSetting(_kSemester, semesterLabel);
    notifyListeners();
  }

  /// Gives up the manual choice and goes back to whatever the dates say.
  Future<void> followTheCalendar() async {
    manualSemester = null;
    await _setSetting(_kManualSemester, null);
    final now = currentSemester;
    if (now != null) {
      semesterLabel = semesterLabelFor(now);
      await _setSetting(_kSemester, semesterLabel);
    }
    notifyListeners();
  }

  /// Every semester that has a course filed under it, newest first, plus the
  /// one the student is in even when it is still empty.
  List<int> get semestersWithCourses {
    final seen = <int>{
      for (final s in _allSubjects)
        if (s.semesterNo != null) s.semesterNo!,
    };
    final now = settledSemester ?? currentSemester;
    if (now != null) seen.add(now);
    final list = seen.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// The courses taught in one semester. Archived ones are included, because
  /// this is a record of what happened rather than a list of what is current.
  List<Subject> subjectsInSemester(int number) => List.unmodifiable(
        _allSubjects.where((s) => s.semesterNo == number),
      );

  /// Courses with no semester at all — everything created before the degree
  /// was dated.
  List<Subject> get subjectsWithoutSemester => List.unmodifiable(
        _allSubjects.where((s) => s.semesterNo == null),
      );

  /// Files every undated course under [number].
  ///
  /// Offered once, after the degree dates are first set, and never run on its
  /// own: a migration that silently decides which term a year of notes
  /// belonged to is not something anybody can check afterwards.
  Future<int> fileLooseCoursesInto(int number) async {
    final loose = subjectsWithoutSemester;
    if (loose.isEmpty) return 0;
    for (final subject in loose) {
      await _db.db.update(
        'subjects',
        {'semester_no': number},
        where: 'id = ? AND user_id = ?',
        whereArgs: [subject.id, _auth.requireUserId],
      );
    }
    await _reloadSubjects();
    notifyListeners();
    return loose.length;
  }

  /// Moves one course to another semester, for when it was filed wrong.
  Future<void> moveSubjectToSemester(Subject subject, int? number) async {
    if (subject.id == null) return;
    await _db.db.update(
      'subjects',
      {'semester_no': number},
      where: 'id = ? AND user_id = ?',
      whereArgs: [subject.id, _auth.requireUserId],
    );
    await _reloadSubjects();
    notifyListeners();
  }

  Future<void> saveSemester(String semester, {SemesterSystem? system}) async {
    semesterLabel = semester.trim();
    await _setSetting(_kSemester, semesterLabel);
    if (system != null) {
      semesterSystem = system;
      await _setSetting(_kSemesterSystem, system.key);
    }
    notifyListeners();
  }

  /// Records whether this account is a student's or a teacher's.
  Future<void> saveRole(String key) async {
    roleKey = key == 'teacher' ? 'teacher' : 'student';
    await _setSetting(_kRole, roleKey);
    notifyListeners();
  }

  bool get isTeacher => roleKey == 'teacher';

  Future<void> saveProfilePhoto(Uint8List? jpeg) async {
    profilePhoto = jpeg;
    await _setSetting(_kPhoto, jpeg == null ? null : BrandStore.encode(jpeg));
    notifyListeners();
  }

  // --------------------------------------------------------- notifications

  /// When the notification centre was last emptied; anything newer is unread.
  DateTime? noticeSeenAt;

  /// Notification groups this account switched off.
  Set<String> noticeOff = const {};

  /// Local reminders (tasks, exams) ringing while the app is closed. Off
  /// until the person turns it on, which is also when permission is asked.
  bool remindersOn = false;

  /// One gentle nudge after a few days away. Needs [remindersOn].
  bool idleReminder = false;

  Future<void> setReminders({bool? on, bool? idle}) async {
    if (on != null) {
      remindersOn = on;
      await _setSetting(_kRemindOn, on ? '1' : null);
    }
    if (idle != null) {
      idleReminder = idle;
      await _setSetting(_kRemindIdle, idle ? '1' : null);
    }
    notifyListeners();
  }

  Future<void> markNoticesSeen() async {
    noticeSeenAt = DateTime.now();
    await _setSetting(_kNoticeSeen, noticeSeenAt!.millisecondsSinceEpoch.toString());
    notifyListeners();
  }

  Future<void> setNoticeGroup(String group, {required bool enabled}) async {
    noticeOff = enabled ? ({...noticeOff}..remove(group)) : {...noticeOff, group};
    await _setSetting(_kNoticeOff, noticeOff.join(','));
    notifyListeners();
  }

  // ------------------------------------------------------ hidden chats

  /// Conversations this account has removed from its own list, with the
  /// moment it did. Local to this device and account: the conversation, and
  /// the other person's copy of it, are untouched.
  Map<String, int> _hiddenChats = const {};

  static Map<String, int> _parseHidden(String? raw) {
    final out = <String, int>{};
    for (final part in (raw ?? '').split(',')) {
      final i = part.lastIndexOf(':');
      if (i <= 0) continue;
      final at = int.tryParse(part.substring(i + 1));
      if (at != null) out[part.substring(0, i)] = at;
    }
    return out;
  }

  /// True when [chatId] was removed and nothing newer has arrived since. A
  /// new message brings the conversation back on its own.
  bool isChatHidden(String chatId, DateTime? lastAt) {
    final at = _hiddenChats[chatId];
    if (at == null) return false;
    return lastAt == null || lastAt.millisecondsSinceEpoch <= at;
  }

  Future<void> hideChat(String chatId) async {
    _hiddenChats = {..._hiddenChats, chatId: DateTime.now().millisecondsSinceEpoch};
    await _setSetting(_kHiddenChats,
        _hiddenChats.entries.map((e) => '${e.key}:${e.value}').join(','));
    notifyListeners();
  }

  Future<void> saveTourDone(bool done) async {
    tourDone = done;
    await _setSetting(_kTourDone, done ? '1' : null);
    notifyListeners();
  }

  Future<void> saveTeachingCourse(String? course) async {
    final clean = course?.trim();
    teachingCourse = (clean == null || clean.isEmpty) ? null : clean;
    await _setSetting(_kCourse, teachingCourse);
    notifyListeners();
  }

  Future<void> saveBackupState({DateTime? at, bool? auto}) async {
    if (at != null) {
      lastBackupAt = at;
      await _setSetting(_kBackupAt, at.millisecondsSinceEpoch.toString());
    }
    if (auto != null) {
      autoBackup = auto;
      await _setSetting(_kBackupAuto, auto ? '1' : null);
    }
    notifyListeners();
  }

  Future<void> saveReminder(String choice) async {
    reminderChoice = choice;
    await _setSetting(_kReminder, choice);
    notifyListeners();
  }

  Future<void> completeSetup() async {
    setupDone = true;
    await _setSetting(_kSetupDone, '1');
    notifyListeners();
  }

  /// Saves, or clears, the logo used on cover pages.
  ///
  /// This one does notify: the cover preview has to redraw the moment a logo
  /// is picked, and that is the whole point of picking it.
  Future<void> saveBrandLogo(Uint8List? png) async {
    brandLogo = png;
    await _setSetting(_kBrandLogo, png == null ? null : BrandStore.encode(png));
    notifyListeners();
  }

  /// Remembers the cover page for next time.
  ///
  /// Deliberately does not notify: the cover screen already holds the spec it
  /// just saved, and waking every other listener to tell them a draft changed
  /// would rebuild the whole app for nothing.
  Future<void> saveCoverDraft(String json) async {
    coverDraft = json;
    await _setSetting(_kCoverDraft, json);
  }

  // --------------------------------------------------------------- subjects

  Future<Subject> addSubject({
    required String name,
    required String code,
    required int colorIndex,
    int? semesterNo,
  }) async {
    final subject = Subject(
      userId: _auth.requireUserId,
      name: name.trim(),
      code: code.trim(),
      colorIndex: colorIndex,
      // Stamped with the semester the student is in unless the caller names
      // one. A course added today belongs to today's term; working that out
      // later from a creation date would be guesswork.
      semesterNo: semesterNo ?? settledSemester ?? currentSemester,
      createdAt: DateTime.now(),
    );
    final id = await _db.db.insert('subjects', subject.toMap());
    await _reloadSubjects();
    notifyListeners();
    return subject.copyWith(id: id);
  }

  Future<void> updateSubject(Subject subject) async {
    if (subject.id == null) return;
    await _db.db.update(
      'subjects',
      subject.toMap(),
      where: 'id = ? AND user_id = ?',
      whereArgs: [subject.id, _auth.requireUserId],
    );
    await _reloadSubjects();
    notifyListeners();
  }

  /// Archives rather than deletes, so notes filed under it are never orphaned.
  Future<void> archiveSubject(int id) async {
    await _db.db.update(
      'subjects',
      {'archived': 1},
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, _auth.requireUserId],
    );
    await _reloadSubjects();
    notifyListeners();
  }

  /// Brings an archived course back. Nothing was removed when it was archived,
  /// so there is nothing to rebuild.
  Future<void> unarchiveSubject(int id) async {
    await _db.db.update(
      'subjects',
      {'archived': 0},
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, _auth.requireUserId],
    );
    await _reloadSubjects();
    notifyListeners();
  }

  /// Every course including archived ones, for the course manager.
  List<Subject> allSubjects() => List.unmodifiable(_allSubjects);

  /// True when another subject in this account already uses the code.
  bool codeExists(String code, {int? ignoreId}) {
    final c = code.trim().toLowerCase();
    return _subjects.any((s) => s.code.toLowerCase() == c && s.id != ignoreId);
  }

  /// The palette slot to offer next, so two subjects rarely share a colour.
  int get nextColorIndex => _subjects.length;

  // ----------------------------------------------------------------- notes

  List<Note> _notes = const [];

  /// Live notes, newest first. Trash is kept out of every normal list.
  List<Note> notes() => List.unmodifiable(_notes);

  bool get hasNotes => _notes.isNotEmpty;

  List<Note> recentNotes({int limit = 5}) =>
      List.unmodifiable(_notes.take(limit));

  List<Note> notesForSubject(int? subjectId) => List.unmodifiable(
        subjectId == null
            ? _notes
            : _notes.where((n) => n.subjectId == subjectId),
      );

  Note? noteById(int id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  int get unrevisedCount =>
      _notes.where((n) => n.status != StudyStatus.mastered).length;

  int get importantUnrevisedCount => _notes
      .where((n) => n.important && n.status != StudyStatus.mastered)
      .length;

  int noteCountForSubject(int? subjectId) =>
      _notes.where((n) => n.subjectId == subjectId).length;

  double masteryForSubject(int? subjectId) {
    final list = _notes.where((n) => n.subjectId == subjectId).toList();
    if (list.isEmpty) return 0;
    final done =
        list.where((n) => n.status == StudyStatus.mastered).length;
    return done / list.length;
  }

  int countWithStatus(StudyStatus status) =>
      _notes.where((n) => n.status == status).length;

  int countWithType(NoteType type) =>
      _notes.where((n) => n.type == type).length;

  int get importantCount => _notes.where((n) => n.important).length;

  Future<void> _reloadNotes() async {
    final rows = await _db.db.query(
      'notes',
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [_auth.requireUserId],
      orderBy: 'updated_at DESC',
    );
    _notes = rows.map(Note.fromMap).toList();
    _applyCounts();
  }

  /// Creates a note and returns it with its new id.
  Future<Note> createNote({
    required String title,
    String body = '',
    int? subjectId,
    String? topic,
    List<String> tags = const [],
  }) async {
    final now = DateTime.now();
    final note = Note(
      userId: _auth.requireUserId,
      subjectId: subjectId,
      topic: topic?.trim().isEmpty == true ? null : topic?.trim(),
      title: title.trim(),
      body: body,
      tags: normalizeTags(tags),
      createdAt: now,
      updatedAt: now,
    );
    final id = await _db.db.insert('notes', note.toMap());
    await _reloadNotes();
    notifyListeners();
    return note.copyWith(id: id);
  }

  Future<void> updateNote(Note note) async {
    if (note.id == null) return;
    await _db.db.update(
      'notes',
      note.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ? AND user_id = ?',
      whereArgs: [note.id, _auth.requireUserId],
    );
    await _reloadNotes();
    notifyListeners();
  }

  Future<void> setStatus(Note note, StudyStatus status) =>
      updateNote(note.copyWith(status: status));

  Future<void> toggleImportant(Note note) =>
      updateNote(note.copyWith(important: !note.important));

  /// Records that the note was opened, so Exam Mode and the "Recently opened"
  /// order have something to work from.
  Future<void> markOpened(Note note) async {
    if (note.id == null) return;
    await _db.db.update(
      'notes',
      {'opened_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND user_id = ?',
      whereArgs: [note.id, _auth.requireUserId],
    );
    await _reloadNotes();
  }

  // ------------------------------------------------------- search and filter

  /// Narrows and orders the notes already held in memory.
  ///
  /// The Notes tab uses this rather than [searchNotes] so that switching a
  /// filter redraws at once instead of waiting on the database. Both paths
  /// answer the same [NoteQuery]; this one is for a list already on screen,
  /// the SQL one for searching the whole notebook.
  List<Note> queryNotes(NoteQuery query) =>
      List.unmodifiable(query.apply(_notes));

  /// Runs the query against the database. Requirement 6.1.
  ///
  /// Free text is split into words and each word must appear in the title, the
  /// body, the topic or the tags, so the order the student types them in does
  /// not matter.
  Future<List<Note>> searchNotes(NoteQuery query, {int limit = 300}) async {
    if (!_auth.isSignedIn) return const [];

    final where = <String>['user_id = ?', 'deleted_at IS NULL'];
    final args = <Object?>[_auth.requireUserId];

    if (query.subjectId != null) {
      where.add('subject_id = ?');
      args.add(query.subjectId);
    }
    if (query.type != null) {
      where.add('type = ?');
      args.add(query.type!.key);
    }
    if (query.status != null) {
      where.add('status = ?');
      args.add(query.status!.key);
    }
    if (query.importantOnly) {
      where.add('important = 1');
    }
    if (query.tag != null) {
      // Tags live in one comma-joined column. Padding both the column and the
      // needle with commas makes the match exact, so "db" no longer matches
      // the tag "dbms".
      where.add("(',' || tags || ',') LIKE ? $_likeEscape");
      args.add('%,${_escapeLike(normalizeTag(query.tag!))},%');
    }
    for (final term in query.terms) {
      where.add(
        '(title LIKE ? $_likeEscape '
        'OR body LIKE ? $_likeEscape '
        "OR IFNULL(topic, '') LIKE ? $_likeEscape "
        'OR tags LIKE ? $_likeEscape)',
      );
      final needle = '%${_escapeLike(term)}%';
      args.addAll([needle, needle, needle, needle]);
    }

    final rows = await _db.db.query(
      'notes',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: query.sort.orderBy,
      limit: limit,
    );
    return rows.map(Note.fromMap).toList();
  }

  static String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  // ------------------------------------------------------------------ tags

  /// Every tag in use, in alphabetical order, for suggestions and filters.
  List<String> allTags() {
    final seen = <String>{};
    for (final n in _notes) {
      for (final t in n.tags) {
        final clean = normalizeTag(t);
        if (clean.isNotEmpty) seen.add(clean);
      }
    }
    final list = seen.toList()..sort();
    return List.unmodifiable(list);
  }

  /// Tags ordered by how many notes carry them, so the filter bar offers the
  /// ones the student actually uses rather than the alphabet.
  List<String> topTags({int limit = 8}) {
    final counts = <String, int>{};
    for (final n in _notes) {
      for (final t in n.tags) {
        final clean = normalizeTag(t);
        if (clean.isEmpty) continue;
        counts[clean] = (counts[clean] ?? 0) + 1;
      }
    }
    final list = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return List.unmodifiable(list.take(limit));
  }

  int noteCountForTag(String tag) {
    final wanted = normalizeTag(tag);
    return _notes
        .where((n) => n.tags.any((t) => normalizeTag(t) == wanted))
        .length;
  }

  Future<void> updateTags(Note note, List<String> tags) =>
      updateNote(note.copyWith(tags: normalizeTags(tags)));

  // --------------------------------------------------------------- sharing

  /// Notes that arrived from someone else, newest arrival first.
  List<Note> inboxNotes() {
    final list = _notes.where((n) => n.isShared).toList()
      ..sort((a, b) =>
          (b.sharedAt ?? b.updatedAt).compareTo(a.sharedAt ?? a.updatedAt));
    return List.unmodifiable(list);
  }

  /// Who has shared notes with this student, and how many each.
  ///
  /// Derived from the notes themselves rather than kept as a separate contact
  /// list, so it cannot drift out of step with what is actually filed.
  Map<String, int> sharers() {
    final counts = <String, int>{};
    for (final n in _notes) {
      final who = n.sharedBy;
      if (who == null || who.isEmpty) continue;
      counts[who] = (counts[who] ?? 0) + 1;
    }
    return Map.unmodifiable(counts);
  }

  int get sharedCount => _notes.where((n) => n.isShared).length;

  /// Packs a note, and optionally its files, into a bundle to hand over.
  Future<NoteBundle> packForSharing(
    Note note, {
    bool includeFiles = true,
  }) async {
    final subject =
        note.subjectId == null ? null : subjectById(note.subjectId!);

    final files = <BundleFile>[];
    if (includeFiles && note.id != null && AttachmentStore.isSupported) {
      for (final a in await attachmentsFor(note.id!)) {
        final bytes = await AttachmentStore.readBytes(a.storedName);
        // A missing file should not stop the note being shared; the text is
        // the part that matters most.
        if (bytes == null) continue;
        files.add(BundleFile(
          type: a.type,
          fileName: a.fileName,
          bytes: bytes,
          durationMs: a.durationMs,
        ));
      }
    }

    return NoteBundle(
      title: note.title,
      body: note.body,
      topic: note.topic,
      tags: note.tags,
      type: note.type,
      subjectName: subject?.name,
      subjectCode: subject?.code,
      // A note that was itself shared keeps its original author, so passing it
      // on does not quietly rename whoever wrote it.
      sharedBy: note.sharedBy ?? userName,
      policy: note.sharePolicy ?? SharePolicy.open,
      files: files,
      writtenAt: note.createdAt,
    );
  }

  /// Writes a received bundle into the notebook as a new note.
  ///
  /// The sender's subject travels by name and code, never by id, so it is
  /// matched against this account's own subjects by code and created only if
  /// there is no match. That way a classmate's "CSE112" lands in the student's
  /// own CSE112 instead of making a second one.
  Future<Note> importBundle(NoteBundle bundle) async {
    final code = bundle.subjectCode?.trim() ?? '';
    // Archived courses too. The unique index on the code covers every row, so
    // a match that is only archived would otherwise be "missing" here and
    // then refused by the database when a second one was created.
    var subject = code.isEmpty ? null : subjectByCode(code);
    if (subject == null && code.isNotEmpty) {
      final wanted = code.toLowerCase();
      for (final s in _allSubjects) {
        if (s.code.trim().toLowerCase() == wanted) {
          subject = s;
          break;
        }
      }
    }

    if (subject == null && code.isNotEmpty) {
      subject = await addSubject(
        name: (bundle.subjectName?.trim().isNotEmpty ?? false)
            ? bundle.subjectName!.trim()
            : code,
        code: code,
        colorIndex: nextColorIndex,
      );
    }

    final now = DateTime.now();
    final note = Note(
      userId: _auth.requireUserId,
      subjectId: subject?.id,
      topic: bundle.topic,
      title: bundle.title,
      body: bundle.body,
      tags: normalizeTags(bundle.tags),
      type: bundle.type,
      // The receiver has not read it yet, whatever the sender had marked it.
      status: StudyStatus.newNote,
      createdAt: bundle.writtenAt,
      updatedAt: now,
      sharedBy: bundle.sharedBy,
      sharedAt: now,
      sharePolicy: bundle.policy,
    );

    final id = await _db.db.insert('notes', note.toMap());

    if (AttachmentStore.isSupported) {
      for (var i = 0; i < bundle.files.length; i++) {
        final f = bundle.files[i];
        final storedName =
            await AttachmentStore.saveBytes(f.bytes, f.safeExtension);
        await _db.db.insert(
          'attachments',
          Attachment(
            noteId: id,
            type: f.type,
            fileName: f.fileName,
            storedName: storedName,
            sizeBytes: f.sizeBytes,
            durationMs: f.durationMs,
            position: i,
            createdAt: now,
          ).toMap(),
        );
      }
    }

    await _reloadNotes();
    notifyListeners();
    return note.copyWith(id: id);
  }

  // -------------------------------------------------------- imported shares

  /// Cloud shares already added to this notebook, by share id.
  ///
  /// Accepting a share is two steps — add the note here, then tell the cloud —
  /// and they cannot be one transaction, because one is SQLite and the other
  /// is Firestore. When the second failed, the share stayed in the inbox as
  /// waiting, and accepting it again added a second copy. Remembering the id
  /// lets the retry skip straight to the step that failed.
  Set<String> _importedShares = {};

  bool hasImportedShare(String shareId) => _importedShares.contains(shareId);

  Future<void> markShareImported(String shareId) async {
    if (!_auth.isSignedIn) return;
    _importedShares = {..._importedShares, shareId};
    // Bounded: an answered share leaves the inbox, so only recent ids can
    // ever be retried. Sets keep insertion order, so the oldest go first.
    if (_importedShares.length > 300) {
      _importedShares =
          _importedShares.skip(_importedShares.length - 300).toSet();
    }
    await _setSetting(_kImportedShares, _importedShares.join('\n'));
  }

  // -------------------------------------------------------- recent searches

  List<String> _recentSearches = const [];

  List<String> recentSearches() => List.unmodifiable(_recentSearches);

  static List<String> _splitSearches(String? stored) {
    if (stored == null || stored.trim().isEmpty) return const [];
    return stored
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Keeps the last few searches so a repeated lookup is one tap.
  Future<void> rememberSearch(String text) async {
    final q = text.trim();
    if (q.length < 2 || !_auth.isSignedIn) return;

    final kept = _recentSearches
        .where((s) => s.toLowerCase() != q.toLowerCase())
        .toList();
    _recentSearches = [q, ...kept].take(8).toList();
    await _setSetting(_kRecentSearches, _recentSearches.join('\n'));
    notifyListeners();
  }

  Future<void> clearRecentSearches() async {
    _recentSearches = const [];
    if (_auth.isSignedIn) await _setSetting(_kRecentSearches, '');
    notifyListeners();
  }

  // ----------------------------------------------------------- attachments

  /// Files belonging to one note, in capture order.
  Future<List<Attachment>> attachmentsFor(int noteId) async {
    // Scoped to the account like every other read here, rather than trusting
    // that a note id could only ever have come from this account's lists.
    final rows = await _db.db.query(
      'attachments',
      where: 'note_id = ? AND note_id IN (SELECT id FROM notes WHERE user_id = ?)',
      whereArgs: [noteId, _auth.requireUserId],
      orderBy: 'position ASC, id ASC',
    );
    return rows.map(Attachment.fromMap).toList();
  }

  Future<int> attachmentCount(int noteId) async {
    final rows = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM attachments WHERE note_id = ? '
      'AND note_id IN (SELECT id FROM notes WHERE user_id = ?)',
      [noteId, _auth.requireUserId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Records a file that [AttachmentStore] has already copied in.
  Future<Attachment> addAttachment({
    required Note note,
    required AttachmentType type,
    required String fileName,
    required String storedName,
    int sizeBytes = 0,
    int? pageCount,
    int? durationMs,
  }) async {
    final position = await attachmentCount(note.id!);
    final attachment = Attachment(
      noteId: note.id!,
      type: type,
      fileName: fileName,
      storedName: storedName,
      sizeBytes: sizeBytes,
      pageCount: pageCount,
      durationMs: durationMs,
      position: position,
      createdAt: DateTime.now(),
    );
    final id = await _db.db.insert('attachments', attachment.toMap());

    // A note takes the kind of its first attachment, so lists can show what
    // the material actually is.
    if (position == 0 && note.type == NoteType.text) {
      await updateNote(note.copyWith(type: _noteTypeFor(type)));
    } else {
      notifyListeners();
    }
    return attachment.copyWith(id: id);
  }

  NoteType _noteTypeFor(AttachmentType type) {
    switch (type) {
      case AttachmentType.image:
        return NoteType.image;
      case AttachmentType.pdf:
        return NoteType.pdf;
      case AttachmentType.audio:
        return NoteType.voice;
    }
  }

  /// Removes the row and the file together, so nothing is left orphaned.
  Future<void> removeAttachment(Attachment attachment) async {
    await _db.db.delete(
      'attachments',
      where: 'id = ? AND note_id IN (SELECT id FROM notes WHERE user_id = ?)',
      whereArgs: [attachment.id, _auth.requireUserId],
    );
    if (AttachmentStore.isSupported) {
      await AttachmentStore.delete(attachment.storedName);
    }
    notifyListeners();
  }

  // ----------------------------------------------------------------- trash

  /// Moves a note to Trash rather than removing it.
  Future<void> deleteNote(Note note) async {
    if (note.id == null) return;
    await _db.db.update(
      'notes',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND user_id = ?',
      whereArgs: [note.id, _auth.requireUserId],
    );
    await _reloadNotes();
    notifyListeners();
  }

  Future<List<Note>> trashedNotes() async {
    final rows = await _db.db.query(
      'notes',
      where: 'user_id = ? AND deleted_at IS NOT NULL',
      whereArgs: [_auth.requireUserId],
      orderBy: 'deleted_at DESC',
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<void> restoreNote(Note note) async {
    if (note.id == null) return;
    await _db.db.update(
      'notes',
      {'deleted_at': null},
      where: 'id = ? AND user_id = ?',
      whereArgs: [note.id, _auth.requireUserId],
    );
    await _reloadNotes();
    notifyListeners();
  }

  /// Removes the row for good, with its files. Only reachable from Trash.
  Future<void> deleteNoteForever(Note note) async {
    if (note.id == null) return;
    if (AttachmentStore.isSupported) {
      for (final a in await attachmentsFor(note.id!)) {
        await AttachmentStore.delete(a.storedName);
      }
    }
    // The attachment rows go with the note through ON DELETE CASCADE.
    await _db.db.delete(
      'notes',
      where: 'id = ? AND user_id = ?',
      whereArgs: [note.id, _auth.requireUserId],
    );
    notifyListeners();
  }

  // ------------------------------------------------------- course files

  Future<List<CourseFile>> courseFilesFor(int subjectId) async {
    final rows = await _db.db.query(
      'course_files',
      where: 'user_id = ? AND subject_id = ?',
      whereArgs: [_auth.requireUserId, subjectId],
      orderBy: 'created_at DESC',
    );
    return rows.map(CourseFile.fromMap).toList();
  }

  /// Stores a file under a course. Throws a message-ready [String] when the
  /// file is refused (type, size, content, duplicate) or the course is not
  /// this account's.
  Future<CourseFile> addCourseFile({
    required int subjectId,
    required String name,
    required Uint8List bytes,
  }) async {
    if (!AttachmentStore.isSupported) {
      throw 'Files need the phone app.';
    }
    final owned = subjectById(subjectId) ??
        _allSubjects.where((s) => s.id == subjectId).firstOrNull;
    if (owned == null) throw 'That course was not found.';
    final problem = checkCourseFile(name, bytes);
    if (problem != null) throw problem;
    final clean = name.split(RegExp(r'[\\/]')).last.trim();
    final dupe = await _db.db.query(
      'course_files',
      where: 'user_id = ? AND subject_id = ? AND LOWER(file_name) = ? '
          'AND size_bytes = ?',
      whereArgs: [
        _auth.requireUserId,
        subjectId,
        clean.toLowerCase(),
        bytes.length,
      ],
      limit: 1,
    );
    if (dupe.isNotEmpty) throw 'This file is already in the course.';

    // Drive first: the student's Drive is where the file is kept safe, so a
    // full Drive stops the upload here, before anything is saved, and says so.
    // Any other Drive trouble (no network, access not given) keeps the file on
    // the phone and it is uploaded later by [uploadPendingCourseFiles].
    String? driveId;
    final drive = DriveService.instance;
    if (drive.isSupported) {
      try {
        await drive.ensureSpace(bytes.length);
        driveId = await _uploadToDrive(owned, clean, bytes);
      } on DriveException catch (e) {
        if (e.message == DriveService.fullMessage) throw e.message;
      }
    }

    final stored =
        await AttachmentStore.saveBytes(bytes, extensionOf(clean));
    final file = CourseFile(
      userId: _auth.requireUserId,
      subjectId: subjectId,
      fileName: clean,
      storedName: stored,
      sizeBytes: bytes.length,
      createdAt: DateTime.now(),
      driveId: driveId,
    );
    try {
      final id = await _db.db.insert('course_files', file.toMap());
      notifyListeners();
      return CourseFile.fromMap({...file.toMap(), 'id': id});
    } catch (_) {
      await AttachmentStore.delete(stored);
      if (driveId != null) await _dropFromDrive(driveId);
      rethrow;
    }
  }

  /// Puts [bytes] in `NoteNest/Courses/<code>` in the student's Drive.
  Future<String> _uploadToDrive(
    Subject course,
    String name,
    Uint8List bytes, {
    bool prompt = true,
  }) async {
    final up = await DriveService.instance.upload(
      bytes: bytes,
      name: name,
      mimeType: mimeTypeFor(name),
      folderPath: ['Courses', course.code],
      appProperties: {'notenestCourseFile': '1'},
      prompt: prompt,
    );
    return up.id;
  }

  Future<void> _dropFromDrive(String driveId) async {
    try {
      await DriveService.instance.delete(driveId);
    } catch (_) {
      // Already gone or Drive unreachable; the phone copy is what matters here.
    }
  }

  /// Uploads course files that never reached Drive (it was offline or access
  /// was not given). Silent; stops at the first failure and retries next time.
  Future<void> uploadPendingCourseFiles() async {
    if (!DriveService.instance.isSupported || !AttachmentStore.isSupported) {
      return;
    }
    final rows = await _db.db.query(
      'course_files',
      where: 'user_id = ? AND drive_id IS NULL',
      whereArgs: [_auth.requireUserId],
    );
    for (final f in rows.map(CourseFile.fromMap)) {
      final course = _allSubjects.where((s) => s.id == f.subjectId).firstOrNull;
      if (course == null || f.id == null) continue;
      try {
        final bytes = await AttachmentStore.readBytes(f.storedName);
        if (bytes == null) continue;
        await DriveService.instance.ensureSpace(bytes.length, prompt: false);
        final id = await _uploadToDrive(
          course,
          f.fileName,
          bytes,
          prompt: false,
        );
        await _db.db.update(
          'course_files',
          {'drive_id': id},
          where: 'id = ? AND user_id = ?',
          whereArgs: [f.id, _auth.requireUserId],
        );
      } catch (_) {
        return;
      }
    }
    notifyListeners();
  }

  Future<void> removeCourseFile(CourseFile file) async {
    if (file.id == null) return;
    final removed = await _db.db.delete(
      'course_files',
      where: 'id = ? AND user_id = ?',
      whereArgs: [file.id, _auth.requireUserId],
    );
    if (removed > 0) {
      await AttachmentStore.delete(file.storedName);
      final id = file.driveId;
      if (id != null) await _dropFromDrive(id);
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- tasks

  List<Task> _tasks = const [];

  /// Every task of this account in [compareTasks] order. Private by
  /// construction: each query below is scoped to the signed-in user id.
  List<Task> tasks() => List.unmodifiable(_tasks);

  List<Task> get openTasks => _tasks.where((t) => !t.isDone).toList();

  List<Task> get overdueTasks => _tasks.where((t) => t.isOverdue()).toList();

  List<Task> get tasksDueToday =>
      _tasks.where((t) => t.isDueToday() && !t.isOverdue()).toList();

  Future<void> _reloadTasks() async {
    final rows = await _db.db.query(
      'tasks',
      where: 'user_id = ?',
      whereArgs: [_auth.requireUserId],
    );
    _tasks = rows.map(Task.fromMap).toList()..sort(compareTasks);
  }

  Future<Task> addTask({
    required String title,
    String? description,
    DateTime? dueAt,
    TaskPriority priority = TaskPriority.normal,
    int? subjectId,
    bool inProgress = false,
  }) async {
    final clean = title.trim();
    if (clean.isEmpty) throw ArgumentError('A task needs a title.');
    final desc = description?.trim();
    final task = Task(
      userId: _auth.requireUserId,
      subjectId: subjectId,
      title: clean,
      description: desc == null || desc.isEmpty ? null : desc,
      dueAt: dueAt,
      priority: priority,
      inProgress: inProgress,
      createdAt: DateTime.now(),
    );
    final id = await _db.db.insert('tasks', task.toMap());
    await _reloadTasks();
    notifyListeners();
    return task.copyWith(id: id);
  }

  Future<void> updateTask(Task task) async {
    if (task.id == null || task.title.trim().isEmpty) return;
    await _db.db.update(
      'tasks',
      task.toMap(),
      // The user id in the WHERE is the ownership check.
      where: 'id = ? AND user_id = ?',
      whereArgs: [task.id, _auth.requireUserId],
    );
    await _reloadTasks();
    notifyListeners();
  }

  Future<void> setTaskDone(Task task, bool done) => updateTask(
        done
            ? task.copyWith(doneAt: DateTime.now())
            : task.copyWith(clearDone: true),
      );

  Future<void> deleteTask(Task task) async {
    if (task.id == null) return;
    await _db.db.delete(
      'tasks',
      where: 'id = ? AND user_id = ?',
      whereArgs: [task.id, _auth.requireUserId],
    );
    await _reloadTasks();
    notifyListeners();
  }

  // -------------------------------------------------- goals and day notes

  List<Goal> _goals = const [];
  Map<String, DayLog> _dayLogs = const {};

  /// Open goals first, then reached ones, each in the order they were added.
  List<Goal> goals() => List.unmodifiable(_goals);

  /// What was written and rated for [day]; empty when nothing was.
  DayLog dayLog(DateTime day) =>
      _dayLogs[dayKey(day)] ??
      DayLog(userId: _auth.requireUserId, day: dayKey(day));

  Future<void> _reloadDayPlan() async {
    final uid = _auth.requireUserId;
    final goals = await _db.db.query(
      'goals',
      where: 'user_id = ?',
      whereArgs: [uid],
      orderBy: 'created_at ASC',
    );
    _goals = goals.map(Goal.fromMap).toList()
      ..sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
    final logs = await _db.db
        .query('day_logs', where: 'user_id = ?', whereArgs: [uid]);
    _dayLogs = {
      for (final m in logs) (m['day'] as String? ?? ''): DayLog.fromMap(m),
    };
  }

  /// Adds a goal. Returns false when the list already holds [maxGoals] open
  /// goals or the title is empty.
  Future<bool> addGoal(String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return false;
    if (_goals.where((g) => !g.isDone).length >= maxGoals) return false;
    await _db.db.insert(
      'goals',
      Goal(
        userId: _auth.requireUserId,
        title: clean,
        createdAt: DateTime.now(),
      ).toMap(),
    );
    await _reloadDayPlan();
    notifyListeners();
    return true;
  }

  Future<void> updateGoal(Goal goal) async {
    if (goal.id == null || goal.title.trim().isEmpty) return;
    await _db.db.update(
      'goals',
      goal.toMap(),
      where: 'id = ? AND user_id = ?',
      whereArgs: [goal.id, _auth.requireUserId],
    );
    await _reloadDayPlan();
    notifyListeners();
  }

  Future<void> setGoalDone(Goal goal, bool done) => updateGoal(
        done
            ? goal.copyWith(doneAt: DateTime.now())
            : goal.copyWith(clearDone: true),
      );

  Future<void> deleteGoal(Goal goal) async {
    if (goal.id == null) return;
    await _db.db.delete(
      'goals',
      where: 'id = ? AND user_id = ?',
      whereArgs: [goal.id, _auth.requireUserId],
    );
    await _reloadDayPlan();
    notifyListeners();
  }

  /// Saves the note and star rating for [day]. An empty log removes the row.
  Future<void> saveDayLog(DateTime day, {String? thoughts, int? rating}) async {
    final next = dayLog(day).copyWith(
      thoughts: thoughts?.trim(),
      rating: rating?.clamp(0, 5),
    );
    if (next.isEmpty) {
      await _db.db.delete(
        'day_logs',
        where: 'user_id = ? AND day = ?',
        whereArgs: [next.userId, next.day],
      );
    } else {
      await _db.db.insert(
        'day_logs',
        next.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await _reloadDayPlan();
    notifyListeners();
  }

  /// Moves every open task due before today to the end of [day]. Returns how
  /// many moved.
  Future<int> moveOverdueTo(DateTime day) async {
    final n = DateTime.now();
    final start = DateTime(n.year, n.month, n.day);
    final late = _tasks
        .where((t) => !t.isDone && t.dueAt != null && t.dueAt!.isBefore(start))
        .toList();
    final target = DateTime(day.year, day.month, day.day, 23, 59);
    for (final t in late) {
      await _db.db.update(
        'tasks',
        t.copyWith(dueAt: target).toMap(),
        where: 'id = ? AND user_id = ?',
        whereArgs: [t.id, _auth.requireUserId],
      );
    }
    if (late.isNotEmpty) {
      await _reloadTasks();
      notifyListeners();
    }
    return late.length;
  }

  // -------------------------------------------------------------- exams

  List<Exam> _exams = const [];

  /// Every exam, quiz and assignment, soonest first. Past ones are kept —
  /// "what did I sit last week" is a fair thing to ask.
  List<Exam> exams() => List.unmodifiable(_exams);

  List<Exam> upcomingExams() =>
      List.unmodifiable(_exams.where((e) => !e.isPast));

  /// The next one due, or null when nothing is scheduled.
  Exam? get nextExam {
    for (final e in _exams) {
      if (!e.isPast) return e;
    }
    return null;
  }

  DateTime? get nextExamDate => nextExam?.date;

  String? get nextExamSubject {
    final exam = nextExam;
    if (exam == null) return null;
    final subject =
        exam.subjectId == null ? null : subjectById(exam.subjectId!);
    return subject?.code ?? exam.title;
  }

  int? get daysToNextExam => nextExam?.daysAway;

  List<Exam> examsForSubject(int subjectId) =>
      List.unmodifiable(_exams.where((e) => e.subjectId == subjectId));

  /// Everything on one day, for the calendar.
  List<Exam> examsOn(DateTime day) {
    final target = atMidnight(day);
    return List.unmodifiable(
      _exams.where((e) => atMidnight(e.date) == target),
    );
  }

  Future<void> _reloadExams() async {
    final rows = await _db.db.query(
      'exams',
      where: 'user_id = ?',
      whereArgs: [_auth.requireUserId],
      orderBy: 'exam_date ASC',
    );
    _exams = rows.map(Exam.fromMap).toList();
  }

  /// Exams whose reminder window has opened, soonest first.
  ///
  /// This is what the app can do on its own: the reminder is shown the next
  /// time the student opens NoteNest. A notification that arrives while the
  /// app is closed needs a scheduled alarm from the operating system, which is
  /// the one piece of Activity 08 still outstanding.
  List<Exam> dueReminders() =>
      List.unmodifiable(_exams.where((e) => e.reminderIsDue));

  Future<Exam> addExam({
    required String title,
    required DateTime date,
    int? subjectId,
    ExamKind kind = ExamKind.exam,
    String? note,
    int? remindDays,
  }) async {
    final exam = Exam(
      userId: _auth.requireUserId,
      subjectId: subjectId,
      title: title.trim(),
      date: atMidnight(date),
      kind: kind,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      remindDays: remindDays,
      createdAt: DateTime.now(),
    );
    final id = await _db.db.insert('exams', exam.toMap());
    await _reloadExams();
    notifyListeners();
    return exam.copyWith(id: id);
  }

  Future<void> updateExam(Exam exam) async {
    if (exam.id == null) return;
    await _db.db.update(
      'exams',
      exam.toMap(),
      where: 'id = ? AND user_id = ?',
      whereArgs: [exam.id, _auth.requireUserId],
    );
    await _reloadExams();
    notifyListeners();
  }

  Future<void> deleteExam(Exam exam) async {
    if (exam.id == null) return;
    await _db.db.delete(
      'exams',
      where: 'id = ? AND user_id = ?',
      whereArgs: [exam.id, _auth.requireUserId],
    );
    await _reloadExams();
    notifyListeners();
  }

  /// The notes to revise for an exam, in the order Exam Mode recommends.
  ///
  /// An exam with no subject covers the whole notebook, which is what a
  /// student means by "finals".
  List<Note> revisionQueue(Exam exam) {
    final pool = exam.subjectId == null
        ? _notes
        : _notes.where((n) => n.subjectId == exam.subjectId).toList();
    return List.unmodifiable(revisionOrder(pool));
  }

  /// How many of those are not yet Mastered.
  int remainingFor(Exam exam) => revisionQueue(exam)
      .where((n) => n.status != StudyStatus.mastered)
      .length;


  // ------------------------------------------------------------ drawer menu

  /// The drawer is a list of places, not a menu of every feature.
  ///
  /// Chats, Groups, Shared inbox and Note requests used to be four links here.
  /// They are four views of one subject — other people — so they are now four
  /// things you can reach from the People tab, one tap away on the bar you can
  /// already see, instead of behind a hamburger you have to know to open.
  List<NestDrawerLink> drawerLinks() => const [
        NestDrawerLink(
          id: 'cloud',
          label: 'Cloud account',
          icon: Icons.cloud_queue_rounded,
        ),
        NestDrawerLink(
          id: 'cover',
          label: 'Cover page',
          icon: Icons.description_outlined,
        ),
        NestDrawerLink(
          id: 'convert',
          label: 'Convert a file',
          icon: Icons.swap_horiz_rounded,
        ),
        NestDrawerLink(
          id: 'semesters',
          label: 'Semesters',
          icon: Icons.school_outlined,
        ),
        NestDrawerLink(
          id: 'trash',
          label: 'Trash',
          icon: Icons.delete_outline_rounded,
        ),
      ];
}

/// Today's date as the printed-index label used on the home screen.
String todayLabel([DateTime? date]) {
  final d = date ?? DateTime.now();
  const days = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
  ];
  const months = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}
