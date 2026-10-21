/// A file kept under a course: slides, handouts, past papers.
///
/// Only the file name and size live in the database; the bytes sit in the
/// app's attachment folder under [storedName]. Validation is plain Dart here
/// so it can be tested without a phone.
library;

import 'dart:typed_data';
import '../l10n/strings.dart';

const maxCourseFileBytes = 25 * 1024 * 1024;

/// What a course accepts. Nothing executable, nothing scriptable.
const courseFileExtensions = [
  'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt', 'png', 'jpg',
  'jpeg',
];

String extensionOf(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

bool _startsWith(Uint8List b, List<int> magic) {
  if (b.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (b[i] != magic[i]) return false;
  }
  return true;
}

/// Null when the file is acceptable, otherwise a message for the person.
///
/// The extension is checked and so is the start of the file, because a name is
/// only a claim: a program renamed to `notes.pdf` is still a program.
String? checkCourseFile(String name, Uint8List bytes) {
  final ext = extensionOf(name);
  if (!courseFileExtensions.contains(ext)) {
    return tr('This type of file is not supported. Use PDF, Word, PowerPoint, '
        'Excel, text or an image.');
  }
  if (bytes.isEmpty) return tr('That file is empty.');
  if (bytes.length > maxCourseFileBytes) {
    return tr('That file is larger than 25 MB.');
  }
  final ok = switch (ext) {
    'pdf' => _startsWith(bytes, [0x25, 0x50, 0x44, 0x46]), // %PDF
    'docx' || 'pptx' || 'xlsx' => _startsWith(bytes, [0x50, 0x4B]), // PK zip
    'doc' || 'ppt' || 'xls' =>
      _startsWith(bytes, [0xD0, 0xCF, 0x11, 0xE0]), // OLE2
    'png' => _startsWith(bytes, [0x89, 0x50, 0x4E, 0x47]),
    'jpg' || 'jpeg' => _startsWith(bytes, [0xFF, 0xD8, 0xFF]),
    _ => !bytes.take(4096).contains(0), // txt: no binary bytes
  };
  return ok ? null : 'This file does not look like a real .$ext file.';
}

class CourseFile {
  const CourseFile({
    this.id,
    required this.userId,
    required this.subjectId,
    required this.fileName,
    required this.storedName,
    this.sizeBytes = 0,
    required this.createdAt,
    this.driveId,
  });

  final int? id;
  final int userId;
  final int subjectId;
  final String fileName;
  final String storedName;
  final int sizeBytes;
  final DateTime createdAt;

  /// Id of the copy in the owner's Drive, or null if it is not there yet.
  final String? driveId;

  String get extension => extensionOf(fileName);
  bool get isPdf => extension == 'pdf';

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'subject_id': subjectId,
        'file_name': fileName,
        'stored_name': storedName,
        'size_bytes': sizeBytes,
        'created_at': createdAt.millisecondsSinceEpoch,
        'drive_id': driveId,
      };

  factory CourseFile.fromMap(Map<String, Object?> m) => CourseFile(
        id: m['id'] as int?,
        userId: m['user_id'] as int,
        subjectId: m['subject_id'] as int,
        fileName: m['file_name'] as String? ?? '',
        storedName: m['stored_name'] as String? ?? '',
        sizeBytes: m['size_bytes'] as int? ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          m['created_at'] as int? ?? 0,
        ),
        driveId: m['drive_id'] as String?,
      );
}
