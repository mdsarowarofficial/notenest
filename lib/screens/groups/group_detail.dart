import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/cloud_service.dart';
import '../../models/cloud_profile.dart';
import '../../models/study_group.dart';
import '../../theme/nest_theme.dart';
import '../chat/message_request.dart';

/// One group: who is in it, the code that lets one more person in, and the way
/// out.
class GroupDetailPage extends StatefulWidget {
  const GroupDetailPage({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  /// One listener for the life of the screen, not one per rebuild.
  late final Stream<StudyGroup?> _group =
      CloudService.instance.watchGroup(widget.groupId);

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;

    return StreamBuilder<StudyGroup?>(
      stream: _group,
      builder: (context, snap) {
        final group = snap.data;

        return Scaffold(
          appBar: AppBar(
            title: Text(group?.name ?? 'Group'),
            actions: [
              if (group != null && group.isOwner(cloud.uid))
                IconButton(
                  tooltip: 'Delete group',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _confirmDelete(context, group),
                ),
            ],
          ),
          body: group == null
              ? Center(
                  child: snap.connectionState == ConnectionState.waiting
                      ? const CircularProgressIndicator()
                      : const Padding(
                          padding: EdgeInsets.all(30),
                          child: Text(
                            'This group is no longer there, or you are not in '
                            'it any more.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                )
              : _Body(group: group),
        );
      },
    );
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    StudyGroup group,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this group?'),
        content: Text(
          'Everyone in ${group.name} loses it, and the code '
          '${prettyJoinCode(group.joinCode)} stops working. Notes already '
          'accepted stay in their notebooks.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (yes != true || !context.mounted) return;
    try {
      await CloudService.instance.deleteGroup(group);
      if (context.mounted) Navigator.of(context).pop();
    } on CloudException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.group});

  final StudyGroup group;

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    final me = cloud.uid;
    final colour = group.isClass ? NestColor.mint : NestColor.pen;

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 40),
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NestColor.o(colour, 0.12),
                borderRadius: BorderRadius.circular(NestRadius.chip),
              ),
              child: Text(
                group.initials,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colour,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    [
                      group.kind.label,
                      if (group.subject.trim().isNotEmpty) group.subject.trim(),
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),
        const Text('GROUP CODE', style: nestEyebrow),
        const SizedBox(height: 8),
        _CodeCard(group: group),

        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'MEMBERS',
                style: nestEyebrow,
              ),
            ),
            Text('${group.memberCount}', style: nestEyebrow),
          ],
        ),
        const SizedBox(height: 8),
        _Members(group: group),

        const SizedBox(height: 28),
        if (group.canLeave(me))
          OutlinedButton.icon(
            onPressed: () => _leave(context, group),
            style: OutlinedButton.styleFrom(foregroundColor: NestColor.redPen),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Leave this group'),
          )
        else if (group.isOwner(me))
          Text(
            'You made this group, so you cannot leave it — a group with no '
            'owner is one nobody can delete. Delete it instead when it is '
            'finished with.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  static Future<void> _leave(BuildContext context, StudyGroup group) async {
    try {
      await CloudService.instance.leaveGroup(group);
      if (context.mounted) Navigator.of(context).pop();
    } on CloudException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.group});

  final StudyGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.card),
        boxShadow: NestShadow.resting,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prettyJoinCode(group.joinCode),
                  style: const TextStyle(
                    fontSize: 28,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w700,
                    color: NestColor.penDeep,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Anyone with this code can join. There is no O or I in a '
                  'code — those are zero and one.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy code',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: group.joinCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copied')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Members extends StatefulWidget {
  const _Members({required this.group});

  final StudyGroup group;

  @override
  State<_Members> createState() => _MembersState();
}

class _MembersState extends State<_Members> {
  late Future<List<CloudProfile>> _people = _load();

  Future<List<CloudProfile>> _load() =>
      CloudService.instance.profilesFor(widget.group.memberUids);

  @override
  void didUpdateWidget(_Members old) {
    super.didUpdateWidget(old);
    // Only when the membership actually changed. Rebuilt on every snapshot —
    // a rename, a tick of `updatedAt` — this would otherwise start a new load
    // and blink the whole list back to a spinner.
    if (!listEquals(old.group.memberUids, widget.group.memberUids)) {
      _people = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    return FutureBuilder<List<CloudProfile>>(
      future: _people,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final people = snap.data!;
        // The owner first, then everyone else by name. A list in uid order is
        // a list in no order at all.
        people.sort((a, b) {
          if (a.uid == group.ownerUid) return -1;
          if (b.uid == group.ownerUid) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

        return Container(
          decoration: BoxDecoration(
            color: NestColor.card,
            borderRadius: BorderRadius.circular(NestRadius.card),
            boxShadow: NestShadow.resting,
          ),
          child: Column(
            children: [
              for (var i = 0; i < people.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: 60, color: NestColor.rule),
                _MemberRow(
                  person: people[i],
                  isOwner: people[i].uid == group.ownerUid,
                  isYou: people[i].uid == CloudService.instance.uid,
                ),
              ],
              if (people.length < group.memberCount)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    // Honest rather than silent: a member whose profile could
                    // not be read is still a member, and pretending the group
                    // is smaller than it is would be worse than saying so.
                    '${group.memberCount - people.length} member(s) could not '
                    'be loaded.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.person,
    required this.isOwner,
    required this.isYou,
  });

  final CloudProfile person;
  final bool isOwner;
  final bool isYou;

  /// Opens a one-to-one conversation with this member.
  ///
  /// This is the whole of NoteNest's "add a friend": being in a group together
  /// is how you find each other. Talking one to one still needs a message
  /// request that the other person accepts, like anybody else.
  static Future<void> _message(BuildContext context, CloudProfile person) =>
      startConversation(context, person);

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NestColor.o(NestColor.pen, 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              person.initials,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: NestColor.pen,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name.trim().isEmpty
                      ? person.email
                      : '${person.name}${isYou ? ' (you)' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  person.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (isOwner)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: NestColor.o(NestColor.mint, 0.12),
                borderRadius: BorderRadius.circular(NestRadius.chip),
              ),
              child: const Text(
                'Owner',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: NestColor.mint,
                ),
              ),
            )
          else if (person.isTeacher)
            Text('Teacher', style: Theme.of(context).textTheme.bodySmall),
          if (!isYou) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 17,
              color: NestColor.inkFaint,
            ),
          ],
        ],
      ),
    );

    // Your own row is not tappable: a conversation with yourself is not a
    // feature, it is a bug waiting to be filed.
    if (isYou) return body;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _message(context, person),
        child: body,
      ),
    );
  }
}
