import 'package:flutter/material.dart';

import '../data/note_repository.dart';
import '../models/note.dart';
import '../theme/nest_theme.dart';
import 'nest_mark_tile.dart';

/// A note as one compact line: a coloured mark, a title, and a line of meta.
///
/// The short form of [NoteTile]. Today's list is a reminder of what to pick up,
/// not a place to read, so it shows no body text and no tags — and because the
/// row is short, the coloured mark on the left does the work that the status
/// pill does on the full card. Three or four of these down a page is where the
/// app's colour comes from.
class NoteRow extends StatelessWidget {
  const NoteRow({
    super.key,
    required this.note,
    this.onTap,
    this.trailing,
  });

  final Note note;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final subject = note.subjectId == null
        ? null
        : NoteRepository.instance.subjectById(note.subjectId!);

    final meta = <String>[
      if (subject != null) subject.code,
      relativeDay(note.updatedAt),
      if (note.type != NoteType.text) note.type.label.toLowerCase(),
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.tile),
        boxShadow: NestShadow.resting,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 17, 15),
            child: Row(
              children: [
                MarkTile.status(note.status),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title.trim().isEmpty
                            ? 'Untitled note'
                            : note.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: NestFont.display,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: NestColor.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: NestFont.body,
                          fontSize: 11.5,
                          color: NestColor.inkMeta,
                        ),
                      ),
                    ],
                  ),
                ),
                if (note.important)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.star_rounded,
                      size: 17,
                      color: NestColor.redPen,
                    ),
                  ),
                if (trailing != null) ...[
                  const SizedBox(width: 6),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
