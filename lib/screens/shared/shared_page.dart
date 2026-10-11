import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_empty_state.dart';
import '../../widgets/note_tile.dart';
import '../notes/note_detail.dart';
import '../share/import_page.dart';
import '../share/request_note_sheet.dart';

/// The Shared inbox — everything classmates have sent. Requirement 9.
///
/// Grouped by who sent it, because that is how a student thinks about a
/// borrowed note: not "a note about joins" but "the one Rafi gave me". The
/// grouping is read off the notes themselves rather than kept as a separate
/// contact list, so it can never drift out of step with what is actually here.
class SharedPage extends StatelessWidget {
  const SharedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;

    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final notes = repo.inboxNotes();
        final sharers = repo.sharers();

        if (notes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 90),
            child: NestEmptyState(
              icon: Icons.move_to_inbox_rounded,
              title: 'Nothing shared yet',
              message: 'When a classmate sends you a NoteNest note, import it '
                  'here and it joins your own subjects — with their name still '
                  'on it.',
              actionLabel: 'Import a note',
              onAction: () => _import(context),
            ),
          );
        }

        // Newest sender first, matching the order of the notes below.
        final order = <String>[];
        for (final n in notes) {
          final who = n.sharedBy!;
          if (!order.contains(who)) order.add(who);
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 120),
          children: [
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
                      color: NestColor.o(NestColor.pen, 0.12),
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
          ],
        );
      },
    );
  }

  static String _initial(String name) {
    final t = name.trim();
    return t.isEmpty ? '?' : t[0].toUpperCase();
  }

  static void _import(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ImportNotePage()),
    );
  }
}
