import 'package:flutter/material.dart';

import '../data/note_repository.dart';
import '../models/note.dart';
import '../theme/nest_theme.dart';
import 'nest_mark_tile.dart';

/// One note in a list. Used by Today, Notes, Shared, Search and Trash, so a
/// note looks the same everywhere it appears — and changing it here changes
/// every list in the app at once.
///
/// A card rather than a row on a ruled line. The ruled version read as a
/// table: every note looked like every other note, and the study status —
/// which is the one idea in this app that no other notes app has — was an
/// eight-pixel dot nobody noticed. Here the status is the first thing in the
/// card and it carries a colour.
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

  /// Kept for the screens that already pass it. Cards need no rule between
  /// them, so this now only decides whether there is a gap below.
  final bool showRule;

  @override
  Widget build(BuildContext context) {
    final subject = note.subjectId == null
        ? null
        : NoteRepository.instance.subjectById(note.subjectId!);
    final t = Theme.of(context).textTheme;
    final body = note.body.trim().replaceAll('\n', ' ');

    return Padding(
      padding: EdgeInsets.only(bottom: showRule ? 12 : 0),
      child: Container(
        decoration: BoxDecoration(
          color: NestColor.card,
          borderRadius: BorderRadius.circular(NestRadius.tile + 2),
          boxShadow: NestShadow.resting,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusPill(status: note.status),
                      if (subject != null) ...[
                        const SizedBox(width: 7),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: NestColor.o(subject.color, 0.22),
                              borderRadius:
                                  BorderRadius.circular(NestRadius.chip - 4),
                            ),
                            child: Text(
                              subject.code,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: NestFont.body,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: NestColor.ink,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (note.important)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: NestColor.redPen,
                          ),
                        ),
                      Text(
                        relativeDay(note.updatedAt),
                        style: const TextStyle(
                          fontFamily: NestFont.body,
                          fontSize: 11,
                          color: NestColor.inkFaint,
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 4),
                        trailing!,
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (note.type != NoteType.text)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 7),
                          child: Icon(
                            _typeIcon(note.type),
                            size: 15,
                            color: NestColor.inkFaint,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          note.title.isEmpty ? 'Untitled note' : note.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall,
                    ),
                  ],
                  if (note.tags.isNotEmpty) ...[
                    const SizedBox(height: 11),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Three at most. A note with eleven tags should not be
                        // three times taller than one with two.
                        for (final tag in note.tags.take(3))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: NestColor.paper,
                              borderRadius:
                                  BorderRadius.circular(NestRadius.pill),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                fontFamily: NestFont.body,
                                fontSize: 11,
                                color: NestColor.inkSoft,
                              ),
                            ),
                          ),
                        if (note.tags.length > 3)
                          Text(
                            '+${note.tags.length - 3}',
                            style: const TextStyle(
                              fontFamily: NestFont.body,
                              fontSize: 11,
                              color: NestColor.inkFaint,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _typeIcon(NoteType type) {
  switch (type) {
    case NoteType.image:
      return Icons.photo_rounded;
    case NoteType.pdf:
      return Icons.picture_as_pdf_rounded;
    case NoteType.voice:
      return Icons.mic_rounded;
    case NoteType.text:
      return Icons.notes_rounded;
  }
}

/// The revision status as a soft tinted pill.
///
/// Deliberately pale rather than a saturated block with white text on it: the
/// label has to stay readable at 10.5px, and reversed-out type that small is
/// the first thing to fail on a cheap screen in daylight.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final StudyStatus status;

  /// Delegates to [MarkTile], which owns the tint/ink pairs. Two copies of
  /// these switches drifted apart once already: the pill said one yellow and
  /// the row mark said another.
  static Color tintFor(StudyStatus status) => MarkTile.tintForStatus(status);

  static Color inkFor(StudyStatus status) => MarkTile.inkForStatus(status);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: tintFor(status),
        borderRadius: BorderRadius.circular(NestRadius.pill),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontFamily: NestFont.body,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.1,
          color: inkFor(status),
        ),
      ),
    );
  }
}

/// A small coloured marker for the revision status.
///
/// Kept because four other screens draw their own layouts around it, and
/// because `colorFor` is the single place the status colours are decided.
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
