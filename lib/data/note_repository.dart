import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/note.dart';
import '../models/subject.dart';
import '../widgets/nest_drawer.dart';
import 'app_database.dart';
import 'auth_repository.dart';

/// The one place every screen asks for data.
///
/// Everything is scoped to the signed-in account, so two students sharing a
/// phone never see each other's subjects. Notes are still empty because the
/// notes table does not exist yet; when it does, only this file and the note
/// screens change.
class NoteRepository extends ChangeNotifier {
  NoteRepository._();

  static final NoteRepository instance = NoteRepository._();

  static const _kSemester = 'semester_label';
  static const _kReminder = 'revision_reminder';
  static const _kSetupDone = 'setup_done';

  final _db = AppDatabase.instance;
  final _auth = AuthRepository.instance;

  // ------------------------------------------------------------------ state

  String? semesterLabel;
  String? reminderChoice;
  bool setupDone = false;

  List<Subject> _subjects = const [];

  String get userName => _auth.currentUser?.name ?? '';

  List<Subject> subjects() => List.unmodifiable(_subjects);

  bool get hasSubjects => _subjects.isNotEmpty;

  Subject? subjectByCode(String code) {
    for (final s in _subjects) {
      if (s.code == code) return s;
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
      _subjects = const [];
      _notes = const [];
      semesterLabel = null;
      reminderChoice = null;
      setupDone = false;
      notifyListeners();
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
    reminderChoice = map[_kReminder];
    setupDone = map[_kSetupDone] == '1';

    await _reloadSubjects();
    await _reloadNotes();
    notifyListeners();
  }

  /// Clears in-memory state on sign out.
  void clear() {
    _subjects = const [];
    _notes = const [];
    semesterLabel = null;
    reminderChoice = null;
    setupDone = false;
    notifyListeners();
  }

  Future<void> _reloadSubjects() async {
    final rows = await _db.db.query(
      'subjects',
      where: 'user_id = ? AND archived = 0',
      whereArgs: [_auth.requireUserId],
      orderBy: 'created_at ASC',
    );
    _subjects = rows.map(Subject.fromMap).toList();
    _applyCounts();
  }

  /// Fills each subject's note count and mastery from the loaded notes.
  void _applyCounts() {
    _subjects = _subjects
        .map((s) => s.copyWith(
              noteCount: noteCountForSubject(s.id),
              mastery: masteryForSubject(s.id),
            ))
        .toList();
  }

  Future<void> _setSetting(String key, String? value) async {
    await _db.db.insert(
      'user_settings',
      {'user_id': _auth.requireUserId, 'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --------------------------------------------------------------- semester

  Future<void> saveSemester(String semester) async {
    semesterLabel = semester.trim();
    await _setSetting(_kSemester, semesterLabel);
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

  // --------------------------------------------------------------- subjects

  Future<Subject> addSubject({
    required String name,
    required String code,
    required int colorIndex,
  }) async {
    final subject = Subject(
      userId: _auth.requireUserId,
      name: name.trim(),
      code: code.trim(),
      colorIndex: colorIndex,
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
      where: 'id = ?',
      whereArgs: [subject.id],
    );
    await _reloadSubjects();
    notifyListeners();
  }

  /// Archives rather than deletes, so notes filed under it are never orphaned.
  Future<void> archiveSubject(int id) async {
    await _db.db.update(
      'subjects',
      {'archived': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _reloadSubjects();
    notifyListeners();
  }

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
      tags: tags,
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
      where: 'id = ?',
      whereArgs: [note.id],
    );
    await _reloadNotes();
    notifyListeners();
  }

  Future<void> setStatus(Note note, StudyStatus status) =>
      updateNote(note.copyWith(status: status));

  Future<void> toggleImportant(Note note) =>
      updateNote(note.copyWith(important: !note.important));

  /// Records that the note was opened, so Exam Mode can raise stale notes.
  Future<void> markOpened(Note note) async {
    if (note.id == null) return;
    await _db.db.update(
      'notes',
      {'opened_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [note.id],
    );
    await _reloadNotes();
  }

  // ----------------------------------------------------------------- trash

  /// Moves a note to Trash rather than removing it.
  Future<void> deleteNote(Note note) async {
    if (note.id == null) return;
    await _db.db.update(
      'notes',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [note.id],
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
      where: 'id = ?',
      whereArgs: [note.id],
    );
    await _reloadNotes();
    notifyListeners();
  }

  /// Removes the row for good. Only reachable from Trash, after a warning.
  Future<void> deleteNoteForever(Note note) async {
    if (note.id == null) return;
    await _db.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    notifyListeners();
  }

  // ------------------------------------------------------- exam (not built)

  DateTime? nextExamDate;
  String? nextExamSubject;

  int? get daysToNextExam {
    final exam = nextExamDate;
    if (exam == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(exam.year, exam.month, exam.day).difference(today).inDays;
  }

  bool get isSynced => false;

  // ------------------------------------------------------------ drawer menu

  List<NestDrawerLink> drawerLinks() => const [
        NestDrawerLink(
          id: 'inbox',
          label: 'Shared inbox',
          icon: Icons.move_to_inbox_rounded,
        ),
        NestDrawerLink(
          id: 'groups',
          label: 'Study groups',
          icon: Icons.groups_rounded,
        ),
        NestDrawerLink(
          id: 'requests',
          label: 'Note requests',
          icon: Icons.pending_actions_rounded,
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
