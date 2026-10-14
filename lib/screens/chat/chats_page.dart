import 'package:flutter/material.dart';

import '../../data/cloud_service.dart';
import '../../models/chat.dart';
import '../../models/cloud_profile.dart';
import '../../models/study_group.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_empty_state.dart';
import '../cloud/cloud_page.dart';
import '../groups/groups_page.dart';
import 'chat_page.dart';

/// Every conversation, in two sections.
///
/// Groups first, then people. Not one list sorted by time, and that is a
/// deliberate trade: a group's last message lives in its own document, so
/// merging the two into one time-ordered list would mean waiting on every
/// group's document before the screen could draw anything. Two sections draw
/// immediately and read just as well.
class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key, this.embedded = false});

  /// Drawn inside the People tab rather than pushed as a screen of its own.
  /// Embedded it gives up its Scaffold — the tab already has one — and its
  /// floating button, because a FAB and the floating nav bar want the same
  /// corner and the FAB wins by sitting on top of a destination.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    final body = _body(context, cloud);
    if (embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      floatingActionButton: ListenableBuilder(
        listenable: cloud,
        builder: (context, _) => cloud.isSignedIn
            ? FloatingActionButton.extended(
                onPressed: () => showFindPersonSheet(context),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                label: const Text('Message someone'),
              )
            : const SizedBox.shrink(),
      ),
      body: body,
    );
  }

  Widget _body(BuildContext context, CloudService cloud) {
    return ListenableBuilder(
        listenable: cloud,
        builder: (context, _) {
          if (!cloud.isSignedIn) {
            return Padding(
              padding: const EdgeInsets.all(22),
              child: NestEmptyState(
                icon: Icons.cloud_queue_rounded,
                title: 'Connect a cloud account first',
                message: 'A conversation lives somewhere both phones can see, '
                    'so it needs an account. Everything already on this device '
                    'keeps working either way.',
                actionLabel: 'Cloud account',
                onAction: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CloudPage()),
                ),
              ),
            );
          }
          return const _Threads();
        },
    );
  }
}

class _Threads extends StatefulWidget {
  const _Threads();

  @override
  State<_Threads> createState() => _ThreadsState();
}

