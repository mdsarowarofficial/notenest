import 'package:flutter/material.dart';

import '../data/note_repository.dart';
import '../models/note.dart';
import '../theme/nest_theme.dart';
import 'nest_marks.dart';

/// One note in a list. Used by Today, Notes and Trash so a note looks the same
/// everywhere it appears.
class NoteTile extends StatelessWidget {
  const NoteTile({
    super.key,
    required this.note,
    this.onTap,
    this.trailing,
    this.showRule = true,
  });

  final Note note;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showRule;

  @override
  Widget build(BuildContext context) {
    final subject = note.subjectId == null
        ? null
        : NoteRepository.instance.subjectById(note.subjectId!);

    final meta = [
      if (subject != null) subject.code,
      if (note.topic != null && note.topic!.isNotEmpty) note.topic!,
      relativeDay(note.updatedAt),
    ].join(' · ');

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 5,
                  height: 38,
                  decoration: BoxDecoration(
                    color: subject?.color ?? NestColor.rule,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              note.title.isEmpty ? 'Untitled note' : note.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          if (note.important) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.star_rounded,
                                size: 15, color: NestColor.redPen),
                          ],
                        ],
                      ),
                      if (note.body.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          note.body.trim().replaceAll('\n', ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          StatusDot(status: note.status),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nestEyebrow.copyWith(
                                letterSpacing: 0.3,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                trailing ??
                    const Icon(Icons.chevron_right_rounded,
                        color: NestColor.inkFaint),
              ],
            ),
          ),
        ),
        if (showRule) const PaperRule(indent: 19),
      ],
    );
  }
}

/// A small coloured marker for the revision status.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status, this.withLabel = false});

  final StudyStatus status;
  final bool withLabel;

  static Color colorFor(StudyStatus status) {
    switch (status) {
      case StudyStatus.newNote:
        return NestColor.inkFaint;
      case StudyStatus.read:
        return NestColor.pen;
      case StudyStatus.review:
        return NestColor.redPen;
      case StudyStatus.mastered:
        return NestColor.mint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        if (withLabel) ...[
          const SizedBox(width: 6),
          Text(
            status.label,
            style: nestEyebrow.copyWith(color: color, letterSpacing: 0.8),
          ),
        ],
      ],
    );
  }
}
