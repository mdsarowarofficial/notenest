import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_empty_state.dart';
import '../../widgets/note_tile.dart';
import 'note_detail.dart';
import 'note_editor.dart';

/// Every note the student owns. Requirement 6.
///
/// When a subject is picked in the drawer the list narrows to that subject;
/// otherwise it shows everything, newest first.
class NotesPage extends StatelessWidget {
  const NotesPage({
    super.key,
    required this.subjectCode,
    required this.onCapture,
  });

  final String subjectCode;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;

    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final subject = repo.subjectByCode(subjectCode);
        final notes = subject == null
            ? repo.notes()
            : repo.notesForSubject(subject.id);

        if (notes.isEmpty) {
          return NestEmptyState(
            icon: Icons.auto_stories_rounded,
            title: subject?.name ?? 'Notes',
            message: subject == null
                ? 'Every note you keep will appear here, grouped by subject '
                    'and topic.'
                : 'Nothing filed under ${subject.code} yet.',
            actionLabel: repo.hasSubjects ? 'Write a note' : null,
            onAction: repo.hasSubjects
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            NoteEditorPage(initialSubjectId: subject?.id),
                      ),
                    )
                : null,
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
                Text('${notes.length}', style: nestEyebrow),
              ],
            ),
            const SizedBox(height: 6),
            for (final note in notes)
              NoteTile(
                note: note,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteDetailPage(noteId: note.id!),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
