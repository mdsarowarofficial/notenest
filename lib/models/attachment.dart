/// What kind of file is attached to a note.
enum AttachmentType { image, pdf, audio }

extension AttachmentTypeData on AttachmentType {
  String get key => name;

  String get label {
    switch (this) {
      case AttachmentType.image:
        return 'Photo';
      case AttachmentType.pdf:
        return 'PDF';
      case AttachmentType.audio:
        return 'Recording';
    }
  }

  static AttachmentType fromKey(String? key) {
    switch (key) {
      case 'pdf':
        return AttachmentType.pdf;
      case 'audio':
        return AttachmentType.audio;
      default:
        return AttachmentType.image;
    }
  }
}

/// A file stored beside a note.
///
/// Only the file name is kept in the database. The folder it sits in is asked
/// for at runtime, because the application's data directory changes between
/// installs and between devices — storing an absolute path would break every
/// attachment the first time the app is reinstalled.
class Attachment {
  const Attachment({
    this.id,
    required this.noteId,
    required this.type,
    required this.fileName,
    required this.storedName,
    this.sizeBytes = 0,
    this.pageCount,
    this.durationMs,
    this.position = 0,
    required this.createdAt,
  });

  final int? id;
  final int noteId;
  final AttachmentType type;

  /// What the student will recognise, e.g. "lecture-04.pdf".
  final String fileName;

  /// The unique name on disk, e.g. "a_1736500000000.pdf".
  final String storedName;

  final int sizeBytes;
  final int? pageCount;

  /// How long a recording runs. Null for anything that is not audio.
  ///
  /// Stored rather than read back from the file, so a list of recordings can
  /// show its lengths without opening every file.
  final int? durationMs;

  /// Order within the note, so multi-page captures stay in sequence.
  final int position;

  final DateTime createdAt;

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  String get readableSize {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Attachment copyWith({int? id, int? position}) => Attachment(
        id: id ?? this.id,
        noteId: noteId,
        type: type,
        fileName: fileName,
        storedName: storedName,
        sizeBytes: sizeBytes,
        pageCount: pageCount,
        durationMs: durationMs,
        position: position ?? this.position,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'note_id': noteId,
        'type': type.key,
        'file_name': fileName,
        'stored_name': storedName,
        'size_bytes': sizeBytes,
        'page_count': pageCount,
        'duration_ms': durationMs,
        'position': position,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Attachment.fromMap(Map<String, Object?> m) => Attachment(
        id: m['id'] as int?,
        noteId: m['note_id'] as int,
        type: AttachmentTypeData.fromKey(m['type'] as String?),
        fileName: m['file_name'] as String? ?? '',
        storedName: m['stored_name'] as String? ?? '',
        sizeBytes: m['size_bytes'] as int? ?? 0,
        pageCount: m['page_count'] as int?,
        durationMs: m['duration_ms'] as int?,
        position: m['position'] as int? ?? 0,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
      );
}
