import 'package:flutter/material.dart';

import '../../data/classroom_service.dart';
import '../../data/cloud_service.dart';
import '../../data/drive_service.dart';
import '../../data/profile_photo.dart';
import '../../models/classwork.dart';
import '../../models/cloud_profile.dart';
import '../../models/study_group.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_mark_tile.dart';
import 'class_files.dart';
import 'classroom_page.dart' show StatusPill;
import '../../l10n/strings.dart';

/// One post, opened. For an assignment this is also where work is handed in
/// (a student) or collected and graded (the teacher).
class PostDetailPage extends StatefulWidget {
  const PostDetailPage({
    super.key,
    required this.classGroup,
    required this.postId,
  });

  final StudyGroup classGroup;
  final String postId;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  late final Stream<ClassPost?> _post =
      ClassroomService.instance.watchPost(widget.classGroup.id, widget.postId);

  bool get _teaching => widget.classGroup.isOwner(CloudService.instance.uid);

  Future<void> _delete(ClassPost post) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(trp('Delete this {0}?', [post.kind.label.toLowerCase()])),
        content: Text(
          post.isAssignment
              ? tr('Students\' handed-in work for it is removed from the class '
                  'too. Their files stay in their own Google Drive, and yours '
                  'stay in yours.')
              : tr('Your files stay in your Google Drive.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('Keep it')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ClassroomService.instance.deletePost(widget.classGroup.id, post);
      navigator.pop();
    } on CloudException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _moveDeadline(ClassPost post) async {
    final now = DateTime.now();
    final start = post.dueAt ?? now.add(const Duration(days: 7));
    final day = await showDatePicker(
      context: context,
      initialDate: start.isBefore(now) ? now : start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
      helpText: tr('New due date'),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay.fromDateTime(post.dueAt ?? DateTime(0, 1, 1, 23, 59)),
    );
    if (!mounted) return;
    final t = time ?? const TimeOfDay(hour: 23, minute: 59);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ClassroomService.instance.updatePost(
        widget.classGroup.id,
        post,
        dueAt: DateTime(day.year, day.month, day.day, t.hour, t.minute),
      );
      messenger.showSnackBar(SnackBar(content: Text(tr('Deadline moved.'))));
    } on CloudException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ClassPost?>(
      stream: _post,
      builder: (context, snap) {
        final post = snap.data;
        if (post == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: snap.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator()
                  : Text(tr('This post was removed.')),
            ),
          );
        }
        final t = Theme.of(context).textTheme;

        return Scaffold(
          appBar: AppBar(
            title: Text(post.kind.label),
            actions: [
              if (_teaching)
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'due') _moveDeadline(post);
                    if (v == 'delete') _delete(post);
                  },
                  itemBuilder: (_) => [
                    if (post.isAssignment)
                      PopupMenuItem(
                          value: 'due', child: Text(tr('Change the deadline'))),
                    PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
                  ],
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
            children: [
              Text(
                post.kind == PostKind.announcement
                    ? (post.authorName.isEmpty ? tr('Teacher') : post.authorName)
                    : post.title,
                style: t.headlineSmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (post.authorName.isNotEmpty &&
                      post.kind != PostKind.announcement)
                    Text(post.authorName, style: t.bodySmall),
                  if (post.points != null)
                    Text(trp('{0} points', [post.points]), style: t.bodySmall),
                  if (post.topic.isNotEmpty)
                    Text(post.topic, style: t.bodySmall),
                ],
              ),
              if (post.dueAt != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: post.isPastDue()
                        ? NestColor.tintRed
                        : NestColor.tintWarm,
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 18,
                        color: post.isPastDue()
                            ? NestColor.redDeep
                            : NestColor.warmDeep,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          trp('{0} {1}', [tr(post.isPastDue() ? tr('Was due') : tr('Due')), formatDue(post.dueAt!)]),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: post.isPastDue()
                                ? NestColor.redDeep
                                : NestColor.warmDeep,
                          ),
                        ),
                      ),
                      if (!_teaching && !post.isPastDue())
                        TextButton(
                          onPressed: () => addDeadlineToExams(
                            context,
                            post,
                            className: widget.classGroup.name,
                          ),
                          child: Text(tr('Add to Exam')),
                        ),
                    ],
                  ),
                ),
              ],
              if (post.body.isNotEmpty) ...[
                const SizedBox(height: 16),
                SelectableText(post.body, style: t.bodyLarge),
              ],
              if (post.files.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(tr('ATTACHED'), style: nestEyebrow),
                const SizedBox(height: 8),
                for (final f in post.files)
                  ClassFileTile(
                    file: f,
                    saveTitle: _teaching
                        ? null
                        : (post.files.length == 1
                            ? post.title
                            : trp('{0} — {1}', [post.title, f.name])),
                    saveTopic: post.topic.isEmpty ? null : post.topic,
                  ),
                if (!_teaching)
                  Text(
                    tr('Tip: ⋮ → Save to my notes keeps a copy on your phone, '
                    'so you can read it offline.'),
                    style: t.bodySmall,
                  ),
              ],
              if (post.isAssignment) ...[
                const SizedBox(height: 26),
                if (_teaching)
                  _TeacherWork(classGroup: widget.classGroup, post: post)
                else
                  _MyWork(classGroup: widget.classGroup, post: post),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------ student side

class _MyWork extends StatefulWidget {
  const _MyWork({required this.classGroup, required this.post});

  final StudyGroup classGroup;
  final ClassPost post;

  @override
  State<_MyWork> createState() => _MyWorkState();
}

class _MyWorkState extends State<_MyWork> {
  late final Stream<Submission?> _mine = ClassroomService.instance
      .watchMySubmission(widget.classGroup.id, widget.post.id);

  final _text = TextEditingController();
  bool _seeded = false;

  /// Files already uploaded but not yet handed in, plus ones just picked.
  List<ClassFile> _files = [];
  final List<PendingFile> _pending = [];

  String? _busy;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    try {
      final picked = await pickClassFiles();
      if (picked.isEmpty || !mounted) return;
      setState(() {
        _pending.addAll(picked);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save({required bool turnIn}) async {
    if (turnIn &&
        _text.text.trim().isEmpty &&
        _files.isEmpty &&
        _pending.isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('Hand in with nothing attached?')),
          content: Text(
            tr('Your teacher will see it marked as done, with no file and no '
            'answer. Use this only if the work was handed in some other way.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr('Mark as done')),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    setState(() {
      _busy = _pending.isEmpty ? tr('Saving…') : tr('Uploading to Google Drive…');
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_pending.isNotEmpty) {
        final up = await ClassroomService.instance.uploadFiles(
          _pending,
          folder: [widget.classGroup.name, widget.post.title],
        );
        _files = [..._files, ...up];
        _pending.clear();
      }
      await ClassroomService.instance.saveMyWork(
        classId: widget.classGroup.id,
        postId: widget.post.id,
        text: _text.text,
        files: _files,
        turnIn: turnIn,
      );
      messenger.showSnackBar(SnackBar(
        content: Text(turnIn ? tr('Handed in.') : tr('Saved — not handed in yet.')),
      ));
    } on DriveException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on CloudException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _unsubmit() async {
    setState(() => _busy = tr('Taking it back…'));
    try {
      await ClassroomService.instance.saveMyWork(
        classId: widget.classGroup.id,
        postId: widget.post.id,
        text: _text.text,
        files: _files,
        turnIn: false,
      );
    } on CloudException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return StreamBuilder<Submission?>(
      stream: _mine,
      builder: (context, snap) {
        final mine = snap.data;
        if (!_seeded && snap.connectionState != ConnectionState.waiting) {
          _seeded = true;
          _text.text = mine?.text ?? '';
          _files = [...?mine?.files];
        }
        final status = workStatus(widget.post, mine);
        final handedIn = mine?.isTurnedIn ?? false;
        final busy = _busy != null;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NestColor.card,
            borderRadius: BorderRadius.circular(NestRadius.card),
            boxShadow: NestShadow.resting,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(tr('Your work'), style: t.titleMedium)),
                  StatusPill(status: status),
                ],
              ),
              if (mine?.state == SubmissionState.returned) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NestColor.tintMint,
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mine!.grade == null
                            ? tr('Returned')
                            : trp('Grade: {0}{1}', [mine.grade, widget.post.points == null ? '' : ' / ${widget.post.points}']),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: NestColor.mintDeep,
                          fontSize: 16,
                        ),
                      ),
                      if (mine.feedback.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(mine.feedback, style: t.bodyMedium),
                      ],
                    ],
                  ),
                ),
              ],
              if (handedIn && mine?.submittedAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  trp('Handed in {0}{1}', [formatDue(mine!.submittedAt!), mine.isLateFor(widget.post) ? tr(' — late') : '']),
                  style: t.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              for (final f in _files)
                ClassFileTile(
                  file: f,
                  onRemove: handedIn || busy
                      ? null
                      : () => setState(() => _files.remove(f)),
                ),
              if (!handedIn) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in _pending)
                      PendingFileChip(
                        file: f,
                        onRemove: () => setState(() => _pending.remove(f)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _text,
                  enabled: !busy,
                  minLines: 2,
                  maxLines: 8,
                  maxLength: maxPostBody,
                  decoration: InputDecoration(
                    labelText: tr('Answer or note to your teacher (optional)'),
                    alignLabelWithHint: true,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: busy ? null : _attach,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(tr('Add a file')),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: busy ? null : () => _save(turnIn: true),
                    child: Text(
                      widget.post.isPastDue() ? tr('Hand in late') : tr('Hand in'),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : () => _save(turnIn: false),
                  child: Text(tr('Save without handing in')),
                ),
              ] else ...[
                if (mine?.text.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(mine!.text, style: t.bodyMedium),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : _unsubmit,
                  child: Text(tr('Unsubmit to change it')),
                ),
              ],
              if (_busy != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(_busy!),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: NestColor.redPen)),
              ],
              const SizedBox(height: 6),
              Text(
                tr('Files you hand in are saved in your Google Drive and shared '
                'by link with your teacher.'),
                style: t.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------ teacher side

class _TeacherWork extends StatefulWidget {
  const _TeacherWork({required this.classGroup, required this.post});

  final StudyGroup classGroup;
  final ClassPost post;

  @override
  State<_TeacherWork> createState() => _TeacherWorkState();
}

class _TeacherWorkState extends State<_TeacherWork> {
  late final Stream<List<Submission>> _subs = ClassroomService.instance
      .watchSubmissions(widget.classGroup.id, widget.post.id);
  late final Future<List<CloudProfile>> _people =
      ClassroomService.instance.people(widget.classGroup);

  bool _reminding = false;

  Future<void> _remind(int missing) async {
    setState(() => _reminding = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ClassroomService.instance.remindMissing(
        classGroup: widget.classGroup,
        post: widget.post,
        missingCount: missing,
      );
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Reminder posted in the class chat.'))),
      );
    } on CloudException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _reminding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return FutureBuilder<List<CloudProfile>>(
      future: _people,
      builder: (context, peopleSnap) => StreamBuilder<List<Submission>>(
        stream: _subs,
        builder: (context, subSnap) {
          final people = peopleSnap.data;
          final subs = subSnap.data;
          if (people == null || subs == null) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final byUid = {for (final s in subs) s.uid: s};
          final students =
              people.where((p) => p.uid != widget.classGroup.ownerUid).toList();

          final statuses = {
            for (final p in students)
              p.uid: workStatus(widget.post, byUid[p.uid]),
          };
          int count(Set<WorkStatus> which) =>
              statuses.values.where(which.contains).length;
          final handedIn = count(
              {WorkStatus.turnedIn, WorkStatus.late, WorkStatus.returned});
          final graded = count({WorkStatus.returned});
          final notYet = count({WorkStatus.assigned, WorkStatus.missing});

          // What needs the teacher first: work waiting to be graded, then
          // work not in yet, then what is already done.
          int rank(WorkStatus s) => switch (s) {
                WorkStatus.late || WorkStatus.turnedIn => 0,
                WorkStatus.missing => 1,
                WorkStatus.assigned => 2,
                WorkStatus.returned => 3,
              };
          students.sort((a, b) {
            final r = rank(statuses[a.uid]!) - rank(statuses[b.uid]!);
            return r != 0
                ? r
                : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Student work'), style: t.titleMedium),
              const SizedBox(height: 10),
              Row(
                children: [
                  _Count(label: tr('Handed in'), value: handedIn),
                  _Count(label: tr('Graded'), value: graded),
                  _Count(
                    label: widget.post.isPastDue() ? tr('Missing') : tr('Not yet'),
                    value: notYet,
                    warn: widget.post.isPastDue() && notYet > 0,
                  ),
                ],
              ),
              if (notYet > 0) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _reminding ? null : () => _remind(notYet),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(
                    trp('Remind the {0} who have not handed in', [notYet]),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (students.isEmpty)
                Text(
                  tr('No students in this class yet.'),
                  style: t.bodySmall,
                ),
              for (final p in students)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                  leading: InitialsTile(
                    name: p.name.isEmpty ? p.email : p.name,
                    size: 38,
                    photo: ProfilePhoto.decode(p.photo),
                  ),
                  title: Text(p.name.isEmpty ? p.email : p.name),
                  subtitle: byUid[p.uid]?.grade != null
                      ? Text(trp('Grade {0}{1}', [byUid[p.uid]!.grade, widget.post.points == null ? '' : ' / ${widget.post.points}']))
                      : null,
                  trailing: StatusPill(status: statuses[p.uid]!),
                  onTap: byUid[p.uid] == null || !byUid[p.uid]!.isTurnedIn
                      ? null
                      : () => _review(context, p, byUid[p.uid]!),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _review(
    BuildContext context,
    CloudProfile student,
    Submission work,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReviewSheet(
        classGroup: widget.classGroup,
        post: widget.post,
        student: student,
        work: work,
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, this.warn = false});

  final String label;
  final int value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: warn ? NestColor.tintRed : NestColor.paper,
          borderRadius: BorderRadius.circular(NestRadius.chip),
        ),
        child: Column(
          children: [
            Text(
              trp('{0}', [value]),
              style: TextStyle(
                fontFamily: NestFont.display,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: warn ? NestColor.redDeep : NestColor.ink,
              ),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({
    required this.classGroup,
    required this.post,
    required this.student,
    required this.work,
  });

  final StudyGroup classGroup;
  final ClassPost post;
  final CloudProfile student;
  final Submission work;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late final _grade = TextEditingController(
    text: widget.work.grade?.toString() ?? '',
  );
  late final _feedback = TextEditingController(text: widget.work.feedback);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _grade.dispose();
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _return() async {
    final raw = _grade.text.trim();
    final grade = raw.isEmpty ? null : int.tryParse(raw);
    if (raw.isNotEmpty && grade == null) {
      setState(() => _error = tr('The grade must be a whole number.'));
      return;
    }
    final max = widget.post.points ?? maxPoints;
    if (grade != null && (grade < 0 || grade > max)) {
      setState(() => _error = trp('The grade must be between 0 and {0}.', [max]));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await ClassroomService.instance.returnWork(
        classId: widget.classGroup.id,
        postId: widget.post.id,
        studentUid: widget.student.uid,
        grade: grade,
        feedback: _feedback.text,
      );
      navigator.pop();
    } on CloudException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final w = widget.work;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.student.name, style: t.headlineSmall),
            if (w.submittedAt != null)
              Text(
                trp('Handed in {0}{1}', [formatDue(w.submittedAt!), w.isLateFor(widget.post) ? tr(' — late') : '']),
                style: t.bodySmall,
              ),
            const SizedBox(height: 14),
            if (w.text.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NestColor.paper,
                  borderRadius: BorderRadius.circular(NestRadius.chip),
                ),
                child: SelectableText(w.text),
              ),
              const SizedBox(height: 10),
            ],
            for (final f in w.files) ClassFileTile(file: f),
            if (w.files.isEmpty && w.text.isEmpty)
              Text(tr('Marked as done with nothing attached.'), style: t.bodySmall),
            const SizedBox(height: 14),
            TextField(
              controller: _grade,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('Grade'),
                suffixText: widget.post.points == null
                    ? null
                    : '/ ${widget.post.points}',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _feedback,
              minLines: 2,
              maxLines: 6,
              maxLength: maxFeedback,
              decoration: InputDecoration(
                labelText: tr('Private feedback (only this student sees it)'),
                alignLabelWithHint: true,
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: NestColor.redPen)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _busy ? null : _return,
                child: Text(w.state == SubmissionState.returned
                    ? tr('Update and return')
                    : tr('Return to student')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
