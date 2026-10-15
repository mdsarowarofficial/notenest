import 'package:flutter/material.dart';

import '../../data/classroom_service.dart';
import '../../data/cloud_service.dart';
import '../../data/note_repository.dart';
import '../../models/study_group.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_empty_state.dart';
import '../cloud/cloud_page.dart';
import '../groups/groups_page.dart' show showJoinGroupSheet;
import 'classroom_page.dart';

/// Every class this account teaches or sits in.
///
/// A teacher's tab and a student's segment of People. The difference is only
/// the button: a teacher makes a class, a student joins one with its code.
class ClassesPage extends StatefulWidget {
  const ClassesPage({super.key, this.embedded = false});

  /// True inside another page, which supplies the bottom padding for the nav
  /// bar and no app bar of its own.
  final bool embedded;

  @override
  State<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends State<ClassesPage> {
  Stream<List<StudyGroup>>? _classes;
  String? _streamFor;

  /// One listener per signed-in account, not one per rebuild.
  Stream<List<StudyGroup>> _watch(String uid) {
    if (_classes == null || _streamFor != uid) {
      _classes = ClassroomService.instance.watchClasses();
      _streamFor = uid;
    }
    return _classes!;
  }

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    final teacher = NoteRepository.instance.isTeacher;

    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) {
        final uid = cloud.uid;
        if (!cloud.isSignedIn || uid == null) {
          return const _NeedsCloud();
        }
        return StreamBuilder<List<StudyGroup>>(
          stream: _watch(uid),
          builder: (context, snap) {
            final classes = snap.data ?? const <StudyGroup>[];
            final waiting = snap.connectionState == ConnectionState.waiting &&
                !snap.hasData;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 130),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        teacher ? 'Your classes' : 'Classes',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (teacher)
                      FilledButton.icon(
                        onPressed: () => showCreateClassSheet(context),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New class'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: () => showJoinGroupSheet(context),
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: const Text('Join a class'),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (snap.hasError)
                  NestEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load your classes',
                    message: '${snap.error}',
                  )
                else if (waiting)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (classes.isEmpty)
                  NestEmptyState(
                    icon: Icons.co_present_rounded,
                    title: teacher ? 'No classes yet' : 'Not in a class yet',
                    message: teacher
                        ? 'Make a class, then give your students its six-letter '
                            'code. You can post slides and PDFs, set '
                            'assignments with a deadline, and grade what comes '
                            'back.'
                        : 'Ask your teacher for the class code and join. '
                            'Slides, PDFs and assignments appear here, and you '
                            'hand your work in from the same place.',
                    actionLabel: teacher ? 'New class' : 'Join a class',
                    onAction: teacher
                        ? () => showCreateClassSheet(context)
                        : () => showJoinGroupSheet(context),
                  )
                else
                  for (final c in classes) _ClassCard(group: c, me: uid),
              ],
            );
          },
        );
      },
    );
  }
}

/// Opens a group the right way: a class as a classroom, anything else as a
/// group.
void openClass(BuildContext context, StudyGroup group) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ClassroomPage(classId: group.id)),
  );
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.group, required this.me});

  final StudyGroup group;
  final String me;

  /// A colour per class, picked from the name so it stays the same on every
  /// phone without being stored anywhere.
  static const _bands = [
    Color(0xFF4A5BD4),
    Color(0xFF17A47A),
    Color(0xFFD9822B),
    Color(0xFFB0458F),
    Color(0xFF2E86AB),
    Color(0xFF6D5BD0),
  ];

  @override
  Widget build(BuildContext context) {
    final colour = _bands[group.name.hashCode.abs() % _bands.length];
    final teaching = group.isOwner(me);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colour,
        borderRadius: BorderRadius.circular(NestRadius.tile),
        child: InkWell(
          borderRadius: BorderRadius.circular(NestRadius.tile),
          onTap: () => openClass(context, group),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: NestFont.display,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Colors.white70),
                  ],
                ),
                if (group.subject.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    group.subject,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      teaching
                          ? Icons.school_rounded
                          : Icons.person_outline_rounded,
                      size: 16,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        teaching
                            ? 'You teach · ${group.memberCount - 1} '
                                '${group.memberCount - 1 == 1 ? 'student' : 'students'}'
                            : group.ownerName.isEmpty
                                ? group.memberLabel
                                : group.ownerName,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    if (teaching)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(NestRadius.pill),
                        ),
                        child: Text(
                          prettyJoinCode(group.joinCode),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NeedsCloud extends StatelessWidget {
  const _NeedsCloud();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 130),
      children: [
        NestEmptyState(
          icon: Icons.cloud_queue_rounded,
          title: 'Connect a cloud account first',
          message: 'A class lives somewhere the teacher\'s phone and every '
              'student\'s phone can see, so it needs an account. Your notes '
              'on this phone keep working either way.',
          actionLabel: 'Cloud account',
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CloudPage()),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- new class

Future<void> showCreateClassSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CreateClassSheet(),
  );
}

class _CreateClassSheet extends StatefulWidget {
  const _CreateClassSheet();

  @override
  State<_CreateClassSheet> createState() => _CreateClassSheetState();
}

class _CreateClassSheetState extends State<_CreateClassSheet> {
  final _name = TextEditingController();
  late final _course =
      TextEditingController(text: NoteRepository.instance.teachingCourse ?? '');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _course.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final problem = groupNameProblem(_name.text);
    if (problem != null) {
      setState(() => _error = problem.replaceAll('group', 'class'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      final group = await CloudService.instance.createGroup(
        name: _name.text,
        kind: GroupKind.classroom,
        subject: _course.text,
      );
      if (!mounted) return;
      navigator.pop();
      navigator.push(
        MaterialPageRoute(builder: (_) => ClassroomPage(classId: group.id)),
      );
    } on CloudException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        20,
        22,
        22 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New class', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: maxGroupName,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Class name',
              hintText: 'Data Structures — Section B',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _course,
            maxLength: maxGroupSubject,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Course code (optional)',
              hintText: 'CSE 211',
              counterText: '',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: NestColor.redPen)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _busy ? null : _create,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Make the class'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Students join with the class code shown on the next screen.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