class _ThreadsState extends State<_Threads> {
  late final Stream<List<StudyGroup>> _groups =
      CloudService.instance.watchGroups();
  late final Stream<List<ChatThread>> _direct =
      CloudService.instance.watchDirectChats();

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    // Its own listener: this widget is built `const` by the page, so the
    // page's rebuild does not reach it, and a block made in a conversation
    // must still take that conversation off this list.
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) => _lists(context, cloud),
    );
  }

  Widget _lists(BuildContext context, CloudService cloud) {
    return StreamBuilder<List<StudyGroup>>(
      stream: _groups,
      builder: (context, groupSnap) {
        return StreamBuilder<List<ChatThread>>(
          stream: _direct,
          builder: (context, directSnap) {
            final groups = groupSnap.data ?? const <StudyGroup>[];
            final me = cloud.uid ?? '';
            final direct = (directSnap.data ?? const <ChatThread>[])
                .where((t) => !cloud.isBlocked(t.otherMember(me)))
                .toList();

            if (!groupSnap.hasData && !directSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (groups.isEmpty && direct.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(22),
                child: NestEmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No conversations yet',
                  message: 'Every group has a conversation of its own. Make a '
                      'group or join one, and talking starts there — or '
                      'message one person by their email address.',
                  actionLabel: 'Groups',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const GroupsPage()),
                  ),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 40),
              children: [
                if (groups.isNotEmpty) ...[
                  const Text('GROUPS', style: nestEyebrow),
                  const SizedBox(height: 8),
                  for (final g in groups) _GroupRow(group: g),
                  const SizedBox(height: 22),
                ],
                if (direct.isNotEmpty) ...[
                  const Text('PEOPLE', style: nestEyebrow),
                  const SizedBox(height: 8),
                  for (final t in direct) _DirectRow(thread: t),
                ] else if (groups.isNotEmpty) ...[
                  const Text('PEOPLE', style: nestEyebrow),
                  const SizedBox(height: 8),
                  Text(
                    'Open a group, tap somebody in its member list, and you '
                    'can talk to them on their own.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group});

  final StudyGroup group;

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    final chatId = groupChatId(group.id);

    return StreamBuilder<ChatThread?>(
      stream: cloud.watchChat(chatId),
      builder: (context, snap) {
        final thread = snap.data;
        return _Row(
          initials: group.initials,
          colour: group.isClass ? NestColor.mint : NestColor.pen,
          title: group.name,
          // Before anybody has spoken there is no last message, so the row
          // says what the group is instead of sitting there blank.
          subtitle: thread?.lastText.isNotEmpty == true
              ? '${thread!.lastFromName}: ${thread.lastText}'
              : '${group.memberLabel} · no messages yet',
          when: thread?.lastAt,
          unread: thread?.isUnreadFor(cloud.uid) ?? false,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatPage(
                chatId: chatId,
                title: group.name,
                groupId: group.id,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DirectRow extends StatelessWidget {
  const _DirectRow({required this.thread});

  final ChatThread thread;

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    final me = cloud.uid ?? '';
    final otherUid = thread.otherMember(me);

    return FutureBuilder<CloudProfile?>(
      future: cloud.profileFor(otherUid),
      builder: (context, snap) {
        final person = snap.data;
        // The name is read from the profile every time rather than stored on
        // the thread, so somebody who changes their name does not keep showing
        // up here under the old one.
        final name = person?.name.trim().isNotEmpty == true
            ? person!.name
            : (person?.email ?? 'Someone');

        return _Row(
          initials: person?.initials ?? '?',
          colour: NestColor.pen,
          title: name,
          subtitle: thread.lastText.isEmpty
              ? 'No messages yet'
              : (thread.lastFromUid == me
                  ? 'You: ${thread.lastText}'
                  : thread.lastText),
          when: thread.lastAt,
          unread: thread.isUnreadFor(me),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatPage(chatId: thread.id, title: name),
            ),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.initials,
    required this.colour,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.when,
    this.unread = false,
  });

  final String initials;
  final Color colour;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final DateTime? when;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.tile),
        // A row has to sit above the page, not be a white patch on it. Drawn
        // through Material rather than a Container so the ink splash still
        // clips to the rounded corners; surfaceTintColor off because Material
        // 3 otherwise tints an elevated surface toward the primary colour and
        // the card stops being white.
        elevation: 3,
        shadowColor: NestColor.o(NestColor.ink, 0.42),
        surfaceTintColor: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(NestRadius.tile),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: NestColor.o(colour, 0.26),
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                  ),
                  child: Text(
                    initials,
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
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: unread
                                      ? NestColor.ink
                                      : NestColor.inkSoft,
                                ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (when != null)
                      Text(whenLabel(when!), style: nestEyebrow),
                    const SizedBox(height: 6),
                    if (unread)
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: NestColor.pen,
                          shape: BoxShape.circle,
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


// ------------------------------------------------------- message someone

/// Starts a conversation with somebody by their exact email address.
///
/// The same lookup that sending a note uses, and the same limit on it: an
/// exact match, never a prefix. NoteNest does not list everybody who has an
/// account, so there is nobody to browse and nobody to find by accident.
///
/// This is the way to reach somebody you share no group with — the person who
/// sent you a note out of the blue, most often. The protection is that they
/// must already know your address, which is exactly the protection that
/// sending you a note has.
Future<void> showFindPersonSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _FindPersonSheet(),
  );
}

class _FindPersonSheet extends StatefulWidget {
  const _FindPersonSheet();

  @override
  State<_FindPersonSheet> createState() => _FindPersonSheetState();
}

class _FindPersonSheetState extends State<_FindPersonSheet> {
  final _email = TextEditingController();
  CloudProfile? _found;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _look() async {
    setState(() {
      _busy = true;
      _error = null;
      _found = null;
    });
    try {
      final person = await CloudService.instance.findByEmail(_email.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _found = person;
        _error = person == null
            ? 'Nobody with that address has a NoteNest cloud account yet.'
            : null;
      });
    } on CloudException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _open(CloudProfile person) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final chatId = await CloudService.instance.openDirectChat(person.uid);
      if (!mounted) return;
      navigator.pop();
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            chatId: chatId,
            title: person.name.trim().isEmpty ? person.email : person.name,
          ),
        ),
      );
    } on CloudException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;

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
              Text(
                'Message someone',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'For somebody you are not in a group with. Anybody in a group '
                'with you can be reached from its member list instead.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _email,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Their email',
                        hintText: 'classmate@example.com',
                      ),
                      onSubmitted: (_) => _look(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _look,
                      child: const Text('Find'),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: NestColor.o(NestColor.redPen, 0.08),
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                    border: const Border(
                      left: BorderSide(color: NestColor.redPen, width: 3),
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              if (found != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _open(found),
                    icon: const Icon(Icons.forum_outlined, size: 18),
                    label: Text(
                      'Message ${found.name.trim().isEmpty ? found.email : found.name}',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
