import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/note_markup.dart';
import '../theme/nest_theme.dart';

/// A note's text, drawn with its formatting: headings, bullets, numbered
/// lines, bold, italic, highlights and checkboxes that can be ticked.
///
/// [onChanged] is given the whole new body when a checkbox is ticked. Pass
/// null for a read-only view, where the boxes are drawn but do nothing.
class NoteBody extends StatelessWidget {
  const NoteBody({super.key, required this.body, this.onChanged});

  final String body;
  final ValueChanged<String>? onChanged;

  TextStyle get _base => TextStyle(
        fontFamily: NestFont.body,
        fontSize: 15.5,
        height: 1.62,
        color: NestColor.ink,
      );

  List<InlineSpan> _spans(String text, TextStyle style) {
    return [
      for (final r in parseInline(text))
        TextSpan(
          text: r.text,
          style: style.copyWith(
            fontWeight: r.bold ? FontWeight.w700 : null,
            fontStyle: r.italic ? FontStyle.italic : null,
            backgroundColor:
                r.mark ? NestColor.o(NestColor.highlight, 0.6) : null,
            color: r.mark ? NestColor.onHighlight : null,
          ),
        ),
    ];
  }

  Widget _block(BuildContext context, MarkBlock b) {
    switch (b.kind) {
      case BlockKind.blank:
        return const SizedBox(height: 10);
      case BlockKind.heading:
        final size = switch (b.level) { 1 => 23.0, 2 => 19.5, _ => 17.0 };
        final style = TextStyle(
          fontFamily: NestFont.display,
          fontSize: size,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: NestColor.ink,
        );
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text.rich(TextSpan(children: _spans(b.text, style))),
        );
      case BlockKind.bullet:
        return _listRow(
          Text('•', style: _base.copyWith(color: NestColor.pen)),
          b.text,
        );
      case BlockKind.numbered:
        return _listRow(
          Text(
            '${num_(b.number)}.',
            style: _base.copyWith(
              color: NestColor.pen,
              fontWeight: FontWeight.w600,
            ),
          ),
          b.text,
          width: 28,
        );
      case BlockKind.check:
        final style = b.checked
            ? _base.copyWith(
                color: NestColor.inkFaint,
                decoration: TextDecoration.lineThrough,
              )
            : _base;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onChanged == null
                    ? null
                    : () => onChanged!(toggleCheck(body, b.line)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 10, 4),
                  child: Icon(
                    b.checked
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 22,
                    color: b.checked ? NestColor.mint : NestColor.inkFaint,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text.rich(TextSpan(children: _spans(b.text, style))),
                ),
              ),
            ],
          ),
        );
      case BlockKind.paragraph:
        return Text.rich(TextSpan(children: _spans(b.text, _base)));
    }
  }

  Widget _listRow(Widget marker, String text, {double width = 20}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: width, child: marker),
          Expanded(child: Text.rich(TextSpan(children: _spans(text, _base)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocks = parseMarkup(body);
    final progress = checkProgress(body);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (progress.total > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: progress.done == progress.total
                        ? NestColor.tintMint
                        : NestColor.tintPen,
                    borderRadius: BorderRadius.circular(NestRadius.pill),
                  ),
                  child: Text(
                    trp('{0} of {1} done', [progress.done, progress.total]),
                    style: TextStyle(
                      fontFamily: NestFont.body,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: progress.done == progress.total
                          ? NestColor.mintDeep
                          : NestColor.penDeep,
                    ),
                  ),
                ),
              ),
            ),
          for (final b in blocks) _block(context, b),
        ],
      ),
    );
  }
}
