import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/attachment.dart';
import '../models/exam.dart';
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

/// SQLite treats `%` and `_` inside LIKE as wildcards, so a student searching
/// for "50%" would otherwise match every note. Each needle escapes them with a
/// backslash and every LIKE declares that backslash as its escape character.
const _likeEscape = "ESCAPE '\\'";

/// The one place every screen asks for data.
///
/// Everything is scoped to the signed-in account, so two students sharing a
/// phone never see each other's subjects or notes.
class NoteRepository extends ChangeNotifier {
  NoteRepository._();

  static final NoteRepository instance = NoteRepository._();

  static const _kSemester = 'semester_label';
  static const _kSemesterSystem = 'semester_system';
  static const _kRole = 'account_role';
  static const _kReminder = 'revision_reminder';
  static const _kSetupDone = 'setup_done';
  static const _kRecentSearches = 'recent_searches';
  static const _kCoverDraft = 'cover_draft';
  static const _kBrandLogo = 'brand_logo';

  final _db = AppDatabase.instance;
  final _auth = AuthRepository.instance;

  // ------------------------------------------------------------------ state

  String? semesterLabel;

  /// How this student's university counts semesters, so the picker reopens
  /// where they left it rather than at the top of the list.
  SemesterSystem semesterSystem = SemesterSystem.bi;

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
    roleKey = map[_kRole] == 'teacher' ? 'teacher' : 'student';
    reminderChoice = map[_kReminder];
    setupDone = map[_kSetupDone] == '1';
    coverDraft = map[_kCoverDraft];
    brandLogo = BrandStore.decode(map[_kBrandLogo]);
    _recentSearches = _splitSearches(map[_kRecentSearches]);

    await _reloadSubjects();
    await _reloadNotes();
    await _reloadExams();
    notifyListeners();
  }

  /// Clears in-memory state on sign out.
  void clear() {
    _subjects = const [];
    _notes = const [];
    _exams = const [];
    _recentSearches = const [];
    semesterLabel = null;
    semesterSystem = SemesterSystem.bi;
    roleKey = 'student';
    reminderChoice = null;
    setupDone = false;
    coverDraft = null;
    brandLogo = null;
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

  /// Records that the note was opened, so Exam Mode and the "Recently opened"
  /// order have something to work from.
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
    var subject = code.isEmpty ? null : subjectByCode(code);

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
    final rows = await _db.db.query(
      'attachments',
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'position ASC, id ASC',
    );
    return rows.map(Attachment.fromMap).toList();
  }

  Future<int> attachmentCount(int noteId) async {
    final rows = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM attachments WHERE note_id = ?',
      [noteId],
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
    await _db.db
        .delete('attachments', where: 'id = ?', whereArgs: [attachment.id]);
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

  /// Removes the row for good, with its files. Only reachable from Trash.
  Future<void> deleteNoteForever(Note note) async {
    if (note.id == null) return;
    if (AttachmentStore.isSupported) {
      for (final a in await attachmentsFor(note.id!)) {
        await AttachmentStore.delete(a.storedName);
      }
    }
    // The attachment rows go with the note through ON DELETE CASCADE.
    await _db.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    notifyListeners();
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
    await _db.db
        .update('exams', exam.toMap(), where: 'id = ?', whereArgs: [exam.id]);
    await _reloadExams();
    notifyListeners();
  }

  Future<void> deleteExam(Exam exam) async {
    if (exam.id == null) return;
    await _db.db.delete('exams', where: 'id = ?', whereArgs: [exam.id]);
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
