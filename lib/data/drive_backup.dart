import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'app_database.dart';
import 'attachment_store.dart';
import 'auth_repository.dart';
import 'drive_service.dart';
import 'note_repository.dart';

/// What a restore brought back.
class RestoreReport {
  const RestoreReport({
    required this.subjects,
    required this.notes,
    required this.files,
    required this.exams,
    required this.skipped,
  });

  final int subjects;
  final int notes;
  final int files;
  final int exams;

  /// Notes that were already on this phone and so were left alone.
  final int skipped;

  String get summary {
    final parts = <String>[
      '$notes ${notes == 1 ? 'note' : 'notes'}',
      if (files > 0) '$files ${files == 1 ? 'file' : 'files'}',
      if (subjects > 0) '$subjects ${subjects == 1 ? 'subject' : 'subjects'}',
      if (exams > 0) '$exams ${exams == 1 ? 'date' : 'dates'}',
    ];
    final tail =
        skipped > 0 ? ' $skipped already here were left as they were.' : '';
    return 'Restored ${parts.join(', ')}.$tail';
  }
}

/// Copies one account's notebook to its owner's Google Drive, and back.
///
/// Notes live in a database on the phone, and attachments — the PDFs, the
/// photographed pages, the recordings — are files beside it. Lose the phone and
/// both go with it. This puts the whole account into one zip in the student's
/// own Drive, under NoteNest/Backups, where it outlives the phone and can be
/// pulled onto the next one by signing in as the same person.
///
/// One file per account, overwritten each time, found again by app properties
/// rather than by name — so renaming it in Drive does not lose it, and two
/// accounts on one phone never overwrite each other's.
///
/// Restoring **merges**. Nothing already on the phone is deleted or replaced:
/// a course with the same code is reused, a note that already exists (same
/// title, same creation time) is skipped. A restore that wiped the notes
/// written since the backup would be a data-loss feature.
class DriveBackup {
  DriveBackup._();

  static const _format = 'notenest.backup';
  static const _version = 1;
  static const _propKey = 'notenestBackup';
  static const _ownerKey = 'owner';
  static const _mime = 'application/zip';

  /// Settings that describe this phone's backup, not the notebook, and so are
  /// never carried across.
  static const _localOnlySettings = {'drive_backup_at', 'drive_backup_auto'};

  static final _db = AppDatabase.instance;

  /// A row ready to insert under a new id: the old one means nothing here.
  static Map<String, dynamic> _withoutId(Map<String, dynamic> row) =>
      Map.of(row)..remove('id');

  static String _owner() =>
      (AuthRepository.instance.currentUser?.email ?? '').trim().toLowerCase();

  /// Builds the archive and uploads it, replacing the previous backup.
  ///
  /// With [prompt] false nothing is shown on screen: if Drive access has not
  /// been given, this throws instead of asking. That is the daily backup's
  /// mode.
  static Future<DateTime> backUp({bool prompt = true}) async {
    final userId = AuthRepository.instance.requireUserId;
    final owner = _owner();
    final bytes = await _pack(userId);

    final drive = DriveService.instance;
    final existing =
        await drive.findByProperty(_ownerKey, owner, prompt: prompt);
    final mine = existing.where((f) => f.appProperties[_propKey] == '1');

    if (mine.isNotEmpty) {
      await drive.overwrite(
        fileId: mine.first.id,
        bytes: bytes,
        mimeType: _mime,
        prompt: prompt,
      );
    } else {
      await drive.upload(
        bytes: bytes,
        name: 'NoteNest backup ($owner).zip',
        mimeType: _mime,
        folderPath: const ['Backups'],
        appProperties: {_propKey: '1', _ownerKey: owner},
        prompt: prompt,
      );
    }

    final now = DateTime.now();
    await NoteRepository.instance.saveBackupState(at: now);
    return now;
  }

  /// The newest backup of this account in Drive, or null if there is none.
  static Future<DriveFile?> latest() async {
    final found =
        await DriveService.instance.findByProperty(_ownerKey, _owner());
    for (final f in found) {
      if (f.appProperties[_propKey] == '1') return f;
    }
    return null;
  }

  /// Downloads the backup and merges it into this account.
  static Future<RestoreReport> restore(DriveFile file) async {
    final bytes = await DriveService.instance.downloadOwn(file.id);
    final report = await _unpack(AuthRepository.instance.requireUserId, bytes);
    await NoteRepository.instance.load();
    return report;
  }

  /// Backs up once a day if the account asked for it. Silent: never asks for
  /// anything and never throws, because it runs as the notebook opens.
  static Future<void> runDailyIfDue() async {
    final repo = NoteRepository.instance;
    if (!repo.autoBackup || !DriveService.instance.isSupported) return;
    final last = repo.lastBackupAt;
    if (last != null && DateTime.now().difference(last).inHours < 24) return;
    try {
      await backUp(prompt: false);
    } catch (_) {
      // Tried again the next time the notebook opens.
    }
  }

  // ----------------------------------------------------------------- pack

