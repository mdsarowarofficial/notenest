/// Where a note sits in the revision cycle. Exam Mode orders notes by this.
enum StudyStatus { newNote, read, review, mastered }

extension StudyStatusData on StudyStatus {
  String get label {
    switch (this) {
      case StudyStatus.newNote:
        return 'New';
      case StudyStatus.read:
        return 'Read';
      case StudyStatus.review:
        return 'Review';
      case StudyStatus.mastered:
        return 'Mastered';
    }
  }

  /// The value written to the database. Kept separate from [label] so renaming
  /// what the student sees never rewrites stored rows.
  String get key {
    switch (this) {
      case StudyStatus.newNote:
        return 'new';
      case StudyStatus.read:
        return 'read';
      case StudyStatus.review:
        return 'review';
      case StudyStatus.mastered:
        return 'mastered';
    }
  }

  static StudyStatus fromKey(String? key) {
    switch (key) {
      case 'read':
        return StudyStatus.read;
      case 'review':
        return StudyStatus.review;
      case 'mastered':
        return StudyStatus.mastered;
      default:
        return StudyStatus.newNote;
    }
  }
}

/// How the material was captured.
enum NoteType { text, image, pdf, voice }

extension NoteTypeData on NoteType {
  String get key => name;

  static NoteType fromKey(String? key) {
    switch (key) {
      case 'image':
        return NoteType.image;
      case 'pdf':
        return NoteType.pdf;
      case 'voice':
        return NoteType.voice;
      default:
        return NoteType.text;
    }
  }
}

/// One note in the student's notebook.
class Note {
  const Note({
    this.id,
    required this.userId,
    this.subjectId,
    this.topic,
    required this.title,
    this.body = '',
    this.tags = const [],
    this.type = NoteType.text,
    this.important = false,
    this.status = StudyStatus.newNote,
    required this.createdAt,
    required this.updatedAt,
    this.openedAt,
    this.deletedAt,
  });

  final int? id;
  final int userId;
  final int? subjectId;
  final String? topic;
  final String title;
  final String body;
  final List<String> tags;
  final NoteType type;
  final bool important;
  final StudyStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Last time the note was opened. Exam Mode raises notes not seen recently.
  final DateTime? openedAt;

  /// Set when the note is in Trash. Null means it is live.
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  Note copyWith({
    int? id,
    int? subjectId,
    bool clearSubject = false,
    String? topic,
    String? title,
    String? body,
    List<String>? tags,
    NoteType? type,
    bool? important,
    StudyStatus? status,
    DateTime? updatedAt,
    DateTime? openedAt,
    DateTime? deletedAt,
    bool clearDeleted = false,
  }) =>
      Note(
        id: id ?? this.id,
        userId: userId,
        subjectId: clearSubject ? null : (subjectId ?? this.subjectId),
        topic: topic ?? this.topic,
        title: title ?? this.title,
        body: body ?? this.body,
        tags: tags ?? this.tags,
        type: type ?? this.type,
        important: important ?? this.important,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        openedAt: openedAt ?? this.openedAt,
        deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'subject_id': subjectId,
        'topic': topic,
        'title': title,
        'body': body,
        'tags': tags.join(','),
        'type': type.key,
        'important': important ? 1 : 0,
        'status': status.key,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'opened_at': openedAt?.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
      };

  factory Note.fromMap(Map<String, Object?> m) {
    final rawTags = (m['tags'] as String? ?? '').trim();
    return Note(
      id: m['id'] as int?,
      userId: m['user_id'] as int,
      subjectId: m['subject_id'] as int?,
      topic: m['topic'] as String?,
      title: m['title'] as String? ?? '',
      body: m['body'] as String? ?? '',
      tags: rawTags.isEmpty ? const [] : rawTags.split(','),
      type: NoteTypeData.fromKey(m['type'] as String?),
      important: (m['important'] as int? ?? 0) == 1,
      status: StudyStatusData.fromKey(m['status'] as String?),
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int? ?? 0),
      openedAt: m['opened_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(m['opened_at'] as int),
      deletedAt: m['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(m['deleted_at'] as int),
    );
  }
}

/// "Yesterday", "3 days ago" and so on, for note lists.
String relativeDay(DateTime when) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(when.year, when.month, when.day);
  final days = today.difference(that).inDays;

  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  if (days < 30) {
    final weeks = (days / 7).floor();
    return weeks == 1 ? 'Last week' : '$weeks weeks ago';
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${when.day} ${months[when.month - 1]}';
}
