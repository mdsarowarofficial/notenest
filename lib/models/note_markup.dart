/// The light formatting a note body understands.
///
/// A note is still plain text on disk. The formatting is a handful of marks
/// typed into it, in the style people already use in chat and notes apps:
///
///     # Heading          ## Smaller heading
///     - bullet           1. numbered
///     - [ ] to do        - [x] done
///     **bold**   *italic*   ==highlighted==
///
/// Keeping it as text means search, backup, sharing and PDF export all keep
/// working with no change, and a note written here still reads sensibly in any
/// other app.
library;

enum BlockKind { blank, heading, bullet, numbered, check, paragraph }

/// One line of a note, read.
class MarkBlock {
  const MarkBlock({
    required this.kind,
    required this.text,
    required this.line,
    this.level = 0,
    this.checked = false,
    this.number = 0,
  });

  final BlockKind kind;

  /// The line without its leading mark.
  final String text;

  /// Zero-based line in the body, so a checkbox knows which line to flip.
  final int line;

  /// 1-3 for a heading.
  final int level;

  final bool checked;

  /// For a numbered line, the number as typed.
  final int number;
}

final _heading = RegExp(r'^(#{1,3})\s+(.*)$');
final _check = RegExp(r'^\s*[-*]\s+\[( |x|X)\]\s?(.*)$');
final _bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
final _numbered = RegExp(r'^\s*(\d{1,3})[.)]\s+(.*)$');

/// Reads a body line by line.
List<MarkBlock> parseMarkup(String body) {
  final lines = body.split('\n');
  final out = <MarkBlock>[];
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i].replaceAll('\r', '');
    if (raw.trim().isEmpty) {
      out.add(MarkBlock(kind: BlockKind.blank, text: '', line: i));
      continue;
    }
    final h = _heading.firstMatch(raw);
    if (h != null) {
      out.add(MarkBlock(
        kind: BlockKind.heading,
        text: h.group(2)!,
        line: i,
        level: h.group(1)!.length,
      ));
      continue;
    }
    final c = _check.firstMatch(raw);
    if (c != null) {
      out.add(MarkBlock(
        kind: BlockKind.check,
        text: c.group(2)!,
        line: i,
        checked: c.group(1)!.toLowerCase() == 'x',
      ));
      continue;
    }
    final b = _bullet.firstMatch(raw);
    if (b != null) {
      out.add(MarkBlock(kind: BlockKind.bullet, text: b.group(1)!, line: i));
      continue;
    }
    final n = _numbered.firstMatch(raw);
    if (n != null) {
      out.add(MarkBlock(
        kind: BlockKind.numbered,
        text: n.group(2)!,
        line: i,
        number: int.parse(n.group(1)!),
      ));
      continue;
    }
    out.add(MarkBlock(kind: BlockKind.paragraph, text: raw, line: i));
  }
  return out;
}

/// A stretch of one line with the same look.
class Run {
  const Run(this.text, {this.bold = false, this.italic = false, this.mark = false});

  final String text;
  final bool bold;
  final bool italic;
  final bool mark;
}

// `_` only counts as italic at the edge of a word, so snake_case_names are left
// alone.
final _inline = RegExp(
  r'\*\*(?=\S)(.+?)(?<=\S)\*\*|==(?=\S)(.+?)(?<=\S)==|\*(?=[^\s*])(.+?)(?<=[^\s*])\*|(?<![A-Za-z0-9])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![A-Za-z0-9])',
);

/// Splits a line into runs of plain, bold, italic and highlighted text.
List<Run> parseInline(String s) {
  final runs = <Run>[];
  var at = 0;
  for (final m in _inline.allMatches(s)) {
    if (m.start > at) runs.add(Run(s.substring(at, m.start)));
    if (m.group(1) != null) {
      runs.add(Run(m.group(1)!, bold: true));
    } else if (m.group(2) != null) {
      runs.add(Run(m.group(2)!, mark: true));
    } else {
      runs.add(Run((m.group(3) ?? m.group(4))!, italic: true));
    }
    at = m.end;
  }
  if (at < s.length) runs.add(Run(s.substring(at)));
  return runs;
}

/// The body with its marks taken out: what a list preview or a word count
/// should show.
String plainText(String body) {
  final lines = parseMarkup(body).map((b) {
    final text = parseInline(b.text).map((r) => r.text).join();
    switch (b.kind) {
      case BlockKind.check:
        return '${b.checked ? '☑' : '☐'} $text';
      case BlockKind.bullet:
        return '• $text';
      case BlockKind.numbered:
        return '${b.number}. $text';
      default:
        return text;
    }
  });
  return lines.join('\n');
}

/// The body with the checkbox on [line] flipped, or unchanged if that line is
/// not a checkbox.
String toggleCheck(String body, int line) {
  final lines = body.split('\n');
  if (line < 0 || line >= lines.length) return body;
  final m = RegExp(r'^(\s*[-*]\s+\[)( |x|X)(\].*)$').firstMatch(lines[line]);
  if (m == null) return body;
  lines[line] = '${m.group(1)}${m.group(2) == ' ' ? 'x' : ' '}${m.group(3)}';
  return lines.join('\n');
}

/// How many checkboxes are ticked, and how many there are.
({int done, int total}) checkProgress(String body) {
  var done = 0;
  var total = 0;
  for (final b in parseMarkup(body)) {
    if (b.kind != BlockKind.check) continue;
    total++;
    if (b.checked) done++;
  }
  return (done: done, total: total);
}

/// What pressing Enter at the end of a list line should type on the next one:
/// the same mark, a fresh checkbox, or the next number. Null when the line is
/// not a list line. An empty list line returns '' with [endList] set, meaning
/// "that was the last item, remove the mark instead".
({String prefix, bool endList})? continuationFor(String line) {
  final c = RegExp(r'^(\s*[-*]\s+\[)( |x|X)(\]\s?)(.*)$').firstMatch(line);
  if (c != null) {
    return (prefix: '${c.group(1)} ${c.group(3)}', endList: c.group(4)!.trim().isEmpty);
  }
  final b = RegExp(r'^(\s*[-*•]\s+)(.*)$').firstMatch(line);
  if (b != null) return (prefix: b.group(1)!, endList: b.group(2)!.trim().isEmpty);
  final n = RegExp(r'^(\s*)(\d{1,3})([.)]\s+)(.*)$').firstMatch(line);
  if (n != null) {
    return (
      prefix: '${n.group(1)}${int.parse(n.group(2)!) + 1}${n.group(3)}',
      endList: n.group(4)!.trim().isEmpty,
    );
  }
  return null;
}
