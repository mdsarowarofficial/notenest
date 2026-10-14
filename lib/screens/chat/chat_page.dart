import 'package:flutter/material.dart';

import '../../data/cloud_service.dart';
import '../../data/note_repository.dart';
import '../../models/chat.dart';
import '../../models/cloud_profile.dart';
import '../../models/note.dart';
import '../../models/note_bundle.dart';
import '../../models/note_share.dart';
import '../../theme/nest_theme.dart';

/// One conversation — a group's or one person's.
///
/// The same screen for both, because a message is a message. What differs is
/// only who is allowed in, and that is settled in the security rules rather
/// than here.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.chatId,
    required this.title,
    this.groupId = '',
  });

  final String chatId;
  final String title;

  /// Set for a group thread. Carried so the first message can record which
  /// group the conversation belongs to — the thread document may not exist
  /// until somebody speaks.
  final String groupId;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _cloud = CloudService.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  late final Stream<List<ChatMessage>> _messages =
      _cloud.watchMessages(widget.chatId);
  late final Stream<ChatThread?> _thread = _cloud.watchChat(widget.chatId);

  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Opening the conversation is what marks it read. Done once here and again
    // whenever a message lands while the screen is open.
    _cloud.markRead(widget.chatId);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final problem = messageProblem(_input.text);
    if (problem != null) return;

    final text = _input.text.trim();
    // Cleared before the write, not after. A message that sits in the box
    // while the network thinks about it gets sent twice by anybody impatient.
    _input.clear();
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await _cloud.sendMessage(
        chatId: widget.chatId,
        kind: MessageKind.text,
        text: text,
        groupId: widget.groupId,
      );
      if (!mounted) return;
      setState(() => _sending = false);
    } on CloudException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
        // Handed back rather than lost. Losing what somebody typed because
        // the network blinked is not an acceptable way to report a failure.
        _input.text = text;
      });
    }
  }

  Future<void> _postNote() async {
    final note = await showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NotePicker(),
    );
    if (note == null || !mounted) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final repo = NoteRepository.instance;
      final bundle = await repo.packForSharing(note);
      final full = bundle.encode();
      // Files travel when they fit and are left behind when they do not — the
      // same budget as a direct share, and said plainly below rather than
      // failing at the server.
      final fits = full.length <= sharePayloadBudget;
      final payload = fits
          ? full
          : (await repo.packForSharing(note, includeFiles: false)).encode();

      await _cloud.sendMessage(
        chatId: widget.chatId,
        kind: MessageKind.note,
        title: note.title,
        subjectCode: note.subjectId == null
            ? ''
            : (repo.subjectById(note.subjectId!)?.code ?? ''),
        fileCount: fits ? bundle.files.length : 0,
        payload: payload,
        groupId: widget.groupId,
      );

      if (!mounted) return;
      setState(() => _sending = false);
      if (!fits && bundle.files.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Posted without its ${bundle.files.length} '
              '${bundle.files.length == 1 ? 'file' : 'files'} — too big to '
              'post. Send it as a file to include them.',
            ),
          ),
        );
      }
    } on CloudException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            StreamBuilder<ChatThread?>(
              stream: _thread,
              builder: (context, snap) => _TypingLine(thread: snap.data),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messages,
              builder: (context, snap) {
                if (snap.hasError) {
                  return _Centered(
                    icon: Icons.lock_outline_rounded,
                    text: 'This conversation could not be opened.\n\n'
                        '${snap.error}',
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snap.data!;
                if (messages.isEmpty) {
                  return const _Centered(
                    icon: Icons.chat_bubble_outline_rounded,
                    text: 'Nothing here yet.\n'
                        'Say something, or post a note from your notebook.',
                  );
                }

                // Marked read on every batch that arrives while the screen is
                // open, not only when it is first opened.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _cloud.markRead(widget.chatId);
                });

                return ListView.builder(
                  controller: _scroll,
                  // The query is newest-first and the list is reversed, so the
                  // newest message sits at the bottom with no scrolling to
                  // arrange and nothing to jump when one arrives.
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _Bubble(
                    message: messages[i],
                    chatId: widget.chatId,
                    mine: messages[i].fromUid == _cloud.uid,
                    // The name is worth showing only when the one above it is
                    // somebody else's.
                    showName: widget.groupId.isNotEmpty &&
                        messages[i].fromUid != _cloud.uid &&
                        (i == messages.length - 1 ||
                            messages[i + 1].fromUid != messages[i].fromUid),
                  ),
                );
              },
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: NestColor.o(NestColor.redPen, 0.08),
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: NestColor.redPen),
              ),
            ),
          _Composer(
            controller: _input,
            sending: _sending,
            onChanged: (_) => _cloud.setTyping(widget.chatId),
            onSend: _send,
            onPostNote: _postNote,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ parts

class _TypingLine extends StatelessWidget {
  const _TypingLine({required this.thread});

  final ChatThread? thread;

  @override
  Widget build(BuildContext context) {
    final t = thread;
    if (t == null) return const SizedBox.shrink();

    final uids = t.typingNow(CloudService.instance.uid);
    if (uids.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<CloudProfile>>(
      future: CloudService.instance.profilesFor(uids),
      builder: (context, snap) {
        final names = (snap.data ?? const <CloudProfile>[])
            .map((p) => p.name.trim().isEmpty ? 'Someone' : p.name.trim())
            .toList();
        final label = typingLabel(names);
        if (label == null) return const SizedBox.shrink();
        return Text(
          label,
          style: const TextStyle(fontSize: 12, color: NestColor.mint),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.chatId,
    required this.mine,
    required this.showName,
  });

  final ChatMessage message;
  final String chatId;
  final bool mine;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final at = message.createdAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showName)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 3),
              child: Text(message.fromLabel, style: nestEyebrow),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: message.isNote
                ? _NoteCard(message: message, chatId: chatId)
                : Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    decoration: BoxDecoration(
                      color: mine ? NestColor.pen : NestColor.card,
                      borderRadius: BorderRadius.circular(NestRadius.tile),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.text,
                          style: TextStyle(
                            color: mine ? Colors.white : NestColor.ink,
                            height: 1.35,
                          ),
                        ),
                        if (at != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            clockLabel(at),
                            style: TextStyle(
                              fontSize: 10,
                              color: mine
                                  ? NestColor.o(Colors.white, 0.7)
                                  : NestColor.inkFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A note posted into the conversation.
///
/// It is visible to everybody immediately — there is nothing to accept,
/// because being in the conversation is the permission. What needs a tap is
/// putting it in *your* notebook, which is a different thing: that creates a
/// subject, writes a note and keeps files on your device. Seeing is free;
/// keeping is a choice.
class _NoteCard extends StatefulWidget {
  const _NoteCard({required this.message, required this.chatId});

  final ChatMessage message;
  final String chatId;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool _busy = false;

  /// Whether this note is already in the notebook.
  ///
  /// Read off the notes themselves rather than remembered in this screen, so
  /// it still knows after the app is closed and opened again — and so the
  /// button cannot offer to add a second copy of something already there.
  bool get _saved => NoteRepository.instance.inboxNotes().any(
        (n) =>
            n.title == widget.message.title &&
            n.sharedBy == widget.message.fromName,
      );

  Future<void> _save() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final payload =
          await CloudService.instance.loadBlob(widget.chatId, widget.message.blobId);
      if (payload == null) {
        throw const CloudException('That note is no longer here.');
      }
      // The same decoder that reads a `.notenest` file off disk, with the same
      // refusals, and the same importer that puts it under the right subject.
      final bundle = NoteBundle.decode(payload);
      await NoteRepository.instance.importBundle(bundle);
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Saved "${bundle.title}" to your notes')),
      );
    } on BundleException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('That note could not be read: ${e.message}')),
      );
    } on CloudException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;

    return ListenableBuilder(
      listenable: NoteRepository.instance,
      // `_saved` is read inside the builder, not outside it. Read outside, the
      // button would still say "Save" after the note had been saved, until
      // something else happened to rebuild the page.
      builder: (context, _) {
        final saved = _saved;
        return Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: NestColor.card,
          borderRadius: BorderRadius.circular(NestRadius.tile),
          border: Border.all(color: NestColor.o(NestColor.pen, 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.description_outlined,
                  size: 20,
                  color: NestColor.pen,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.title.trim().isEmpty ? 'A note' : m.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        [
                          if (m.subjectCode.trim().isNotEmpty) m.subjectCode,
                          if (m.fileCount > 0)
                            '${m.fileCount} '
                                '${m.fileCount == 1 ? 'file' : 'files'}',
                          if (m.createdAt != null) clockLabel(m.createdAt!),
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: saved
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('In your notes'),
                    )
                  : FilledButton.icon(
                      onPressed: _busy || !m.hasBlob ? null : _save,
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text(_busy ? 'Saving…' : 'Save to my notes'),
                    ),
            ),
          ],
        ),
        );
      },
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onChanged,
    required this.onSend,
    required this.onPostNote,
  });

  final TextEditingController controller;
  final bool sending;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onPostNote;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: NestColor.card,
          border: Border(top: BorderSide(color: NestColor.rule)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Post a note',
              onPressed: sending ? null : onPostNote,
              icon: const Icon(Icons.note_add_outlined),
              color: NestColor.pen,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                minLines: 1,
                maxLines: 5,
                maxLength: maxMessageLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Message',
                  counterText: '',
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              icon: const Icon(Icons.send_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: NestColor.inkFaint),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Picking one of your own notes to post.
class _NotePicker extends StatelessWidget {
  const _NotePicker();

  @override
  Widget build(BuildContext context) {
    final notes = NoteRepository.instance.notes();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: NestColor.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
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
            'Post a note',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Everyone here sees it straight away. Each of them decides for '
            'themselves whether to keep it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Text(
                'You have no notes to post yet.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: notes.length,
                itemBuilder: (context, i) {
                  final n = notes[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: NestColor.card,
                      borderRadius: BorderRadius.circular(NestRadius.tile),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(NestRadius.tile),
                        onTap: () => Navigator.of(context).pop(n),
                        child: Padding(
                          padding: const EdgeInsets.all(13),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                n.title.trim().isEmpty
                                    ? 'Untitled note'
                                    : n.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    Theme.of(context).textTheme.titleSmall,
                              ),
                              if (n.body.trim().isNotEmpty)
                                Text(
                                  n.body.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
