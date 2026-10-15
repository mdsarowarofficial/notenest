import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat.dart';
import '../models/classwork.dart';
import '../models/cloud_profile.dart';
import '../models/study_group.dart';
import 'cloud_service.dart';
import 'drive_service.dart';

/// A file picked on the phone, waiting to go to Drive.
class PendingFile {
  const PendingFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

/// Classwork: what a teacher posts to a class and what comes back.
///
/// A class is a group with `kind: 'class'` — see [StudyGroup] — so joining by
/// code, the member list and the class chat are the group's and are not
/// repeated here. This adds the two collections underneath it.
///
/// Files never go into Firestore. They go to the poster's own Google Drive and
/// the post carries the Drive id, because a document is capped at a megabyte
/// and a week of slides is not. See [DriveService] for how the link reaches the
/// rest of the class.
class ClassroomService {
  ClassroomService._();

  static final ClassroomService instance = ClassroomService._();

  final _cloud = CloudService.instance;

  FirebaseFirestore get _store => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _posts(String classId) =>
      _store.collection('groups').doc(classId).collection('posts');

  CollectionReference<Map<String, dynamic>> _submissions(
    String classId,
    String postId,
  ) =>
      _posts(classId).doc(postId).collection('submissions');

  String _requireUid() {
    final id = _cloud.uid;
    if (!_cloud.isReady || id == null) {
      throw const CloudException('You are not connected to the cloud.');
    }
    return id;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      throw CloudException(describeStoreError(e.code));
    }
  }

  // ---------------------------------------------------------------- classes

  /// The classes this account teaches or is in, live.
  Stream<List<StudyGroup>> watchClasses() => _cloud
      .watchGroups()
      .map((groups) => groups.where((g) => g.isClass).toList());

  // ------------------------------------------------------------------ posts

