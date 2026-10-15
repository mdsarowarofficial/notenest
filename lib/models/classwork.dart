/// What a teacher posts to a class, and what students hand back.
///
/// Free of any Firebase import, like the other cloud models, so the rules for
/// a deadline, a late hand-in and a grade are ordinary Dart.
///
/// Layout in Firestore:
///
///   groups/{classId}/posts/{postId}                     — teacher writes
///   groups/{classId}/posts/{postId}/submissions/{uid}   — one per student
///
/// A submission's document id *is* the student's uid. That makes "has this
/// student handed in?" a `get` of a name already known, makes a second
/// submission impossible rather than merely unlikely, and lets the rules say
/// "your own" without reading anything.
library;

/// The three things a teacher can put in a class.
enum PostKind { announcement, material, assignment }

extension PostKindData on PostKind {
  String get key => name;

  String get label {
    switch (this) {
      case PostKind.announcement:
        return 'Announcement';
      case PostKind.material:
        return 'Material';
      case PostKind.assignment:
        return 'Assignment';
    }
  }

  static PostKind fromKey(String? key) {
    switch (key) {
      case 'material':
        return PostKind.material;
      case 'assignment':
        return PostKind.assignment;
      default:
        return PostKind.announcement;
    }
  }
}

/// A file kept in its owner's Google Drive and shared by link.
class ClassFile {
  const ClassFile({
    required this.driveId,
    required this.name,
    this.mimeType = '',
    this.size = 0,
  });

  final String driveId;
  final String name;
  final String mimeType;
  final int size;

  bool get isPdf =>
      mimeType == 'application/pdf' || name.toLowerCase().endsWith('.pdf');

  bool get isImage => mimeType.startsWith('image/');

  Map<String, Object?> toMap() => {
        'id': driveId,
        'name': name,
        'mime': mimeType,
        'size': size,
      };

  static ClassFile? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    final size = raw['size'];
    final mime = raw['mime'];
    return ClassFile(
      driveId: id,
      name: name,
      mimeType: mime is String ? mime : '',
      size: size is int ? size : 0,
    );
  }

  static List<ClassFile> listFrom(Object? raw) =>
      raw is List ? raw.map(fromMap).whereType<ClassFile>().toList() : const [];
}

const maxPostTitle = 200;
const maxPostBody = 5000;
const maxTopic = 60;
const maxFilesPerPost = 10;
const maxFeedback = 2000;
const maxPoints = 1000;

