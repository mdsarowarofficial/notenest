import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/note.dart';
import '../../models/note_query.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_mark_tile.dart';
import '../../widgets/nest_tags.dart';
import '../search/search_page.dart';
import '../share/share_note_sheet.dart';
import 'attachment_strip.dart';
import 'note_editor.dart';
import '../../l10n/strings.dart';
import '../../widgets/note_body.dart';

/// Read a note and change how it sits in the revision cycle. Requirement 7.
class NoteDetailPage extends StatefulWidget {
  const NoteDetailPage({super.key, required this.noteId});

  final int noteId;

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  final _repo = NoteRepository.instance;

  @override
  void initState() {
    super.initState();
    final note = _repo.noteById(widget.noteId);
    if (note != null) _repo.markOpened(note);
  }

  Future<void> _delete(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NestColor.card,
        title: Text(tr('Move to Trash?')),
        content: Text(
          tr('The note stays in Trash until you delete it permanently, so you '
          'can bring it back.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('Move to Trash')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _repo.deleteNote(note);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Note moved to Trash')),
        behavior: SnackBarBehavior.floating,
        // A snackbar with an action stays until dismissed unless told not to.
        persist: false,
        action: SnackBarAction(
          label: tr('Undo'),
          onPressed: () => _repo.restoreNote(note),
        ),
      ),
    );
  }

  /// Tapping a tag is how a student walks from one note to the rest of the
  /// material filed under the same idea.
  void _openTag(String tag) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchPage(initial: NoteQuery(tag: tag)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final note = _repo.noteById(widget.noteId);
        if (note == null) {
          return Scaffold(
            body: Center(child: Text(tr('This note is no longer here.'))),
          );
        }

        final subject = note.subjectId == null
            ? null
            : _repo.subjectById(note.subjectId!);
        final t = Theme.of(context).textTheme;

        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: note.important
                    ? tr('Remove important mark')
                    : tr('Mark as important'),
                icon: Icon(
                  note.important
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color:
                      note.important ? NestColor.redPen : NestColor.inkSoft,
                ),
                onPressed: () => _repo.toggleImportant(note),
              ),
              IconButton(
                tooltip: tr('Share with a classmate'),
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () => showShareNoteSheet(context, note),
              ),
              IconButton(
                tooltip: tr('Edit'),
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteEditorPage(existing: note),
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('Move to Trash'),
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _delete(note),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 44),
            children: [
              // The head of the note on one card: what it is, what it is
              // about, and how far through it you are. Before, these three
              // sat loose on the page separated by a hairline rule, which
              // made the screen look like a form rather than a thing you had
              // written.
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: BoxDecoration(
                  color: NestColor.card,
                  borderRadius: BorderRadius.circular(NestRadius.card),
                  boxShadow: NestShadow.resting,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        MarkTile.status(note.status, size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (subject != null)
                                Text(
                                  subject.code.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: nestEyebrow.copyWith(
                                    color: Color.lerp(
                                        subject.color, NestColor.ink, 0.45),
                                  ),
                                ),
                              Text(
                                note.topic != null && note.topic!.isNotEmpty
                                    ? note.topic!
                                    : tr('No topic'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: NestFont.body,
                                  fontSize: 12.5,
                                  color: NestColor.inkMeta,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (note.important)
                          Icon(
                            Icons.star_rounded,
                            size: 20,
                            color: NestColor.redPen,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      note.title.trim().isEmpty ? tr('Untitled note') : note.title,
                      style: t.displaySmall,
                    ),
                    const SizedBox(height: 9),
                    Text(
                      trp('Written {0} · Updated {1}', [relativeDay(note.createdAt), relativeDay(note.updatedAt)]),
                      style: TextStyle(
                        fontFamily: NestFont.body,
                        fontSize: 12,
                        color: NestColor.inkFaint,
                      ),
                    ),
                    if (note.tags.isNotEmpty) ...[
                      const SizedBox(height: 15),
                      NestTagChips(tags: note.tags, onTap: _openTag),
                    ],
                  ],
                ),
              ),
              if (note.isShared) ...[
                const SizedBox(height: 12),
                _SharedBanner(note: note),
              ],
              const SizedBox(height: 12),
              _StatusPicker(note: note),
              const SizedBox(height: 12),
              AttachmentStrip(note: note),
              const SizedBox(height: 12),
              // The note itself, on its own sheet. A body of text floating on
              // the page edge to edge reads as a description of the note; on
              // a card it reads as the note.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                decoration: BoxDecoration(
                  color: NestColor.card,
                  borderRadius: BorderRadius.circular(NestRadius.card),
                  boxShadow: NestShadow.resting,
                ),
                child: note.body.trim().isEmpty
                    ? Text(tr('This note has no body yet.'), style: t.bodySmall)
                    : NoteBody(
                        body: note.body,
                        // Ticking a checkbox saves straight away, so a
                        // checklist can be worked through without opening
                        // the editor.
                        onChanged: (next) =>
                            _repo.updateNote(note.copyWith(body: next)),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Keeps a borrowed note visibly borrowed.
///
/// Credit is the one thing that is easy to lose when notes pass around a
/// class, so whoever wrote it stays named on it for as long as it is in the
/// notebook — not just in the inbox it arrived through.
class _SharedBanner extends StatelessWidget {
  const _SharedBanner({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final reference = note.sharePolicy == SharePolicy.reference;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: NestColor.tintWarm,
        borderRadius: BorderRadius.circular(NestRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkTile.tool(
            Icons.people_outline_rounded,
            tint: NestColor.o(NestColor.warmDeep, 0.16),
            ink: NestColor.warmDeep,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trp('Shared by {0}', [note.sharedBy]),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (note.sharedAt != null || reference) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (note.sharedAt != null)
                        'Arrived ${relativeDay(note.sharedAt!)}',
                      if (reference) 'asked to be kept as reference',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Moves a note between New, Read, Review and Mastered.
///
/// The one control on this screen that changes the note rather than describing
/// it, so it sits on its own card. Selection is a solid fill in the status's
/// own colour: the old version marked it with a 1.5px border and a 16% wash,
/// a difference you had to hunt for on the very control whose whole job is to
/// tell you where this note stands.
class _StatusPicker extends StatelessWidget {
  const _StatusPicker({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.card),
        boxShadow: NestShadow.resting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('STUDY STATUS'), style: nestEyebrow),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in StudyStatus.values)
                _StatusChoice(status: status, note: note),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChoice extends StatelessWidget {
  const _StatusChoice({required this.status, required this.note});

  final StudyStatus status;
  final Note note;

  @override
  Widget build(BuildContext context) {
    final chosen = status == note.status;
    final fill = MarkTile.inkForStatus(status);

    return GestureDetector(
      onTap: () => NoteRepository.instance.setStatus(note, status),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: chosen ? fill : MarkTile.tintForStatus(status),
          borderRadius: BorderRadius.circular(NestRadius.pill),
          boxShadow: chosen ? NestShadow.glow(fill) : const <BoxShadow>[],
        ),
        child: Text(
          status.label,
          style: TextStyle(
            fontFamily: NestFont.body,
            fontSize: 13,
            fontWeight: chosen ? FontWeight.w700 : FontWeight.w600,
            color: chosen ? Colors.white : fill,
          ),
        ),
      ),
    );
  }
}