  static Future<Uint8List> _pack(int userId) async {
    final subjects = await _db.db
        .query('subjects', where: 'user_id = ?', whereArgs: [userId]);
    final notes =
        await _db.db.query('notes', where: 'user_id = ?', whereArgs: [userId]);
    final exams =
        await _db.db.query('exams', where: 'user_id = ?', whereArgs: [userId]);
    final settings = await _db.db
        .query('user_settings', where: 'user_id = ?', whereArgs: [userId]);
    final attachments = await _db.db.rawQuery(
      'SELECT * FROM attachments '
      'WHERE note_id IN (SELECT id FROM notes WHERE user_id = ?)',
      [userId],
    );

    final archive = Archive();
    final kept = <Map<String, Object?>>[];
    if (AttachmentStore.isSupported) {
      for (final a in attachments) {
        final stored = a['stored_name'] as String? ?? '';
        final data = await AttachmentStore.readBytes(stored);
        // A row whose file is gone is left out rather than restored as a
        // broken attachment on the next phone.
        if (data == null) continue;
        archive.add(ArchiveFile.bytes('files/$stored', data));
        kept.add(a);
      }
    }

    final manifest = {
      'format': _format,
      'version': _version,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'owner': _owner(),
      'subjects': subjects,
      'notes': notes,
      'exams': exams,
      'attachments': kept,
      'settings': [
        for (final s in settings)
          if (!_localOnlySettings.contains(s['key'])) s,
      ],
    };
    archive.add(
      ArchiveFile.bytes('backup.json', utf8.encode(jsonEncode(manifest))),
    );
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  // --------------------------------------------------------------- unpack

  static Future<RestoreReport> _unpack(int userId, Uint8List bytes) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const DriveException('That backup file is damaged.');
    }
    final entry = archive.find('backup.json');
    final raw = entry?.readBytes();
    if (raw == null) {
      throw const DriveException('That is not a NoteNest backup.');
    }
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    } catch (_) {
      throw const DriveException('That backup file is damaged.');
    }
    if (m['format'] != _format) {
      throw const DriveException('That is not a NoteNest backup.');
    }
    if ((m['version'] as int? ?? 0) > _version) {
      throw const DriveException(
        'That backup was made by a newer NoteNest. Update the app first.',
      );
    }

    List<Map<String, dynamic>> rows(String key) => [
          for (final r in (m[key] as List? ?? const []))
            if (r is Map) Map<String, dynamic>.from(r),
        ];

    var subjectsAdded = 0, notesAdded = 0, filesAdded = 0, examsAdded = 0;
    var skipped = 0;
    final subjectIds = <int, int>{};
    final noteIds = <int, int>{};

    // Files are written before the rows that point at them, outside the
    // transaction (sqflite transactions must not await unrelated futures).
    // A failure part-way leaves unused files, never rows pointing at nothing.
    final storedNames = <String, String>{};
    if (AttachmentStore.isSupported) {
      for (final a in rows('attachments')) {
        final old = a['stored_name'] as String? ?? '';
        final file = archive.find('files/$old');
        final data = file?.readBytes();
        if (data == null) continue;
        final dot = old.lastIndexOf('.');
        final ext = dot < 0 ? 'bin' : old.substring(dot + 1);
        storedNames[old] =
            await AttachmentStore.saveBytes(Uint8List.fromList(data), ext);
      }
    }
    final usedFiles = <String>{};

    await _db.db.transaction((txn) async {
      for (final s in rows('subjects')) {
        final oldId = s['id'] as int?;
        final code = (s['code'] as String? ?? '').trim();
        final existing = await txn.query(
          'subjects',
          columns: ['id'],
          where: 'user_id = ? AND LOWER(code) = ?',
          whereArgs: [userId, code.toLowerCase()],
          limit: 1,
        );
        int newId;
        if (existing.isNotEmpty) {
          newId = existing.first['id'] as int;
        } else {
          newId = await txn.insert('subjects', {
            ..._withoutId(s),
            'user_id': userId,
          });
          subjectsAdded++;
        }
        if (oldId != null) subjectIds[oldId] = newId;
      }

      for (final n in rows('notes')) {
        final oldId = n['id'] as int?;
        final existing = await txn.query(
          'notes',
          columns: ['id'],
          where: 'user_id = ? AND title = ? AND created_at = ?',
          whereArgs: [userId, n['title'], n['created_at']],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          skipped++;
          continue;
        }
        final subject = n['subject_id'] as int?;
        final newId = await txn.insert('notes', {
          ..._withoutId(n),
          'user_id': userId,
          'subject_id': subject == null ? null : subjectIds[subject],
        });
        notesAdded++;
        if (oldId != null) noteIds[oldId] = newId;
      }

      for (final a in rows('attachments')) {
        final note = noteIds[a['note_id'] as int? ?? -1];
        final stored = storedNames[a['stored_name'] as String? ?? ''];
        if (note == null || stored == null) continue;
        await txn.insert('attachments', {
          ..._withoutId(a),
          'note_id': note,
          'stored_name': stored,
        });
        usedFiles.add(stored);
        filesAdded++;
      }

      for (final e in rows('exams')) {
        final existing = await txn.query(
          'exams',
          columns: ['id'],
          where: 'user_id = ? AND title = ? AND exam_date = ?',
          whereArgs: [userId, e['title'], e['exam_date']],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;
        final subject = e['subject_id'] as int?;
        await txn.insert('exams', {
          ..._withoutId(e),
          'user_id': userId,
          'subject_id': subject == null ? null : subjectIds[subject],
        });
        examsAdded++;
      }

      // Only settings this phone does not have yet: what the student chose
      // here, after the backup, wins.
      for (final s in rows('settings')) {
        final key = s['key'] as String?;
        if (key == null || _localOnlySettings.contains(key)) continue;
        await txn.insert(
          'user_settings',
          {'user_id': userId, 'key': key, 'value': s['value']},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });

    // Files written for notes that turned out to be here already.
    for (final name in storedNames.values) {
      if (!usedFiles.contains(name)) await AttachmentStore.delete(name);
    }

    return RestoreReport(
      subjects: subjectsAdded,
      notes: notesAdded,
      files: filesAdded,
      exams: examsAdded,
      skipped: skipped,
    );
  }
}
