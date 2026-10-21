import 'package:flutter/services.dart';

import '../models/note_markup.dart';

/// Edits to a note's text for the formatting toolbar.
///
/// Each function takes the field's current value (text and selection) and
/// returns the new one, so the toolbar is a thin layer over logic that can be
/// tested without a screen.

/// Wraps the selection in [mark] (`**` for bold), or takes the mark off if the
/// selection is already wrapped. With nothing selected the mark is typed twice
/// and the cursor left between, ready for the words.
TextEditingValue toggleInline(TextEditingValue v, String mark) {
  final sel = v.selection;
  if (!sel.isValid) return v;
  final t = v.text;
  final s = sel.start;
  final e = sel.end;
  final m = mark.length;

  final wrapped = s >= m &&
      e + m <= t.length &&
      t.substring(s - m, s) == mark &&
      t.substring(e, e + m) == mark;
  if (wrapped) {
    return TextEditingValue(
      text: t.substring(0, s - m) + t.substring(s, e) + t.substring(e + m),
      selection: TextSelection(baseOffset: s - m, extentOffset: e - m),
    );
  }
  return TextEditingValue(
    text: t.substring(0, s) + mark + t.substring(s, e) + mark + t.substring(e),
    selection: s == e
        ? TextSelection.collapsed(offset: s + m)
        : TextSelection(baseOffset: s + m, extentOffset: e + m),
  );
}

enum LineStyle { heading, bullet, check, numbered }

// Any mark a line can start with.
final _leading = RegExp(r'^(\s*)(#{1,3}\s+|[-*•]\s+\[[ xX]\]\s?|[-*•]\s+|\d{1,3}[.)]\s+)');

/// Gives every line the selection touches the mark for [style], or takes it
/// off when they already have it. A heading cycles: none, #, ##, ###, none.
TextEditingValue toggleLineStyle(TextEditingValue v, LineStyle style) {
  final sel = v.selection;
  if (!sel.isValid) return v;
  final t = v.text;
  final from = t.lastIndexOf('\n', (sel.start - 1).clamp(0, t.length)) + 1;
  var to = t.indexOf('\n', sel.end);
  if (to < 0) to = t.length;

  final lines = t.substring(from, to).split('\n');

  // What the lines are now, to decide between adding and removing.
  String? current(String line) {
    final m = _leading.firstMatch(line);
    return m?.group(2)?.trim();
  }

  bool all(bool Function(String? c) test) => lines.every((l) => test(current(l)));

  String prefixFor(int index) {
    switch (style) {
      case LineStyle.bullet:
        return '- ';
      case LineStyle.check:
        return '- [ ] ';
      case LineStyle.numbered:
        return '${index + 1}. ';
      case LineStyle.heading:
        return '# ';
    }
  }

  late final bool remove;
  switch (style) {
    case LineStyle.bullet:
      remove = all((c) => c == '-' || c == '*' || c == '•');
    case LineStyle.check:
      remove = all((c) => c != null && c.contains('['));
    case LineStyle.numbered:
      remove = all((c) => c != null && RegExp(r'^\d').hasMatch(c));
    case LineStyle.heading:
      remove = false;
  }

  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final m = _leading.firstMatch(line);
    final indent = m?.group(1) ?? '';
    final body = m == null ? line : line.substring(m.end);

    if (style == LineStyle.heading) {
      final c = current(line);
      final level = (c != null && c.startsWith('#')) ? c.length : 0;
      out.add(level >= 3 ? body : '$indent${'#' * (level + 1)} $body');
    } else if (remove) {
      out.add('$indent$body');
    } else {
      out.add('$indent${prefixFor(i)}$body');
    }
  }

  final replaced = out.join('\n');
  return TextEditingValue(
    text: t.substring(0, from) + replaced + t.substring(to),
    selection: TextSelection.collapsed(offset: from + replaced.length),
  );
}

/// Pressing Enter on a list line starts the next item, and pressing it on an
/// empty item ends the list. Anything else types as normal.
class ListContinueFormatter extends TextInputFormatter {
  const ListContinueFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sel = newValue.selection;
    final typedEnter = newValue.text.length == oldValue.text.length + 1 &&
        sel.isCollapsed &&
        sel.baseOffset > 0 &&
        newValue.text[sel.baseOffset - 1] == '\n' &&
        oldValue.selection.isCollapsed &&
        oldValue.selection.baseOffset == sel.baseOffset - 1;
    if (!typedEnter) return newValue;

    final t = newValue.text;
    final cursor = sel.baseOffset;
    final lineStart = cursor >= 2 ? t.lastIndexOf('\n', cursor - 2) + 1 : 0;
    final line = t.substring(lineStart, cursor - 1);
    final next = continuationFor(line);
    if (next == null) return newValue;

    if (next.endList) {
      // That item was empty: drop its mark, and the Enter that was just typed.
      return TextEditingValue(
        text: t.substring(0, lineStart) + t.substring(cursor),
        selection: TextSelection.collapsed(offset: lineStart),
      );
    }
    return TextEditingValue(
      text: t.substring(0, cursor) + next.prefix + t.substring(cursor),
      selection: TextSelection.collapsed(offset: cursor + next.prefix.length),
    );
  }
}
