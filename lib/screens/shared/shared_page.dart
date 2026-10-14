import 'package:flutter/material.dart';

import '../../data/cloud_service.dart';
import '../../data/note_repository.dart';
import '../../models/note.dart';
import '../../models/note_bundle.dart';
import '../../models/note_share.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_mark_tile.dart';
import '../../widgets/nest_empty_state.dart';
import '../../widgets/note_tile.dart';
import '../notes/note_detail.dart';
import '../chat/chat_page.dart';
import '../share/import_page.dart';
import '../share/request_note_sheet.dart';

/// The Shared inbox — everything classmates have sent. Requirement 9.
///
/// Grouped by who sent it, because that is how a student thinks about a
/// borrowed note: not "a note about joins" but "the one Rafi gave me". The
/// grouping is read off the notes themselves rather than kept as a separate
/// contact list, so it can never drift out of step with what is actually here.
///
/// Notes sent through the cloud arrive here too, as a band at the top waiting
/// to be accepted. Deliberately the same screen rather than a second inbox:
/// two places to look for a shared note is one place too many, and the moment
/// a cloud note is accepted it becomes an ordinary shared note below.
class SharedPage extends StatelessWidget {
  const SharedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([repo, CloudService.instance]),
      builder: (context, _) {
        final notes = repo.inboxNotes();
        final sharers = repo.sharers();

        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 120),
          children: [
            const _PendingBand(),

            if (notes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: NestEmptyState(
                  icon: Icons.move_to_inbox_rounded,
                  title: 'Nothing shared yet',
                  message: 'When a classmate sends you a NoteNest note it '
                      'lands here and joins your own subjects — with their '
                      'name still on it.',
                  actionLabel: 'Import a note',
                  onAction: () => _import(context),
                ),
              )
            else
              ..._received(context, notes, sharers),
          ],
        );
      },
    );
  }

  List<Widget> _received(
    BuildContext context,
    List<Note> notes,
    Map<String, int> sharers,
  ) {
    // Newest sender first, matching the order of the notes below.
    final order = <String>[];
    for (final n in notes) {
      final who = n.sharedBy!;
      if (!order.contains(who)) order.add(who);
    }

    return [
      Row(
        children: [
          Expanded(
            child: Text(
              'Shared with you',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Text('${notes.length}', style: nestEyebrow),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        '${sharers.length} '
        '${sharers.length == 1 ? 'classmate' : 'classmates'} '
        'have sent you notes.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _import(context),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Import'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => showRequestNoteSheet(context),
              icon: const Icon(Icons.waving_hand_outlined, size: 18),
              label: const Text('Ask for one'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      for (final who in order) ...[
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NestColor.o(NestColor.pen, 0.26),
                shape: BoxShape.circle,
              ),
              child: Text(
                _initial(who),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: NestColor.pen,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                who,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text('${sharers[who] ?? 0}', style: nestEyebrow),
          ],
        ),
        const SizedBox(height: 2),
        for (final note in notes.where((n) => n.sharedBy == who))
          NoteTile(
            note: note,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NoteDetailPage(noteId: note.id!),
              ),
            ),
          ),
      ],
    ];
  }

  /// Delegates to the one rune-safe implementation. `name[0]` cuts a Bengali
  /// letter in half, and on an empty name it throws.
  static String _initial(String name) {
    final t = name.trim();
    return t.isEmpty ? '?' : firstLetterOf(t);
  }

  static void _import(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ImportNotePage()),
    );
  }
}

// ---------------------------------------------------------- waiting shares

class _PendingBand extends StatefulWidget {
  const _PendingBand();

  @override
  State<_PendingBand> createState() => _PendingBandState();
}

class _PendingBandState extends State<_PendingBand> {
  /// Held rather than rebuilt. The Shared page rebuilds whenever any note
  /// changes, and a stream made inside build would start a fresh Firestore
  /// listener each time — so accepting one note would make the rest of the
  /// band vanish and come back.
  Stream<List<NoteShare>>? _shares;
  String? _forUid;

  Stream<List<NoteShare>> _stream() {
    final cloud = CloudService.instance;
    if (_shares == null || _forUid != cloud.uid) {
      _forUid = cloud.uid;
      _shares = cloud.watchIncomingShares();
    }
    return _shares!;
  }

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    if (!cloud.isSignedIn) return const SizedBox.shrink();

    return StreamBuilder<List<NoteShare>>(
      stream: _stream(),
      builder: (context, snap) {
        final waiting = snap.data ?? const <NoteShare>[];
        if (waiting.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    waiting.length == 1
                        ? '1 note waiting'
                        : '${waiting.length} notes waiting',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const Icon(
                  Icons.mark_email_unread_outlined,
                  color: NestColor.pen,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Nothing is added to your notebook until you accept it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final share in waiting) _PendingTile(share: share),
            const SizedBox(height: 22),
            const Divider(color: NestColor.rule),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _PendingTile extends StatefulWidget {
  const _PendingTile({required this.share});

  final NoteShare share;

  @override
  State<_PendingTile> createState() => _PendingTileState();
}

class _PendingTileState extends State<_PendingTile> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      // The same decoder that reads a `.notenest` file off disk, with the same
      // refusals. A note arriving over the network has been through at least
      // one more machine than one arriving as a file, so if anything deserves
      // the strict reader it is this.
      final bundle = NoteBundle.decode(widget.share.payload);
      await NoteRepository.instance.importBundle(bundle);
      await CloudService.instance
          .respondToShare(widget.share, accept: true);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Added "${bundle.title}" to your notes')),
      );
    } on BundleException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('That note could not be read: ${e.message}')),
      );
    } on CloudException catch (e) {
      // The note is already in the notebook at this point; only the answer
      // failed to record. Saying so is better than implying nothing happened.
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Added, but it is still showing as waiting: '
              '${e.message}'),
        ),
      );
    }
  }

  Future<void> _message() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final chatId =
          await CloudService.instance.openDirectChat(widget.share.fromUid);
      if (!mounted) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            chatId: chatId,
            title: widget.share.fromLabel,
          ),
        ),
      );
    } on CloudException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    try {
      await CloudService.instance
          .respondToShare(widget.share, accept: false);
    } on CloudException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final share = widget.share;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NestColor.card,
          borderRadius: BorderRadius.circular(NestRadius.tile),
          boxShadow: NestShadow.resting,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: NestColor.o(NestColor.pen, 0.26),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    firstLetterOf(share.fromLabel),
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
                        share.title.trim().isEmpty
                            ? 'Untitled note'
                            : share.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        share.subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // A note from somebody you share no group with used to arrive
                // with no way to answer it. This is that way.
                IconButton(
                  tooltip: 'Message ${share.fromLabel}',
                  icon: const Icon(Icons.forum_outlined, size: 20),
                  color: NestColor.pen,
                  onPressed: _busy ? null : _message,
                ),
              ],
            ),
            if (share.message.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: NestColor.paper,
                  borderRadius: BorderRadius.circular(NestRadius.chip),
                ),
                child: Text(
                  share.message,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _decline,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NestColor.inkSoft,
                    ),
                    child: const Text('No thanks'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _busy ? null : _accept,
                    child: Text(_busy ? 'Working…' : 'Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