/// One `groups/{classId}/posts/{postId}` document.
class ClassPost {
  const ClassPost({
    required this.id,
    required this.kind,
    required this.title,
    this.body = '',
    this.topic = '',
    this.dueAt,
    this.points,
    this.files = const [],
    required this.authorUid,
    this.authorName = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final PostKind kind;
  final String title;
  final String body;

  /// Groups classwork the way a syllabus does: "Week 3", "Lab", "Midterm".
  final String topic;

  /// Only an assignment has one, and even then it is optional.
  final DateTime? dueAt;

  /// Out of how many. Null means ungraded, which a teacher may well want for
  /// a piece of practice.
  final int? points;

  final List<ClassFile> files;
  final String authorUid;
  final String authorName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isAssignment => kind == PostKind.assignment;

  bool isPastDue([DateTime? now]) =>
      dueAt != null && (now ?? DateTime.now()).isAfter(dueAt!);

  Map<String, Object?> toMap() => {
        'kind': kind.key,
        'title': title.trim(),
        'body': body.trim(),
        'topic': topic.trim(),
        'dueAt': dueAt?.millisecondsSinceEpoch,
        'points': points,
        'files': files.map((f) => f.toMap()).toList(),
        'authorUid': authorUid,
        'authorName': authorName.trim(),
        'createdAt': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
        'updatedAt': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      };

  factory ClassPost.fromMap(String id, Map<String, Object?> m) {
    String text(String key) {
      final v = m[key];
      return v is String ? v : '';
    }

    DateTime? at(String key) {
      final v = m[key];
      return v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    }

    final points = m['points'];
    return ClassPost(
      id: id,
      kind: PostKindData.fromKey(text('kind')),
      title: text('title'),
      body: text('body'),
      topic: text('topic'),
      dueAt: at('dueAt'),
      points: points is int ? points : null,
      files: ClassFile.listFrom(m['files']),
      authorUid: text('authorUid'),
      authorName: text('authorName'),
      createdAt: at('createdAt'),
      updatedAt: at('updatedAt'),
    );
  }
}

/// Where a student's work stands.
enum SubmissionState { draft, turnedIn, returned }

extension SubmissionStateData on SubmissionState {
  String get key {
    switch (this) {
      case SubmissionState.draft:
        return 'draft';
      case SubmissionState.turnedIn:
        return 'turnedIn';
      case SubmissionState.returned:
        return 'returned';
    }
  }

  static SubmissionState fromKey(String? key) {
    switch (key) {
      case 'turnedIn':
        return SubmissionState.turnedIn;
      case 'returned':
        return SubmissionState.returned;
      default:
        return SubmissionState.draft;
    }
  }
}

/// One `.../submissions/{uid}` document.
class Submission {
  const Submission({
    required this.uid,
    this.name = '',
    this.text = '',
    this.files = const [],
    this.state = SubmissionState.draft,
    this.submittedAt,
    this.grade,
    this.feedback = '',
    this.returnedAt,
    this.updatedAt,
  });

  final String uid;
  final String name;

  /// An answer typed straight in, for work that is a paragraph, not a file.
  final String text;
  final List<ClassFile> files;
  final SubmissionState state;
  final DateTime? submittedAt;
  final int? grade;
  final String feedback;
  final DateTime? returnedAt;
  final DateTime? updatedAt;

  bool get isTurnedIn => state != SubmissionState.draft;

  bool get hasWork => text.trim().isNotEmpty || files.isNotEmpty;

  /// Late is worked out, not stored: it depends on the deadline, which the
  /// teacher may move after the work came in.
  bool isLateFor(ClassPost post) =>
      post.dueAt != null &&
      submittedAt != null &&
      submittedAt!.isAfter(post.dueAt!);

  Map<String, Object?> toStudentMap() => {
        'uid': uid,
        'name': name.trim(),
        'text': text.trim(),
        'files': files.map((f) => f.toMap()).toList(),
        'state': state.key,
        'submittedAt': submittedAt?.millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

  factory Submission.fromMap(String uid, Map<String, Object?> m) {
    String text(String key) {
      final v = m[key];
      return v is String ? v : '';
    }

    DateTime? at(String key) {
      final v = m[key];
      return v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    }

    final grade = m['grade'];
    return Submission(
      uid: uid,
      name: text('name'),
      text: text('text'),
      files: ClassFile.listFrom(m['files']),
      state: SubmissionStateData.fromKey(text('state')),
      submittedAt: at('submittedAt'),
      grade: grade is int ? grade : null,
      feedback: text('feedback'),
      returnedAt: at('returnedAt'),
      updatedAt: at('updatedAt'),
    );
  }
}

/// How one student stands on one assignment, as a single label.
///
/// The order of the checks is the order a teacher reads them in: graded work
/// is graded whether or not it was late; handed-in work is either on time or
/// late; and nothing at all is "missing" only once the deadline has passed —
/// before that it is simply not done yet.
enum WorkStatus { assigned, missing, turnedIn, late, returned }

extension WorkStatusData on WorkStatus {
  String get label {
    switch (this) {
      case WorkStatus.assigned:
        return 'Assigned';
      case WorkStatus.missing:
        return 'Missing';
      case WorkStatus.turnedIn:
        return 'Turned in';
      case WorkStatus.late:
        return 'Turned in late';
      case WorkStatus.returned:
        return 'Graded';
    }
  }
}

WorkStatus workStatus(ClassPost post, Submission? s, [DateTime? now]) {
  if (s != null && s.state == SubmissionState.returned) {
    return WorkStatus.returned;
  }
  if (s != null && s.isTurnedIn) {
    return s.isLateFor(post) ? WorkStatus.late : WorkStatus.turnedIn;
  }
  return post.isPastDue(now) ? WorkStatus.missing : WorkStatus.assigned;
}

/// What is wrong with a post before it is sent, or null.
String? postProblem({
  required PostKind kind,
  required String title,
  required String body,
  int? points,
  DateTime? dueAt,
  int fileCount = 0,
}) {
  final t = title.trim();
  if (kind == PostKind.announcement) {
    if (body.trim().isEmpty && fileCount == 0) {
      return 'Write something to announce.';
    }
  } else if (t.isEmpty) {
    return 'Give it a title.';
  }
  if (t.length > maxPostTitle) return 'Keep the title under $maxPostTitle.';
  if (body.length > maxPostBody) {
    return 'Keep the text under $maxPostBody characters.';
  }
  if (points != null && (points < 1 || points > maxPoints)) {
    return 'Points must be between 1 and $maxPoints.';
  }
  if (fileCount > maxFilesPerPost) {
    return 'At most $maxFilesPerPost files on one post.';
  }
  return null;
}

/// A deadline, written the way a class would say it.
String formatDue(DateTime due, [DateTime? now]) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(due.year, due.month, due.day);
  final diff = day.difference(today).inDays;
  final hour = due.hour % 12 == 0 ? 12 : due.hour % 12;
  final time =
      '$hour:${due.minute.toString().padLeft(2, '0')} ${due.hour < 12 ? 'AM' : 'PM'}';
  if (diff == 0) return 'Today, $time';
  if (diff == 1) return 'Tomorrow, $time';
  if (diff == -1) return 'Yesterday, $time';
  final year = due.year == n.year ? '' : ' ${due.year}';
  return '${due.day} ${months[due.month - 1]}$year, $time';
}
