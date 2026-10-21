import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/classroom_service.dart';
import '../../data/cloud_service.dart';
import '../../data/profile_photo.dart';
import '../../models/chat.dart';
import '../../models/classwork.dart';
import '../../models/cloud_profile.dart';
import '../../models/study_group.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_empty_state.dart';
import '../../widgets/nest_mark_tile.dart';
import '../chat/chat_page.dart';
import '../groups/group_detail.dart';
import 'post_composer.dart';
import 'post_detail.dart';
import '../../l10n/strings.dart';

/// One class: what was posted, the work set, and who is in it.
///
/// Three tabs, the shape anybody who has used Google Classroom will expect —
/// Stream, Classwork, People — with the class chat one tap away in the app
/// bar rather than buried as a comment box under every post.
class ClassroomPage extends StatefulWidget {
  const ClassroomPage({super.key, required this.classId});

  final String classId;

  @override
  State<ClassroomPage> createState() => _ClassroomPageState();
}

class _ClassroomPageState extends State<ClassroomPage> {
  late final Stream<StudyGroup?> _group =
      CloudService.instance.watchGroup(widget.classId);
  late final Stream<List<ClassPost>> _posts =
      ClassroomService.instance.watchPosts(widget.classId);

  @override
  Widget build(BuildContext context) {
    final me = CloudService.instance.uid;

    return StreamBuilder<StudyGroup?>(
      stream: _group,
      builder: (context, groupSnap) {
        final group = groupSnap.data;
        if (group == null) {
          return Scaffold(
            appBar: AppBar(title: Text(tr('Class'))),
            body: Center(
              child: groupSnap.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(30),
                      child: Text(
                        tr('This class is no longer there, or you are not in it '
                        'any more.'),
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
          );
        }
        final teaching = group.isOwner(me);

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(group.name, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  tooltip: tr('Class chat'),
                  icon: const Icon(Icons.forum_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        chatId: groupChatId(group.id),
                        title: group.name,
                        groupId: group.id,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: teaching ? tr('Class settings') : tr('About this class'),
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupDetailPage(groupId: group.id),
                    ),
                  ),
                ),
              ],
              bottom: TabBar(
                labelStyle: const TextStyle(
                  fontFamily: NestFont.display,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                tabs: [
                  Tab(text: tr('Stream')),
                  Tab(text: tr('Classwork')),
                  Tab(text: tr('People')),
                ],
              ),
            ),
            floatingActionButton: teaching
                ? FloatingActionButton.extended(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PostComposerPage(classGroup: group),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(tr('Post')),
                  )
                : null,
            body: StreamBuilder<List<ClassPost>>(
              stream: _posts,
              builder: (context, postSnap) {
                if (postSnap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(22),
                    child: NestEmptyState(
                      icon: Icons.error_outline_rounded,
                      title: tr('Could not load the class'),
                      message: trp('{0}', [postSnap.error]),
                    ),
                  );
                }
                final posts = postSnap.data;
                if (posts == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return TabBarView(
                  children: [
                    _StreamTab(group: group, posts: posts, teaching: teaching),
                    _ClassworkTab(
                        group: group, posts: posts, teaching: teaching),
                    _PeopleTab(group: group, teaching: teaching),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ stream

class _StreamTab extends StatelessWidget {
  const _StreamTab({
    required this.group,
    required this.posts,
    required this.teaching,
  });

  final StudyGroup group;
  final List<ClassPost> posts;
  final bool teaching;

  @override
  Widget build(BuildContext context) {
    final upcoming = posts
        .where((p) => p.isAssignment && p.dueAt != null && !p.isPastDue())
        .toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 100),
      children: [
        _Banner(group: group, teaching: teaching),
        const SizedBox(height: 14),
        if (upcoming.isNotEmpty) ...[
          _Upcoming(group: group, posts: upcoming.take(3).toList()),
          const SizedBox(height: 14),
        ],
        if (posts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: NestEmptyState(
              icon: Icons.campaign_outlined,
              title: tr('Nothing posted yet'),
              message: teaching
                  ? tr('Tap Post to share an announcement, slides or a PDF, or '
                      'to set an assignment with a deadline.')
                  : tr('Announcements, materials and assignments from your '
                      'teacher will show up here.'),
            ),
          )
        else
          for (final p in posts) _PostCard(group: group, post: p),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.group, required this.teaching});

  final StudyGroup group;
  final bool teaching;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [NestColor.pen, NestColor.penDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(NestRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.name,
            style: const TextStyle(
              fontFamily: NestFont.display,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (group.subject.trim().isNotEmpty)
            Text(group.subject,
                style: TextStyle(color: NestColor.penPale)),
          const SizedBox(height: 12),
          if (teaching)
            InkWell(
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: prettyJoinCode(group.joinCode)));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('Class code copied.'))),
                );
              },
              child: Row(
                children: [
                  Text('Class code  ',
                      style: TextStyle(color: NestColor.penPale)),
                  Text(
                    prettyJoinCode(group.joinCode),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: ls(1.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.copy_rounded,
                      size: 16, color: NestColor.penPale),
                ],
              ),
            )
          else
            Text(
              trp('Taught by {0}', [group.ownerName.isEmpty ? tr('your teacher') : group.ownerName]),
              style: const TextStyle(color: Colors.white),
            ),
        ],
      ),
    );
  }
}

class _Upcoming extends StatelessWidget {
  const _Upcoming({required this.group, required this.posts});

