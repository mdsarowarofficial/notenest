import 'package:flutter/material.dart';

import '../data/note_repository.dart';
import '../models/note.dart';
import '../models/transcript.dart' show formatClock;
import '../theme/nest_theme.dart';
import 'nest_mark_tile.dart';
import '../l10n/strings.dart';
import '../models/note_markup.dart';

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
    this.highlight = const [],
  });

  final Note note;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Search words to mark wherever they appear in the title and the preview.
  /// Lower-case, as [NoteQuery.terms] gives them.
  final List<String> highlight;

  /// Kept for the screens that already pass it. Cards need no rule between
  /// them, so this now only decides whether there is a gap below.
  final bool showRule;

  @override
  Widget build(BuildContext context) {
    final subject = note.subjectId == null
        ? null
        : NoteRepository.instance.subjectById(note.subjectId!);
    final t = Theme.of(context).textTheme;
    final body = plainText(note.body).trim().replaceAll('\n', ' ');
    final checks = checkProgress(note.body);

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
                              style: TextStyle(
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
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: NestColor.redPen,
                          ),
                        ),
                      Text(
                        relativeDay(note.updatedAt),
                        style: TextStyle(
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
                        child: Text.rich(
                          highlightedText(
                            note.title.isEmpty ? tr('Untitled note') : note.title,
                            highlight,
                            t.titleSmall,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (checks.total > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          checks.done == checks.total
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 15,
                          color: checks.done == checks.total
                              ? NestColor.mint
                              : NestColor.pen,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          trp('{0} of {1} done', [checks.done, checks.total]),
                          style: TextStyle(
                            fontFamily: NestFont.body,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: checks.done == checks.total
                                ? NestColor.mintDeep
                                : NestColor.pen,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (note.audioMs > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.graphic_eq_rounded,
                            size: 15, color: NestColor.pen),
                        const SizedBox(width: 5),
                        Text(
                          trp('{0} recording', [formatClock(Duration(milliseconds: note.audioMs))]),
                          style: TextStyle(
                            fontFamily: NestFont.body,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: NestColor.pen,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text.rich(
                      highlightedText(body, highlight, t.bodySmall),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                              style: TextStyle(
                                fontFamily: NestFont.body,
                                fontSize: 11,
                                color: NestColor.inkSoft,
                              ),
                            ),
                          ),
                        if (note.tags.length > 3)
                          Text(
                            trp('+{0}', [note.tags.length - 3]),
                            style: TextStyle(
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

/// [text] with every occurrence of a search word marked in the app's
/// highlighter yellow. Case-insensitive; with no words it is plain text.
TextSpan highlightedText(String text, List<String> terms, TextStyle? style) {
  final words = terms.where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return TextSpan(text: text, style: style);

  final lower = text.toLowerCase();
  // Lower-casing can change a string's length for a few scripts, in which case
  // the offsets would no longer line up; plain text is the safe answer there.
  if (lower.length != text.length) return TextSpan(text: text, style: style);

  // Mark every character a word covers, then cut the text where that changes.
  final marked = List<bool>.filled(text.length, false);
  for (final w in words) {
    var from = 0;
    while (true) {
      final at = lower.indexOf(w, from);
      if (at < 0) break;
      for (var i = at; i < at + w.length; i++) {
        marked[i] = true;
      }
      from = at + w.length;
    }
  }

  final hit = (style ?? const TextStyle()).copyWith(
    backgroundColor: NestColor.o(NestColor.highlight, 0.55),
    fontWeight: FontWeight.w700,
    color: NestColor.ink,
  );
  final spans = <TextSpan>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || marked[i] != marked[start]) {
      spans.add(TextSpan(
        text: text.substring(start, i),
        style: marked[start] ? hit : null,
      ));
      start = i;
    }
  }
  return TextSpan(style: style, children: spans);
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
            style: nestEyebrow.copyWith(color: color, letterSpacing: ls(0.8)),
          ),
        ],
      ],
    );
  }
}
