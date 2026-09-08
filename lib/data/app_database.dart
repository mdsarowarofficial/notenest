import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Opens the local SQLite database and owns the schema.
///
/// Adding a table later means raising [_version] and adding a step to
/// [_upgrade], so an installed app is migrated instead of wiped.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _fileName = 'notenest.db';
  static const _version = 2;

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
  }

  /// Version 2 added the notes table.
  Future<void> _createNotes(Database db) async {
    await db.execute('''
      CREATE TABLE notes (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id    INTEGER NOT NULL,
        subject_id INTEGER,
        topic      TEXT,
        title      TEXT    NOT NULL,
        body       TEXT    NOT NULL DEFAULT '',
        tags       TEXT    NOT NULL DEFAULT '',
        type       TEXT    NOT NULL DEFAULT 'text',
        important  INTEGER NOT NULL DEFAULT 0,
        status     TEXT    NOT NULL DEFAULT 'new',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        opened_at  INTEGER,
        deleted_at INTEGER,
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
  }

  Future<void> _upgrade(Database db, int from, int to) async {
    // One step per version, so an installed app keeps its data.
    if (from < 2) {
      await _createNotes(db);
    }
  }

  /// Removes one account and everything filed under it.
  Future<void> deleteAccount(int userId) async {
    await db.delete('users', where: 'id = ?', whereArgs: [userId]);
  }
}
