import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/cloud_service.dart';
import '../../models/study_group.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_empty_state.dart';
import '../cloud/cloud_page.dart';
import 'group_detail.dart';

/// Study groups and classes: the list, making one, and joining one.
///
/// A group is the thing chat and assignments will hang off, so this screen is
/// deliberately plain. Its whole job is to make membership obvious: which
/// groups you are in, who else is in them, and the code that lets one more
/// person in.
class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  /// Built once per signed-in account rather than in `build`.
  ///
  /// A stream created inside build is a new Firestore listener on every
  /// rebuild — the old one torn down, the new one starting empty — which shows
  /// up as the list blinking back to a spinner whenever anything else changes.
  Stream<List<StudyGroup>>? _groups;
  String? _forUid;

  Stream<List<StudyGroup>> _stream() {
    final cloud = CloudService.instance;
    if (_groups == null || _forUid != cloud.uid) {
      _forUid = cloud.uid;
      _groups = cloud.watchGroups();
    }
    return _groups!;
  }

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      body: ListenableBuilder(
        listenable: cloud,
        builder: (context, _) {
          if (!cloud.isSignedIn) return const _NeedsAccount();

          return StreamBuilder<List<StudyGroup>>(
            stream: _stream(),
            builder: (context, snap) {
              if (snap.hasError) {
                return _Problem(message: '${snap.error}');
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final groups = snap.data!;
              if (groups.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(22),
                  child: NestEmptyState(
                    icon: Icons.groups_2_outlined,
                    title: 'No groups yet',
                    message: 'A group is where a few people keep one subject '
                        'together. Make one and share the code, or type a code '
                        'somebody gave you.',
                    actionLabel: 'Make a group',
                    onAction: () => showCreateGroupSheet(context),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 110),
                children: [
                  for (final g in groups) _GroupTile(group: g),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: ListenableBuilder(
        listenable: cloud,
        builder: (context, _) {
          if (!cloud.isSignedIn) return const SizedBox.shrink();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.extended(
                heroTag: 'join',
                onPressed: () => showJoinGroupSheet(context),
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Join'),
                backgroundColor: NestColor.card,
                foregroundColor: NestColor.pen,
                elevation: 1,
              ),
              const SizedBox(width: 12),
              FloatingActionButton.extended(
                heroTag: 'make',
                onPressed: () => showCreateGroupSheet(context),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Make one'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group});

  final StudyGroup group;

  @override
  Widget build(BuildContext context) {
    final colour = group.isClass ? NestColor.mint : NestColor.pen;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.tile),
        child: InkWell(
          borderRadius: BorderRadius.circular(NestRadius.tile),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GroupDetailPage(groupId: group.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: NestColor.o(colour, 0.12),
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                  ),
                  child: Text(
                    group.initials,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colour,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          group.kind.label,
                          if (group.subject.trim().isNotEmpty)
                            group.subject.trim(),
                          group.memberLabel,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: NestColor.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NeedsAccount extends StatelessWidget {
  const _NeedsAccount();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: NestEmptyState(
        icon: Icons.cloud_queue_rounded,
        title: 'Connect a cloud account first',
        message: 'A group lives somewhere both phones can see, so it needs an '
            'account. Everything already on this device keeps working either '
            'way.',
        actionLabel: 'Cloud account',
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CloudPage()),
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: NestEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Could not load your groups',
        message: message,
      ),
    );
  }
}

// ------------------------------------------------------------ make a group

Future<void> showCreateGroupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CreateGroupSheet(),
  );
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet();

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _name = TextEditingController();
  final _subject = TextEditingController();
  GroupKind _kind = GroupKind.study;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _subject.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final problem = groupNameProblem(_name.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    // Taken before the sheet closes. `Navigator.of(context)` after a pop
    // reads a context that is no longer in the tree, which throws — and it
    // throws on the happy path, where it is least expected.
    final navigator = Navigator.of(context);

    try {
      final group = await CloudService.instance.createGroup(
        name: _name.text,
        kind: _kind,
        subject: _subject.text,
      );
      if (!mounted) return;
      navigator.pop();
      navigator.push(
        MaterialPageRoute(builder: (_) => GroupDetailPage(groupId: group.id)),
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
    final teacher = CloudService.instance.profile?.isTeacher ?? false;

    return _Sheet(
      title: 'Make a group',
      error: _error,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: maxGroupName,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Thesis group, CSE 112 Section B',
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _subject,
          maxLength: maxGroupSubject,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Subject (optional)',
            hintText: 'CSE 112',
            counterText: '',
          ),
        ),
        const SizedBox(height: 18),
        const Text('WHAT KIND', style: nestEyebrow),
        const SizedBox(height: 8),
        SegmentedButton<GroupKind>(
          segments: [
            const ButtonSegment(
              value: GroupKind.study,
              label: Text('Study group'),
            ),
            ButtonSegment(
              value: GroupKind.classroom,
              label: const Text('Class'),
              enabled: teacher,
            ),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 8),
        Text(
          teacher
              ? _kind.blurb
              // Said plainly rather than hidden: a disabled control with no
              // explanation is a dead end, and the fix is one tap away.
              : 'Only a teacher account can make a class. You can change your '
                  'account to Teacher on the Cloud account screen.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _busy ? null : _create,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Make the group'),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ join a group

Future<void> showJoinGroupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _JoinGroupSheet(),
  );
}

class _JoinGroupSheet extends StatefulWidget {
  const _JoinGroupSheet();

  @override
  State<_JoinGroupSheet> createState() => _JoinGroupSheetState();
}

class _JoinGroupSheetState extends State<_JoinGroupSheet> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final problem = joinCodeProblem(_code.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final group = await CloudService.instance.joinByCode(_code.text);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Joined ${group.name}')),
      );
      navigator.push(
        MaterialPageRoute(builder: (_) => GroupDetailPage(groupId: group.id)),
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
    return _Sheet(
      title: 'Join a group',
      error: _error,
      children: [
        TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(
            fontSize: 26,
            letterSpacing: 6,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            hintText: 'K3M 9FP',
          ),
          // Not restricted to the code alphabet as you type: people paste
          // codes with dashes and spaces, and the normaliser throws those away
          // anyway. Blocking the keystroke would only make a correct paste look
          // like it failed.
          inputFormatters: [LengthLimitingTextInputFormatter(16)],
        ),
        const SizedBox(height: 14),
        Text(
          'Ask whoever made the group for its code. It is six characters, and '
          'spaces or dashes do not matter.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _busy ? null : _join,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Join'),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------- sheet chrome

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.title,
    required this.children,
    this.error,
  });

  final String title;
  final List<Widget> children;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: NestColor.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: NestColor.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 18),
              if (error != null) ...[
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: NestColor.o(NestColor.redPen, 0.08),
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                    border:
                        Border.all(color: NestColor.o(NestColor.redPen, 0.3)),
                  ),
                  child: Text(
                    error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: NestColor.redPen),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
