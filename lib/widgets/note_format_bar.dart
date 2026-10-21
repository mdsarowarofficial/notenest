import 'package:flutter/material.dart';

import '../data/note_format.dart';
import '../l10n/strings.dart';
import '../theme/nest_theme.dart';

/// The row of formatting buttons above a note's text field.
///
/// Each button edits the text through [controller]: bold, italic and highlight
/// wrap the selection in marks; heading, bullet, checklist and numbered list
/// mark the lines the selection touches. [focus] is handed back to the text
/// field after every tap so the keyboard stays up.
class NoteFormatBar extends StatelessWidget {
  const NoteFormatBar({super.key, required this.controller, required this.focus});

  final TextEditingController controller;
  final FocusNode focus;

  void _apply(TextEditingValue Function(TextEditingValue) edit) {
    controller.value = edit(controller.value);
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, VoidCallback)>[
      (
        Icons.format_bold_rounded,
        tr('Bold'),
        () => _apply((v) => toggleInline(v, '**'))
      ),
      (
        Icons.format_italic_rounded,
        tr('Italic'),
        () => _apply((v) => toggleInline(v, '*'))
      ),
      (
        Icons.border_color_rounded,
        tr('Highlight'),
        () => _apply((v) => toggleInline(v, '=='))
      ),
      (
        Icons.title_rounded,
        tr('Heading'),
        () => _apply((v) => toggleLineStyle(v, LineStyle.heading))
      ),
      (
        Icons.format_list_bulleted_rounded,
        tr('Bullet list'),
        () => _apply((v) => toggleLineStyle(v, LineStyle.bullet))
      ),
      (
        Icons.checklist_rounded,
        tr('Checklist'),
        () => _apply((v) => toggleLineStyle(v, LineStyle.check))
      ),
      (
        Icons.format_list_numbered_rounded,
        tr('Numbered list'),
        () => _apply((v) => toggleLineStyle(v, LineStyle.numbered))
      ),
    ];

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: NestColor.paper,
        borderRadius: BorderRadius.circular(NestRadius.chip),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          for (final (icon, label, onTap) in actions)
            IconButton(
              tooltip: label,
              icon: Icon(icon, size: 22, color: NestColor.inkSoft),
              onPressed: onTap,
            ),
        ],
      ),
    );
  }
}
