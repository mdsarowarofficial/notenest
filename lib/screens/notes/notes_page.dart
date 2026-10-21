import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/note.dart';
import '../../models/note_query.dart';
import '../../models/subject.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_empty_state.dart';
import '../../widgets/nest_query_bar.dart';
import '../../widgets/note_tile.dart';
import '../search/search_page.dart';
import 'note_detail.dart';
import 'note_editor.dart';
import '../../l10n/strings.dart';

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
    required this.onPickSubject,
  });

  final String subjectCode;
  final VoidCallback onCapture;

  /// Called with a subject code, or the empty string for "All". The shell owns
  /// which subject is showing, because the drawer sets the same value.
  final ValueChanged<String> onPickSubject;

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
            title: subject?.name ?? tr('Notes'),
            message: subject == null
                ? tr('Every note you keep will appear here, grouped by subject '
                    'and topic.')
                : trp('Nothing filed under {0} yet.', [subject.code]),
            actionLabel: _repo.hasSubjects ? tr('Write a note') : null,
            onAction:
                _repo.hasSubjects ? () => _write(subject?.id) : null,
          );
        }

        return ListView(
          // Matches Today, so the two tabs do not shift sideways under your
          // thumb when you switch between them.
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 130),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject == null
                            ? tr('ALL SUBJECTS')
                            : subject.code.toUpperCase(),
                        style: nestEyebrow.copyWith(
                          color: subject?.color ?? NestColor.inkFaint,
                          letterSpacing: ls(1.1),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subject?.name ?? tr('All notes'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _CountPill(shown: notes.length, total: all.length),
              ],
            ),
            const SizedBox(height: 15),
            _SubjectChips(
              subjects: _repo.subjects(),
              selected: widget.subjectCode,
              total: _repo.notesForSubject(null).length,
              onPick: widget.onPickSubject,
            ),
            const SizedBox(height: 11),
            NestQueryBar(
              query: query,
              tags: _repo.topTags(limit: 6),
              onChanged: (q) => setState(() => _query = q),
            ),
            const SizedBox(height: 10),
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
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.card),
        boxShadow: NestShadow.resting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: NestColor.paperDeep,
              borderRadius: BorderRadius.circular(NestRadius.chip),
            ),
            child: Icon(
              Icons.filter_alt_off_rounded,
              size: 21,
              color: NestColor.inkSoft,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            bits.isEmpty
                ? tr('Nothing here right now.')
                : trp('No note here is {0}.', [bits.join(' + ')]),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            tr('Clear the filters to see the whole subject, or search across '
            'every subject instead.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onClear,
                  child: Text(tr('Clear filters')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: Text(tr('Search all')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How many notes the filters leave, out of how many the subject holds.
///
/// A pill rather than the old grey "4 / 12" caption: it is the only number on
/// the screen that tells you whether you are looking at everything or at a
/// slice of it, and as plain small type nobody read it.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.shown, required this.total});

  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) {
    final filtered = shown != total;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: filtered ? NestColor.tintPen : NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.pill),
        boxShadow: filtered ? const <BoxShadow>[] : NestShadow.resting,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            num_(filtered ? shown : total),
            style: TextStyle(
              fontFamily: NestFont.display,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1,
              color: filtered ? NestColor.penDeep : NestColor.ink,
            ),
          ),
          if (filtered)
            Text(
              trp(' / {0}', [total]),
              style: TextStyle(
                fontFamily: NestFont.body,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1,
                color: NestColor.pen,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 5),
              child: Text(
                total == 1 ? tr('note') : tr('notes'),
                style: TextStyle(
                  fontFamily: NestFont.body,
                  fontSize: 11.5,
                  height: 1,
                  color: NestColor.inkFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The subject row: All, then one chip per subject, each with its count.
///
/// The drawer could already do this, but picking a subject was three taps
/// behind a hamburger — on the one screen whose entire job is looking at one
/// subject's notes. Here it is the first thing under the title, and the
/// selected chip fills with the subject's own colour so the list below is
/// obviously filtered rather than mysteriously short.
class _SubjectChips extends StatelessWidget {
  const _SubjectChips({
    required this.subjects,
    required this.selected,
    required this.total,
    required this.onPick,
  });

  final List<Subject> subjects;
  final String selected;
  final int total;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (subjects.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      // Room for the chips' shadows, which a horizontal ListView would clip.
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          Center(
            child: _SubjectChip(
              label: tr('All'),
              count: total,
              fill: NestColor.pen,
              selected: selected.isEmpty,
              onTap: () => onPick(''),
            ),
          ),
          for (final subject in subjects) ...[
            const SizedBox(width: 8),
            Center(
              child: _SubjectChip(
                label: subject.code,
                count: subject.noteCount,
                // Subject colours are pastels, so a selected chip fills with a
                // darkened version and keeps white type readable on it.
                fill: Color.lerp(subject.color, NestColor.onHighlight, 0.42)!,
                selected: selected == subject.code,
                onTap: () => onPick(subject.code),
              ),
            ),
          ],
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

class _SubjectChip extends StatelessWidget {
  const _SubjectChip({
    required this.label,
    required this.count,
    required this.fill,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color fill;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? fill : NestColor.card,
          borderRadius: BorderRadius.circular(NestRadius.pill),
          boxShadow: selected
              ? NestShadow.glow(fill)
              : const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x0F1B1E2B),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: NestFont.body,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : NestColor.inkSoft,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              trp('{0}', [count]),
              style: TextStyle(
                fontFamily: NestFont.display,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected
                    ? NestColor.o(Colors.white, 0.72)
                    : NestColor.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
