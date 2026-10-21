import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Opens the local SQLite database and owns the schema.
///
/// Adding a table or a column later means raising [_version] and adding a step
/// to [_upgrade], so an installed app is migrated instead of wiped.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _fileName = 'notenest.db';
  static const _version = 14;

  Database? _db;

  Database get db {
    final d = _db;
    if (d == null) {
      throw StateError('AppDatabase.open() must be awaited before use');
    }
    return d;
  }

  Future<void> open() async {
    if (_db != null) return;

    // The web build keeps the database in IndexedDB and needs its own factory.
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    }

    final path =
        kIsWeb ? _fileName : p.join(await getDatabasesPath(), _fileName);

    _db = await openDatabase(
      path,
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async => _create(db),
      onUpgrade: (db, from, to) async => _upgrade(db, from, to),
    );
  }

  Future<void> _create(Database db) async {
    // One row per account on this device.
    await db.execute('''
      CREATE TABLE users (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT    NOT NULL,
        email         TEXT    NOT NULL,
        institution   TEXT,
        password_hash TEXT    NOT NULL,
        password_salt TEXT    NOT NULL,
        created_at    INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_users_email ON users (LOWER(email))',
    );

    // Device-wide values such as which account is signed in.
    await db.execute('''
      CREATE TABLE app_settings (
        key   TEXT PRIMARY KEY NOT NULL,
        value TEXT
      )
    ''');

    // Per-account values: semester name, reminder choice, setup completion.
    await db.execute('''
      CREATE TABLE user_settings (
        user_id INTEGER NOT NULL,
        key     TEXT    NOT NULL,
        value   TEXT,
        PRIMARY KEY (user_id, key),
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE subjects (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     INTEGER NOT NULL,
        name        TEXT    NOT NULL,
        code        TEXT    NOT NULL,
        color_index INTEGER NOT NULL,
        archived    INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER NOT NULL,
        -- Which semester this course belongs to. Nullable on purpose: a
        -- student who has not told the app when their degree started has no
        -- semester to file it under, and guessing one would be worse than
        -- leaving the question open.
        semester_no INTEGER,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_subjects_user ON subjects (user_id, archived)',
    );
    // Two subjects in one account must not share a code.
    await db.execute(
      'CREATE UNIQUE INDEX idx_subjects_code '
      'ON subjects (user_id, LOWER(code))',
    );

    await _createNotes(db);
    await _createAttachments(db);
    await _createExams(db);
    await _createTasks(db);
    await _createCourseFiles(db);
    await _createDayPlan(db);
    await _createStudySessions(db);
  }

  /// Version 13: one row per sitting of the study timer. Private to the
  /// account and removed with it; deleting a subject keeps the row, unfiled.
  Future<void> _createStudySessions(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS study_sessions (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id    INTEGER NOT NULL,
        subject_id INTEGER,
        started_at INTEGER NOT NULL,
        minutes    INTEGER NOT NULL,
        FOREIGN KEY (user_id)    REFERENCES users (id)    ON DELETE CASCADE,
        FOREIGN KEY (subject_id) REFERENCES subjects (id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_study_user ON study_sessions (user_id, started_at)',
    );
  }

  /// Version 11: goals, and a note and star rating for each day of the to-do
  /// list. Private to the account, and removed with it.
  Future<void> _createDayPlan(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS goals (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id    INTEGER NOT NULL,
        title      TEXT    NOT NULL,
        done_at    INTEGER,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_goals_user ON goals (user_id, done_at)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS day_logs (
        user_id  INTEGER NOT NULL,
        day      TEXT    NOT NULL,
        thoughts TEXT    NOT NULL DEFAULT '',
        rating   INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (user_id, day),
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');
  }

  /// Version 9: files kept under a course. Rows go with the course; the bytes
  /// are removed by the repository when a file is deleted.
  Future<void> _createCourseFiles(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS course_files (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     INTEGER NOT NULL,
        subject_id  INTEGER NOT NULL,
        file_name   TEXT    NOT NULL,
        stored_name TEXT    NOT NULL,
        size_bytes  INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER NOT NULL,
        -- The copy in the owner's Google Drive; null until it is uploaded.
        drive_id    TEXT,
        FOREIGN KEY (user_id)    REFERENCES users (id)    ON DELETE CASCADE,
        FOREIGN KEY (subject_id) REFERENCES subjects (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_course_files_subject '
      'ON course_files (user_id, subject_id, created_at)',
    );
  }

  /// Version 8 added the to-do list. Private to the account that owns it; a
  /// course (subject) is optional, and removing a course keeps its tasks.
  Future<void> _createTasks(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     INTEGER NOT NULL,
        subject_id  INTEGER,
        title       TEXT    NOT NULL,
        description TEXT,
        due_at      INTEGER,
        priority    TEXT    NOT NULL DEFAULT 'normal',
        done_at     INTEGER,
        in_progress INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER NOT NULL,
        FOREIGN KEY (user_id)    REFERENCES users (id)    ON DELETE CASCADE,
        FOREIGN KEY (subject_id) REFERENCES subjects (id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_user_due '
      'ON tasks (user_id, done_at, due_at)',
    );
  }

  /// Version 6 added exams, which also carry the academic calendar: a quiz or
  /// an assignment is the same row with a different `kind`.
  Future<void> _createExams(Database db) async {
    await db.execute('''
      CREATE TABLE exams (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id    INTEGER NOT NULL,
        subject_id INTEGER,
        title      TEXT    NOT NULL,
        exam_date  INTEGER NOT NULL,
        kind       TEXT    NOT NULL DEFAULT 'exam',
        note       TEXT,
        -- Days before the date to remind, or NULL for no reminder.
        remind_days INTEGER,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (user_id)    REFERENCES users (id)    ON DELETE CASCADE,
        FOREIGN KEY (subject_id) REFERENCES subjects (id) ON DELETE SET NULL
      )
    ''');
    // The countdown asks for the soonest date, and the calendar asks for a
    // month of them; both are this index.
    await db.execute(
      'CREATE INDEX idx_exams_user_date ON exams (user_id, exam_date)',
    );
  }

  /// Version 2 added the notes table. Version 5 added the three sharing
  /// columns at the bottom of it.
  Future<void> _createNotes(Database db) async {
    await db.execute('''
      CREATE TABLE notes (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id      INTEGER NOT NULL,
        subject_id   INTEGER,
        topic        TEXT,
        title        TEXT    NOT NULL,
        body         TEXT    NOT NULL DEFAULT '',
        tags         TEXT    NOT NULL DEFAULT '',
        type         TEXT    NOT NULL DEFAULT 'text',
        important    INTEGER NOT NULL DEFAULT 0,
        status       TEXT    NOT NULL DEFAULT 'new',
        created_at   INTEGER NOT NULL,
        updated_at   INTEGER NOT NULL,
        opened_at    INTEGER,
        deleted_at   INTEGER,
        shared_by    TEXT,
        shared_at    INTEGER,
        share_policy TEXT,
        next_review_at INTEGER,
        review_step  INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (user_id)    REFERENCES users (id)    ON DELETE CASCADE,
        FOREIGN KEY (subject_id) REFERENCES subjects (id) ON DELETE SET NULL
      )
    ''');
    // Every list query filters on owner and whether the note is in Trash.
    await db.execute(
      'CREATE INDEX idx_notes_user ON notes (user_id, deleted_at, updated_at)',
    );
    await db.execute(
      'CREATE INDEX idx_notes_subject ON notes (subject_id)',
    );
    // The Shared inbox asks for exactly this.
    await db.execute(
      'CREATE INDEX idx_notes_shared ON notes (user_id, shared_by, shared_at)',
    );
  }

  /// Version 3 added files attached to notes. Version 4 added `duration_ms`
  /// to it, for how long a recording runs.
  Future<void> _createAttachments(Database db) async {
    await db.execute('''
      CREATE TABLE attachments (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id     INTEGER NOT NULL,
        type        TEXT    NOT NULL,
        file_name   TEXT    NOT NULL,
        stored_name TEXT    NOT NULL,
        size_bytes  INTEGER NOT NULL DEFAULT 0,
        page_count  INTEGER,
        duration_ms INTEGER,
        extracted_text TEXT,
        position    INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER NOT NULL,
        FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_attachments_note ON attachments (note_id, position)',
    );
  }

  Future<void> _upgrade(Database db, int from, int to) async {
    // One step per version, so an installed app keeps its data.
    //
    // The `from >=` guards matter. A table created by a step above is created
    // at its *current* shape, columns from later versions included, so a later
    // ALTER would fail on it as a duplicate column. Each ALTER therefore runs
    // only for installs that already had the older table.
    if (from < 2) {
      await _createNotes(db);
    }
    if (from < 3) {
      await _createAttachments(db);
    }
    if (from >= 3 && from < 4) {
      await db.execute('ALTER TABLE attachments ADD COLUMN duration_ms INTEGER');
    }
    if (from >= 2 && from < 5) {
      await db.execute('ALTER TABLE notes ADD COLUMN shared_by TEXT');
      await db.execute('ALTER TABLE notes ADD COLUMN shared_at INTEGER');
      await db.execute('ALTER TABLE notes ADD COLUMN share_policy TEXT');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notes_shared '
        'ON notes (user_id, shared_by, shared_at)',
      );
    }
    if (from < 6) {
      // A whole new table, so no guard is needed — nothing below version 6
      // has it, and version 6 installs go through _create instead.
      await _createExams(db);
    }
    if (from == 8) {
      // Installs that already have the v8 tasks table gain the new column.
      await db.execute(
        'ALTER TABLE tasks ADD COLUMN in_progress INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (from < 9) {
      await _createCourseFiles(db);
    }
    if (from == 9) {
      // Only installs that already had the v9 table lack the column; newer
      // tables are created with it.
      await db.execute('ALTER TABLE course_files ADD COLUMN drive_id TEXT');
    }
    if (from < 11) {
      // Two new tables; nothing existing is touched.
      await _createDayPlan(db);
    }
    if (from >= 3 && from < 14) {
      // The words inside a PDF, for search. Null means "not read yet"; an
      // empty string means "read, and there is no text" (a scan).
      await db.execute('ALTER TABLE attachments ADD COLUMN extracted_text TEXT');
    }
    if (from < 13) {
      // A new table only; nothing existing is touched.
      await _createStudySessions(db);
    }
    if (from >= 2 && from < 12) {
      // Spaced review: when a note is next due, and how many times in a row it
      // has been remembered. Both start empty, so no existing note is
      // scheduled until the student marks it Read, Review or Mastered.
      await db.execute('ALTER TABLE notes ADD COLUMN next_review_at INTEGER');
      await db.execute(
        'ALTER TABLE notes ADD COLUMN review_step INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (from < 8) {
      // A new table only; nothing existing is touched. A fresh install gets it
      // from _create, so this step is for installs coming from 7 or older.
      await _createTasks(db);
    }
    if (from < 7) {
      // Courses gain the semester they were taught in.
      //
      // Added as a nullable column with no backfill here. Every existing
      // course keeps its notes and keeps working; it simply has no semester
      // until the student sets their degree dates, at which point the app
      // offers to file the lot under the semester they are in now. Writing a
      // guess into every row during a migration would be the kind of silent
      // change that is impossible to undo and impossible to notice.
      await db.execute('ALTER TABLE subjects ADD COLUMN semester_no INTEGER');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_subjects_semester '
        'ON subjects (user_id, semester_no)',
      );
    }
  }

  /// Removes one account and everything filed under it.
  Future<void> deleteAccount(int userId) async {
    await db.delete('users', where: 'id = ?', whereArgs: [userId]);
  }
}
