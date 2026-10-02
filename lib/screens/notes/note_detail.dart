import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/note.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/note_tile.dart';
import 'attachment_strip.dart';
import 'note_editor.dart';

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
        title: const Text('Move to Trash?'),
        content: const Text(
          'The note stays in Trash until you delete it permanently, so you '
          'can bring it back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Move to Trash'),
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
        content: const Text('Note moved to Trash'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _repo.restoreNote(note),
        ),
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
          return const Scaffold(
            body: Center(child: Text('This note is no longer here.')),
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
                    ? 'Remove important mark'
                    : 'Mark as important',
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
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteEditorPage(existing: note),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Move to Trash',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _delete(note),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 40),
            children: [
              if (subject != null)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: NestColor.o(subject.color, 0.35),
                        borderRadius: BorderRadius.circular(NestRadius.chip),
                      ),
                      child: Text(
                        subject.code,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: NestColor.ink,
                        ),
                      ),
                    ),
                    if (note.topic != null && note.topic!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          note.topic!,
                          overflow: TextOverflow.ellipsis,
                          style: nestEyebrow.copyWith(letterSpacing: 0.4),
                        ),
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 14),
              Text(note.title, style: t.displaySmall),
              const SizedBox(height: 10),
              Text(
                'Written ${relativeDay(note.createdAt)} · '
                'Updated ${relativeDay(note.updatedAt)}',
                style: nestEyebrow.copyWith(
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 22),
              _StatusPicker(note: note),
              const SizedBox(height: 22),
              Container(height: 1, color: NestColor.rule),
              const SizedBox(height: 18),
              AttachmentStrip(note: note),
              const SizedBox(height: 18),
              if (note.body.trim().isEmpty)
                Text('This note has no body yet.', style: t.bodySmall)
              else
                SelectableText(
                  note.body,
                  style: const TextStyle(
                    fontSize: 15.5,
                    height: 1.6,
                    color: NestColor.ink,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Moves a note between New, Read, Review and Mastered.
class _StatusPicker extends StatelessWidget {
  const _StatusPicker({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('STUDY STATUS', style: nestEyebrow),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in StudyStatus.values)
              GestureDetector(
                onTap: () =>
                    NoteRepository.instance.setStatus(note, status),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: status == note.status
                        ? NestColor.o(StatusDot.colorFor(status), 0.16)
                        : NestColor.paper,
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                    border: Border.all(
                      color: status == note.status
                          ? StatusDot.colorFor(status)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusDot(status: status),
                      const SizedBox(width: 8),
                      Text(
                        status.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: status == note.status
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: NestColor.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