  /// Everything posted to a class, newest first.
  ///
  /// One `orderBy` on one field, which Firestore indexes on its own — no
  /// console step before a class can open.
  Stream<List<ClassPost>> watchPosts(String classId) {
    if (!_cloud.isReady) return Stream.value(const []);
    return _posts(classId)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ClassPost.fromMap(d.id, d.data())).toList());
  }

  Stream<ClassPost?> watchPost(String classId, String postId) {
    if (!_cloud.isReady) return Stream.value(null);
    return _posts(classId).doc(postId).snapshots().map(
          (d) => d.data() == null ? null : ClassPost.fromMap(d.id, d.data()!),
        );
  }

  /// Uploads files to the poster's Drive, under NoteNest/Classes/[folder],
  /// and makes each one openable by link.
  Future<List<ClassFile>> uploadFiles(
    List<PendingFile> files, {
    required List<String> folder,
  }) async {
    final drive = DriveService.instance;
    final out = <ClassFile>[];
    for (final f in files) {
      final mime = mimeTypeFor(f.name);
      final made = await drive.upload(
        bytes: f.bytes,
        name: f.name,
        mimeType: mime,
        folderPath: ['Classes', ...folder],
      );
      await drive.shareByLink(made.id);
      out.add(ClassFile(
        driveId: made.id,
        name: f.name,
        mimeType: mime,
        size: f.bytes.length,
      ));
    }
    return out;
  }

  /// Posts to a class. Teacher only — the rules refuse anyone else.
  Future<void> createPost({
    required StudyGroup classGroup,
    required PostKind kind,
    required String title,
    String body = '',
    String topic = '',
    DateTime? dueAt,
    int? points,
    List<ClassFile> files = const [],
  }) async {
    final me = _requireUid();
    final name = _cloud.profile?.name ?? '';
    await _guard(() async {
      final doc = _posts(classGroup.id).doc();
      await doc.set(ClassPost(
        id: doc.id,
        kind: kind,
        title: title,
        body: body,
        topic: topic,
        dueAt: kind == PostKind.assignment ? dueAt : null,
        points: kind == PostKind.assignment ? points : null,
        files: files,
        authorUid: me,
        authorName: name,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ).toMap());
    });
  }

  /// Moves a deadline, or edits the words. Files are not re-sent.
  Future<void> updatePost(
    String classId,
    ClassPost post, {
    String? title,
    String? body,
    String? topic,
    DateTime? dueAt,
    bool clearDue = false,
    int? points,
    bool clearPoints = false,
  }) async {
    _requireUid();
    await _guard(() => _posts(classId).doc(post.id).update({
          if (title != null) 'title': title.trim(),
          if (body != null) 'body': body.trim(),
          if (topic != null) 'topic': topic.trim(),
          if (clearDue)
            'dueAt': null
          else if (dueAt != null)
            'dueAt': dueAt.millisecondsSinceEpoch,
          if (clearPoints)
            'points': null
          else if (points != null)
            'points': points,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        }));
  }

  /// Deletes a post. The files stay in the teacher's Drive, where they are the
  /// teacher's to keep or remove; deleting somebody's slides as a side effect
  /// of tidying a class would be a surprise.
  ///
  /// Submissions under it are not reachable once the post is gone, and the
  /// client cannot list another student's work to delete it — so the teacher's
  /// app deletes them first, which it is allowed to read.
  Future<void> deletePost(String classId, ClassPost post) async {
    _requireUid();
    await _guard(() async {
      final subs = await _submissions(classId, post.id).get();
      final batch = _store.batch();
      for (final s in subs.docs) {
        batch.delete(s.reference);
      }
      batch.delete(_posts(classId).doc(post.id));
      await batch.commit();
    });
  }

  // ------------------------------------------------------------ submissions

  /// This student's own work on one assignment.
  Stream<Submission?> watchMySubmission(String classId, String postId) {
    final me = _cloud.uid;
    if (!_cloud.isReady || me == null) return Stream.value(null);
    return _submissions(classId, postId).doc(me).snapshots().map(
          (d) => d.data() == null ? null : Submission.fromMap(d.id, d.data()!),
        );
  }

  /// Every student's work on one assignment. The teacher's view.
  Stream<List<Submission>> watchSubmissions(String classId, String postId) {
    if (!_cloud.isReady) return Stream.value(const []);
    return _submissions(classId, postId).snapshots().map((snap) =>
        snap.docs.map((d) => Submission.fromMap(d.id, d.data())).toList());
  }

  /// Saves the student's work, handed in or not.
  ///
  /// `merge`, so the grade and feedback fields — which only the teacher may
  /// write — are never part of what the student sends.
  Future<void> saveMyWork({
    required String classId,
    required String postId,
    required String text,
    required List<ClassFile> files,
    required bool turnIn,
  }) async {
    final me = _requireUid();
    await _guard(() => _submissions(classId, postId).doc(me).set(
          Submission(
            uid: me,
            name: _cloud.profile?.name ?? '',
            text: text,
            files: files,
            state: turnIn ? SubmissionState.turnedIn : SubmissionState.draft,
            submittedAt: turnIn ? DateTime.now() : null,
          ).toStudentMap(),
          SetOptions(merge: true),
        ));
  }

  /// Grades a piece of work and hands it back. Teacher only.
  Future<void> returnWork({
    required String classId,
    required String postId,
    required String studentUid,
    int? grade,
    String feedback = '',
  }) async {
    _requireUid();
    await _guard(() => _submissions(classId, postId).doc(studentUid).update({
          'grade': grade,
          'feedback': feedback.trim(),
          'state': SubmissionState.returned.key,
          'returnedAt': DateTime.now().millisecondsSinceEpoch,
        }));
  }

  /// Posts a reminder in the class chat naming who has not handed in.
  ///
  /// Something Google Classroom leaves to the teacher's own email: here the
  /// reminder lands where the class already talks, and names nobody publicly
  /// unless the teacher chooses to send it.
  Future<void> remindMissing({
    required StudyGroup classGroup,
    required ClassPost post,
    required int missingCount,
  }) async {
    final due =
        post.dueAt == null ? '' : ' It is due ${formatDue(post.dueAt!)}.';
    await _cloud.sendMessage(
      chatId: groupChatId(classGroup.id),
      kind: MessageKind.text,
      groupId: classGroup.id,
      text: 'Reminder: "${post.title}" is still waiting on '
          '$missingCount ${missingCount == 1 ? 'student' : 'students'}.$due '
          'Open the class → Classwork to hand it in.',
    );
  }

  /// Profiles of everybody in a class, teacher first.
  Future<List<CloudProfile>> people(StudyGroup classGroup) async {
    final found = await _cloud.profilesFor(classGroup.memberUids);
    found.sort((a, b) {
      if (a.uid == classGroup.ownerUid) return -1;
      if (b.uid == classGroup.ownerUid) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return found;
  }
}