  final StudyGroup group;
  final List<ClassPost> posts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: NestColor.tintWarm,
        borderRadius: BorderRadius.circular(NestRadius.tile),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('DUE SOON'), style: nestEyebrow),
          const SizedBox(height: 4),
          for (final p in posts)
            InkWell(
              onTap: () => openPost(context, group, p),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.assignment_outlined,
                        size: 18, color: NestColor.warmDeep),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      formatDue(p.dueAt!),
                      style: TextStyle(
                          color: NestColor.warmDeep, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void openPost(BuildContext context, StudyGroup group, ClassPost post) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PostDetailPage(classGroup: group, postId: post.id),
    ),
  );
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.group, required this.post});

  final StudyGroup group;
  final ClassPost post;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final icon = switch (post.kind) {
      PostKind.announcement => Icons.campaign_rounded,
      PostKind.material => Icons.menu_book_rounded,
      PostKind.assignment => Icons.assignment_rounded,
    };
    final tint = switch (post.kind) {
      PostKind.announcement => NestColor.tintPen,
      PostKind.material => NestColor.tintMint,
      PostKind.assignment => NestColor.tintWarm,
    };
    final ink = switch (post.kind) {
      PostKind.announcement => NestColor.penDeep,
      PostKind.material => NestColor.mintDeep,
      PostKind.assignment => NestColor.warmDeep,
    };

    final headline = post.kind == PostKind.announcement
        ? trp('{0} posted', [post.authorName.isEmpty ? tr('Teacher') : post.authorName])
        : '${post.kind.label}: ${post.title}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.tile),
        elevation: 2,
        shadowColor: NestColor.o(NestColor.ink, 0.3),
        surfaceTintColor: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(NestRadius.tile),
          onTap: () => openPost(context, group, post),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkTile(tint: tint, ink: ink, icon: icon, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(headline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (post.createdAt != null)
                            _shortDate(post.createdAt!),
                          if (post.dueAt != null)
                            'Due ${formatDue(post.dueAt!)}',
                          if (post.files.isNotEmpty)
                            '${num_(post.files.length)} ${tr(post.files.length == 1 ? 'file' : 'files')}',
                        ].join(' · '),
                        style: t.bodySmall,
                      ),
                      if (post.kind == PostKind.announcement &&
                          post.body.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          post.body,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _shortDate(DateTime d) {
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
  return localDate('${d.day} ${months[d.month - 1]}');
}

// --------------------------------------------------------------- classwork

class _ClassworkTab extends StatelessWidget {
  const _ClassworkTab({
    required this.group,
    required this.posts,
    required this.teaching,
  });

  final StudyGroup group;
  final List<ClassPost> posts;
  final bool teaching;

  @override
  Widget build(BuildContext context) {
    final work = posts.where((p) => p.kind != PostKind.announcement).toList();
    if (work.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(22),
        children: [
          NestEmptyState(
            icon: Icons.assignment_outlined,
            title: tr('No classwork yet'),
            message: teaching
                ? tr('Materials and assignments you post are listed here by topic.')
                : tr('Materials and assignments are listed here by topic.'),
          ),
        ],
      );
    }

    // Grouped by topic, the way a syllabus is read. Untitled work goes last
    // rather than first, so the teacher's structure leads.
    final byTopic = <String, List<ClassPost>>{};
    for (final p in work) {
      byTopic.putIfAbsent(p.topic.trim(), () => []).add(p);
    }
    final topics = byTopic.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 100),
      children: [
        for (final topic in topics) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
            child: Text(
              topic.isEmpty ? tr('OTHER') : topic.toUpperCase(),
              style: nestEyebrow.copyWith(color: NestColor.pen, fontSize: 12),
            ),
          ),
          for (final p in byTopic[topic]!)
            _WorkRow(group: group, post: p, teaching: teaching),
        ],
      ],
    );
  }
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({
    required this.group,
    required this.post,
    required this.teaching,
  });

  final StudyGroup group;
  final ClassPost post;
  final bool teaching;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isWork = post.isAssignment;

    Widget status = const SizedBox.shrink();
    if (isWork && !teaching) {
      status = StreamBuilder<Submission?>(
        stream: ClassroomService.instance.watchMySubmission(group.id, post.id),
        builder: (context, snap) =>
            StatusPill(status: workStatus(post, snap.data)),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: NestColor.card,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NestRadius.chip),
      ),
      child: ListTile(
        onTap: () => openPost(context, group, post),
        leading: Icon(
          isWork ? Icons.assignment_rounded : Icons.menu_book_rounded,
          color: isWork ? NestColor.warmDeep : NestColor.mintDeep,
        ),
        title: Text(post.title,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall),
        subtitle: Text(
          post.dueAt != null
              ? trp('Due {0}', [formatDue(post.dueAt!)])
              : isWork
                  ? tr('No due date')
                  : '${post.files.length} ${post.files.length == 1 ? 'file' : 'files'}',
          style: t.bodySmall,
        ),
        trailing: status,
      ),
    );
  }
}

