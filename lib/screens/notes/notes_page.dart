import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/note.dart';
import '../../models/note_query.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_empty_state.dart';
import '../../widgets/nest_query_bar.dart';
import '../../widgets/note_tile.dart';
import '../search/search_page.dart';
import 'note_detail.dart';
import 'note_editor.dart';

/// Every note the student owns. Requirement 6.
///
/// When a subject is picked in the drawer the list narrows to that subject.
/// The filter bar then narrows it further by kind, revision status, important
/// mark or tag, and the sort menu decides the order. The filters live here in
/// screen state rather than in the database: they are how the student is
/// looking at the list right now, not something about the notes.
class NotesPage extends StatefulWidget {
  const NotesPage({
    super.key,
    required this.subjectCode,
    required this.onCapture,
  });

  final String subjectCode;
  final VoidCallback onCapture;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _repo = NoteRepository.instance;

  NoteQuery _query = const NoteQuery();

  void _openNote(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteDetailPage(noteId: id)),
    );
  }

  void _write(int? subjectId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorPage(initialSubjectId: subjectId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final subject = _repo.subjectByCode(widget.subjectCode);

        // The drawer owns the subject, the filter bar owns everything else.
        final query = _query.copyWith(
          subjectId: subject?.id,
          clearSubject: subject == null,
        );

        final all = _repo.notesForSubject(subject?.id);
        final notes = _repo.queryNotes(query);

        // Nothing filed here at all — the filters are not the reason.
        if (all.isEmpty) {
          return NestEmptyState(
            icon: Icons.auto_stories_rounded,
            title: subject?.name ?? 'Notes',
            message: subject == null
                ? 'Every note you keep will appear here, grouped by subject '
                    'and topic.'
                : 'Nothing filed under ${subject.code} yet.',
            actionLabel: _repo.hasSubjects ? 'Write a note' : null,
            onAction:
                _repo.hasSubjects ? () => _write(subject?.id) : null,
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 120),
          children: [
            Row(
              children: [
                if (subject != null) ...[
                  Container(
                    width: 5,
                    height: 20,
                    decoration: BoxDecoration(
                      color: subject.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    subject?.name ?? 'All notes',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Text(
                  notes.length == all.length
                      ? '${all.length}'
                      : '${notes.length} / ${all.length}',
                  style: nestEyebrow,
                ),
              ],
            ),
            const SizedBox(height: 12),
            NestQueryBar(
              query: query,
              tags: _repo.topTags(limit: 6),
              onChanged: (q) => setState(() => _query = q),
            ),
            const SizedBox(height: 6),
            if (notes.isEmpty)
              _NoMatch(
                query: query,
                onClear: () =>
                    setState(() => _query = _query.withoutFilters()),
                // "Search all" means all subjects, so the drawer's subject is
                // dropped on the way across; the filters are carried over.
                onSearch: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SearchPage(
                      initial: query.copyWith(clearSubject: true),
                    ),
                  ),
                ),
              )
            else
              for (final note in notes)
                NoteTile(note: note, onTap: () => _openNote(note.id!)),
          ],
        );
      },
    );
  }
}

/// Shown when the subject has notes but the filters leave none. It says which
/// filters are in force, because a list that looks empty for no reason is the
/// easiest way to lose trust in a filter bar.
class _NoMatch extends StatelessWidget {
  const _NoMatch({
    required this.query,
    required this.onClear,
    required this.onSearch,
  });

  final NoteQuery query;
  final VoidCallback onClear;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final NoteType? type = query.type;
    final StudyStatus? status = query.status;

    final bits = <String>[
      if (query.importantOnly) 'important',
      if (type != null) type.label.toLowerCase(),
      if (status != null) status.label.toLowerCase(),
      if (query.tag != null) '#${query.tag}',
    ];

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.card),
        border: Border.all(color: NestColor.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 16, color: NestColor.inkFaint),
              const SizedBox(width: 8),
              const Text('NO MATCH', style: nestEyebrow),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            bits.isEmpty
                ? 'Nothing here right now.'
                : 'No note here is ${bits.join(' + ')}.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Clear the filters to see the whole subject, or search across '
            'every subject instead.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onClear,
                  child: const Text('Clear filters'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Search all'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
