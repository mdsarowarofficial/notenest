import '../l10n/strings.dart';
/// Where a note sits in the revision cycle. Exam Mode orders notes by this.
enum StudyStatus { newNote, read, review, mastered }

extension StudyStatusData on StudyStatus {
  String get label {
    switch (this) {
      case StudyStatus.newNote:
        return tr('New');
      case StudyStatus.read:
        return tr('Read');
      case StudyStatus.review:
        return tr('Review');
      case StudyStatus.mastered:
        return tr('Mastered');
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

  /// What the student is shown. "text" is the word that is stored; "Written"
  /// is the one that reads correctly in a filter chip or a sentence.
  String get label {
    switch (this) {
      case NoteType.text:
        return tr('Written');
      case NoteType.image:
        return tr('Photo');
      case NoteType.pdf:
        return 'PDF';
      case NoteType.voice:
        return tr('Voice');
    }
  }

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

/// What the sender asked the receiver to do with a shared note.
///
/// This is a request, not a lock. NoteNest has no server, so there is nothing
/// to enforce it with — the receiver's copy is an ordinary note on their own
/// phone. The screens say this plainly rather than implying the file is
/// protected, because a permission that is only a label should not look like
/// one that is not.
enum SharePolicy { open, reference }

extension SharePolicyData on SharePolicy {
  String get key => name;

  String get label {
    switch (this) {
      case SharePolicy.open:
        return tr('Free to edit and pass on');
      case SharePolicy.reference:
        return tr('Please keep as reference');
    }
  }

  String get shortLabel {
    switch (this) {
      case SharePolicy.open:
        return tr('OPEN');
      case SharePolicy.reference:
        return tr('REFERENCE');
    }
  }

  static SharePolicy fromKey(String? key) =>
      key == 'reference' ? SharePolicy.reference : SharePolicy.open;
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
    this.sharedBy,
    this.sharedAt,
    this.sharePolicy,
    this.audioMs = 0,
    this.nextReviewAt,
    this.reviewStep = 0,
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

  /// Who shared this note, if it came from someone else. Null for the
  /// student's own notes.
  ///
  /// Kept so credit is not lost. A note that came from a classmate stays
  /// visibly theirs, however long it sits in the notebook.
  final String? sharedBy;

  /// When it was imported.
  final DateTime? sharedAt;

  /// What the sender asked for. Null for the student's own notes.
  final SharePolicy? sharePolicy;

  /// When the note is next due to be looked at again, or null if it is not
  /// scheduled. See review_schedule.dart.
  final DateTime? nextReviewAt;

  /// How many times in a row the note has been remembered.
  final int reviewStep;

  /// Total length of the recordings attached, in milliseconds. Worked out by
  /// the query that loads the note, not stored on it.
  final int audioMs;

  bool get isDeleted => deletedAt != null;

  bool get isShared => sharedBy != null && sharedBy!.isNotEmpty;

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
    String? sharedBy,
    DateTime? sharedAt,
    SharePolicy? sharePolicy,
    DateTime? nextReviewAt,
    bool clearReview = false,
    int? reviewStep,
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
        sharedBy: sharedBy ?? this.sharedBy,
        sharedAt: sharedAt ?? this.sharedAt,
        sharePolicy: sharePolicy ?? this.sharePolicy,
        audioMs: audioMs,
        nextReviewAt: clearReview ? null : (nextReviewAt ?? this.nextReviewAt),
        reviewStep: reviewStep ?? this.reviewStep,
      );

  /// Android reads a database row through a 2 MB window and the whole notebook
  /// is loaded at launch, so one enormous note would make every launch fail.
  /// 200,000 characters is about a hundred pages of typing and stays under
  /// 1 MB even when every character is Bangla or an emoji.
  static const maxBody = 200000;
  static const maxTitle = 300;
  static const maxTopic = 200;

  static String _clip(String s, int max) {
    if (s.length <= max) return s;
    var end = max;
    // Do not cut an emoji in half.
    final last = s.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return s.substring(0, end);
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'subject_id': subjectId,
        'topic': topic == null ? null : _clip(topic!, maxTopic),
        'title': _clip(title, maxTitle),
        'body': _clip(body, maxBody),
        'tags': tags.join(','),
        'type': type.key,
        'important': important ? 1 : 0,
        'status': status.key,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'opened_at': openedAt?.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
        'shared_by': sharedBy,
        'shared_at': sharedAt?.millisecondsSinceEpoch,
        'share_policy': sharePolicy?.key,
        'next_review_at': nextReviewAt?.millisecondsSinceEpoch,
        'review_step': reviewStep,
      };

  factory Note.fromMap(Map<String, Object?> m) {
    final rawTags = (m['tags'] as String? ?? '').trim();
    final policy = m['share_policy'] as String?;
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
      sharedBy: m['shared_by'] as String?,
      sharedAt: m['shared_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(m['shared_at'] as int),
      sharePolicy:
          policy == null ? null : SharePolicyData.fromKey(policy),
      audioMs: (m['audio_ms'] as num?)?.toInt() ?? 0,
      nextReviewAt: m['next_review_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(m['next_review_at'] as int),
      reviewStep: (m['review_step'] as int?) ?? 0,
    );
  }
}

/// "Yesterday", "3 days ago" and so on, for note lists.
String relativeDay(DateTime when) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(when.year, when.month, when.day);
  final days = today.difference(that).inDays;

  if (days <= 0) return tr('Today');
  if (days == 1) return tr('Yesterday');
  if (days < 7) return trp('{0} days ago', [days]);
  if (days < 30) {
    final weeks = (days / 7).floor();
    return weeks == 1 ? tr('Last week') : trp('{0} weeks ago', [weeks]);
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return localDate('${when.day} ${months[when.month - 1]}');
}
