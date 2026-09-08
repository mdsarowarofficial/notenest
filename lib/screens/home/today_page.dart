import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/note_tile.dart';
import '../notes/note_detail.dart';
import '../notes/note_editor.dart';
import '../subjects/subject_form.dart';

/// The landing screen. Requirement 3.
///
/// It names the single next thing worth doing, then gets out of the way.
class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.onOpenNotes,
    required this.onCapture,
  });

  final VoidCallback onOpenNotes;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;

    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        final days = repo.daysToNextExam;
        final recent = repo.recentNotes(limit: 5);

        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 120),
          children: [
            Text(todayLabel(), style: nestEyebrow),
            const SizedBox(height: 8),
            Text(_headline(repo, days), style: t.displaySmall),
            const SizedBox(height: 10),
            Text(_subline(repo), style: t.bodyMedium),
            const SizedBox(height: 24),

            if (!repo.hasSubjects)
              _StartCard(
                eyebrow: 'FIRST STEP',
                title: 'Add a subject',
                body: 'Subjects give every note a colour and a place to live. '
                    'You can add more later from the drawer.',
                actionLabel: 'Add a subject',
                onAction: () => showSubjectForm(context),
              )
            else if (!repo.hasNotes)
              _StartCard(
                eyebrow: 'NEXT STEP',
                title: 'Write your first note',
                body: 'Give it a title, pick the subject and topic, and start '
                    'writing. It saves as you type.',
                actionLabel: 'Write a note',
                onAction: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NoteEditorPage()),
                ),
              )
            else ...[
              _RevisionCard(
                total: repo.unrevisedCount,
                important: repo.importantUnrevisedCount,
                onOpen: onOpenNotes,
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Text('RECENT', style: nestEyebrow),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(height: 1, color: NestColor.rule),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (final note in recent)
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

  String _headline(NoteRepository repo, int? days) {
    if (days == null) {
      if (!repo.hasSubjects) return 'Nothing filed yet.';
      if (!repo.hasNotes) return 'Your notebook is ready.';
      return '${repo.notes().length} '
          '${repo.notes().length == 1 ? 'note' : 'notes'} in your notebook.';
    }
    if (days <= 0) return 'Your ${repo.nextExamSubject} exam is today.';
    return '$days ${days == 1 ? 'day' : 'days'} to your\n'
        '${repo.nextExamSubject} exam.';
  }

  String _subline(NoteRepository repo) {
    if (!repo.hasSubjects) {
      return 'Add a subject to begin.';
    }
    if (!repo.hasNotes) return 'No notes yet in any subject.';
    return 'Set an exam date in Exam Mode to see a countdown here.';
  }
}

/// A card that names the single next thing worth doing.
class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
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
              Container(width: 4, height: 16, color: NestColor.pen),
              const SizedBox(width: 8),
              Text(eyebrow, style: nestEyebrow.copyWith(color: NestColor.pen)),
            ],
          ),
          const SizedBox(height: 14),
          Text(title, style: t.titleMedium),
          const SizedBox(height: 6),
          Text(body, style: t.bodySmall),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _RevisionCard extends StatelessWidget {
  const _RevisionCard({
    required this.total,
    required this.important,
    required this.onOpen,
  });

  final int total;
  final int important;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final done = total == 0;

    return Container(
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
              Container(
                width: 4,
                height: 16,
                color: done ? NestColor.mint : NestColor.redPen,
              ),
              const SizedBox(width: 8),
              Text(
                done ? 'ALL MASTERED' : 'NEEDS REVISION',
                style: nestEyebrow.copyWith(
                  color: done ? NestColor.mint : NestColor.redPen,
                ),
              ),
              const Spacer(),
              if (!done) Text('$total NOTES', style: nestEyebrow),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            done
                ? 'Every note is marked Mastered'
                : important > 0
                    ? 'Start with the $important you marked important'
                    : 'Work through what you have not mastered yet',
            style: t.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            done
                ? 'Nothing is waiting for revision right now.'
                : 'Notes move from New to Read to Review to Mastered as you '
                    'work through them.',
            style: t.bodySmall,
          ),
          if (!done) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onOpen,
                child: const Text('Open my notes'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