/// A coloured label for where a piece of work stands.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final WorkStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      WorkStatus.assigned => (NestColor.tintPen, NestColor.penDeep),
      WorkStatus.missing => (NestColor.tintRed, NestColor.redDeep),
      WorkStatus.turnedIn => (NestColor.tintMint, NestColor.mintDeep),
      WorkStatus.late => (NestColor.tintWarm, NestColor.warmDeep),
      WorkStatus.returned => (NestColor.tintMint, NestColor.mintDeep),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(NestRadius.pill),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ people

class _PeopleTab extends StatefulWidget {
  const _PeopleTab({required this.group, required this.teaching});

  final StudyGroup group;
  final bool teaching;

  @override
  State<_PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<_PeopleTab> {
  late Future<List<CloudProfile>> _people =
      ClassroomService.instance.people(widget.group);
  late int _count = widget.group.memberCount;

  @override
  void didUpdateWidget(covariant _PeopleTab old) {
    super.didUpdateWidget(old);
    // Somebody joined or left: read the list again.
    if (widget.group.memberCount != _count) {
      _count = widget.group.memberCount;
      _people = ClassroomService.instance.people(widget.group);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CloudProfile>>(
      future: _people,
      builder: (context, snap) {
        final people = snap.data;
        if (people == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final teacher =
            people.where((p) => p.uid == widget.group.ownerUid).toList();
        final students =
            people.where((p) => p.uid != widget.group.ownerUid).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 100),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Text(tr('TEACHER'), style: nestEyebrow),
            ),
            for (final p in teacher) _PersonRow(person: p),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
              child: Text(
                trp('STUDENTS · {0}', [students.length]),
                style: nestEyebrow,
              ),
            ),
            if (students.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  widget.teaching
                      ? trp('Nobody has joined yet. Share the class code {0}.', [prettyJoinCode(widget.group.joinCode)])
                      : tr('Nobody else has joined yet.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            for (final p in students)
              _PersonRow(person: p, showEmail: widget.teaching),
          ],
        );
      },
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, this.showEmail = false});

  final CloudProfile person;

  /// Only the teacher sees students' addresses. Classmates see a name and a
  /// face, which is all a class list needs to show them.
  final bool showEmail;

  @override
  Widget build(BuildContext context) {
    final name = person.name.isEmpty ? tr('Unnamed') : person.name;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: InitialsTile(
        name: name,
        size: 40,
        photo: ProfilePhoto.decode(person.photo),
      ),
      title: Text(name),
      subtitle: showEmail
          ? Text(person.email, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
    );
  }
}
