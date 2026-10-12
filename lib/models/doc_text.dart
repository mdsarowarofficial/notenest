/// The middle ground between a PDF and a Word file.
///
/// Converting one format straight into the other means writing two converters
/// and maintaining four behaviours. Everything here goes through one shape
/// instead — a flat list of [DocBlock]s — so PDF and DOCX each only have to
/// know how to turn into blocks and how to be built from them.
///
/// What this deliberately does not model: tables, images, columns, footnotes,
/// fonts, colours. A converter that claims those and gets them slightly wrong
/// is worse than one that says plainly it carries text and structure.
library;

import 'package:xml/xml.dart';

/// What a paragraph is, as far as a converter can tell.
enum DocStyle { title, heading, subheading, body, bullet, numbered, quote }

class DocBlock {
  const DocBlock(this.style, this.text);

  const DocBlock.body(this.text) : style = DocStyle.body;

  final DocStyle style;
  final String text;

  bool get isHeading =>
      style == DocStyle.title ||
      style == DocStyle.heading ||
      style == DocStyle.subheading;

  bool get isListItem => style == DocStyle.bullet || style == DocStyle.numbered;

  @override
  bool operator ==(Object other) =>
      other is DocBlock && other.style == style && other.text == text;

  @override
  int get hashCode => Object.hash(style, text);

  @override
  String toString() => '${style.name}: $text';
}

// --------------------------------------------------------------- plain text

final _bulletLine = RegExp(r'^\s*[-*•·‣]\s+(.*)$');
final _numberedLine = RegExp(r'^\s*(\d{1,3})[.)]\s+(.*)$');
final _quoteLine = RegExp(r'^\s*>\s?(.*)$');

/// Reads structure out of plain text — the text that comes back from a PDF.
///
/// A PDF has no paragraph styles, so the structure has to be guessed. The
/// guesses are kept conservative on purpose: a heading that was really a
/// sentence is a visible mistake, while a heading left as body text is only a
/// missed improvement.
List<DocBlock> blocksFromPlainText(String raw) {
  final out = <DocBlock>[];
  // A form feed is how a page break arrives from most extractors.
  final lines = raw.replaceAll('\r\n', '\n').replaceAll('\f', '\n').split('\n');

  final paragraph = <String>[];

  void flush() {
    if (paragraph.isEmpty) return;
    final text = paragraph.join(' ').trim();
    paragraph.clear();
    if (text.isEmpty) return;
    out.add(DocBlock(_styleForParagraph(text), text));
  }

  for (final line in lines) {
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      flush();
      continue;
    }

    final bullet = _bulletLine.firstMatch(line);
    if (bullet != null) {
      flush();
      out.add(DocBlock(DocStyle.bullet, bullet.group(1)!.trim()));
      continue;
    }

    final numbered = _numberedLine.firstMatch(line);
    if (numbered != null) {
      flush();
      out.add(DocBlock(
        DocStyle.numbered,
        '${numbered.group(1)}. ${numbered.group(2)!.trim()}',
      ));
      continue;
    }

    final quote = _quoteLine.firstMatch(line);
    if (quote != null) {
      flush();
      out.add(DocBlock(DocStyle.quote, quote.group(1)!.trim()));
      continue;
    }

    paragraph.add(trimmed);
  }
  flush();

  return out;
}

/// A heading only when the line looks like one from several directions at
/// once: short, no closing punctuation, and either all caps or numbered like
/// "3.2 Methodology".
DocStyle _styleForParagraph(String text) {
  if (text.length > 70) return DocStyle.body;
  if (text.endsWith('.') || text.endsWith(',') || text.endsWith(';')) {
    return DocStyle.body;
  }

  final sectioned = RegExp(r'^\d+(\.\d+)*\s+\S').hasMatch(text);
  final shouty = text == text.toUpperCase() &&
      text.contains(RegExp('[A-Z]')) &&
      text.length <= 60;

  if (shouty) return DocStyle.heading;
  if (sectioned) {
    // "3 Results" is a chapter, "3.2.1 Sample" is further down the tree.
    final depth = text.split(' ').first.split('.').length;
    return depth <= 1 ? DocStyle.heading : DocStyle.subheading;
  }
  return DocStyle.body;
}

String blocksToPlainText(List<DocBlock> blocks) {
  final out = <String>[];
  for (final b in blocks) {
    switch (b.style) {
      case DocStyle.bullet:
        out.add('• ${b.text}');
      case DocStyle.quote:
        out.add('> ${b.text}');
      default:
        out.add(b.text);
    }
  }
  return out.join('\n\n');
}

int wordsIn(List<DocBlock> blocks) {
  var n = 0;
  for (final b in blocks) {
    n += b.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }
  return n;
}

// -------------------------------------------------------------- docx: write

/// Escapes the five characters XML cannot carry raw.
///
/// `&` has to go first. Escaping it after the others would turn the `&` in
/// `&lt;` into `&amp;lt;` and the document would show the markup as text.
String escapeXml(String raw) => raw
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

const _wNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// Half-points, which is how Word stores a font size: 22 is 11pt.
int _sizeFor(DocStyle style) {
  switch (style) {
    case DocStyle.title:
      return 44;
    case DocStyle.heading:
      return 32;
    case DocStyle.subheading:
      return 26;
    default:
      return 22;
  }
}

/// The formatting is written directly onto every run rather than through named
/// styles.
///
/// A `w:pStyle` of "Heading1" only means something if the package also carries
/// a `styles.xml` defining it; without one, Word silently renders the heading
/// as body text. Direct formatting is more verbose and always looks right.
String _paragraph(DocBlock block) {
  final bold = block.isHeading;
  final italic = block.style == DocStyle.quote;
  final centred = block.style == DocStyle.title;
  final indented = block.isListItem || block.style == DocStyle.quote;

  final text = block.style == DocStyle.bullet ? '• ${block.text}' : block.text;

  final pPr = StringBuffer('<w:pPr>');
  if (centred) pPr.write('<w:jc w:val="center"/>');
  if (indented) pPr.write('<w:ind w:left="360"/>');
  pPr.write('<w:spacing w:after="${block.isHeading ? 120 : 160}"'
      ' w:line="276" w:lineRule="auto"/>');
  pPr.write('</w:pPr>');

  final rPr = StringBuffer('<w:rPr>');
  if (bold) rPr.write('<w:b/>');
  if (italic) rPr.write('<w:i/>');
  rPr.write('<w:sz w:val="${_sizeFor(block.style)}"/>');
  rPr.write('<w:szCs w:val="${_sizeFor(block.style)}"/>');
  rPr.write('</w:rPr>');

  // xml:space matters: without it Word trims the leading space of "• item".
  return '<w:p>$pPr<w:r>$rPr'
      '<w:t xml:space="preserve">${escapeXml(text)}</w:t>'
      '</w:r></w:p>';
}

/// A4 with 20mm margins, in twentieths of a point, which is Word's unit.
const _sectPr = '<w:sectPr>'
    '<w:pgSz w:w="11906" w:h="16838"/>'
    '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"'
    ' w:header="709" w:footer="709" w:gutter="0"/>'
    '</w:sectPr>';

String buildWordDocumentXml(List<DocBlock> blocks) {
  final body = StringBuffer();
  for (final b in blocks) {
    if (b.text.trim().isEmpty) continue;
    body.write(_paragraph(b));
  }
  // An empty body is still a valid document, and an empty .docx opens; a
  // missing one does not.
  if (body.isEmpty) body.write(_paragraph(const DocBlock.body('')));

  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="$_wNs">'
      '<w:body>$body$_sectPr</w:body>'
      '</w:document>';
}

const contentTypesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '</Types>';

const rootRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1"'
    ' Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"'
    ' Target="word/document.xml"/>'
    '</Relationships>';

// --------------------------------------------------------------- docx: read

/// Turns the `word/document.xml` of a .docx into blocks.
///
/// Element names are matched on their local name with any namespace, because
/// the prefix is only a convention: most writers use `w:`, but a file is
/// equally valid with `wd:` or with the namespace declared as the default.
/// Matching on `w:p` by name would read those as empty documents.
///
/// Paragraphs inside tables are read as ordinary paragraphs. The table's shape
/// is lost, which is a stated limitation, but the words inside it are not — and
/// losing a row of data silently would be the worse of the two.
List<DocBlock> blocksFromWordXml(String xml) {
  final doc = XmlDocument.parse(xml);
  final out = <DocBlock>[];

  for (final p in doc.findAllElements('p', namespaceUri: '*')) {
    final text = _runText(p);
    if (text.trim().isEmpty) continue;
    out.add(DocBlock(_styleForWordParagraph(p, text), _stripBullet(text)));
  }

  return out;
}

/// Joins the text runs, turning a tab into a space and a break into one too.
String _runText(XmlElement p) {
  final buffer = StringBuffer();
  for (final node in p.descendants) {
    if (node is! XmlElement) continue;
    switch (node.name.local) {
      case 't':
        buffer.write(node.innerText);
      case 'tab':
      case 'br':
        buffer.write(' ');
    }
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// A bullet character written into the text by an earlier conversion would
/// otherwise double up when this is exported again.
String _stripBullet(String text) {
  final m = _bulletLine.firstMatch(text);
  return m == null ? text : m.group(1)!.trim();
}

DocStyle _styleForWordParagraph(XmlElement p, String text) {
  final pPr = p.getElement('pPr', namespaceUri: '*');

  if (pPr != null) {
    if (pPr.getElement('numPr', namespaceUri: '*') != null) {
      return _numberedLine.hasMatch(text) ? DocStyle.numbered : DocStyle.bullet;
    }

    final pStyle = pPr.getElement('pStyle', namespaceUri: '*');
    final style =
        (pStyle == null ? '' : _attrVal(pStyle) ?? '').toLowerCase().replaceAll(' ', '');

    if (style.isNotEmpty) {
      if (style.contains('title')) return DocStyle.title;
      if (style.contains('quote')) return DocStyle.quote;
      if (style.contains('listparagraph')) return DocStyle.bullet;
      if (style.startsWith('heading')) {
        final level = RegExp(r'(\d)').firstMatch(style)?.group(1);
        return level == '1' ? DocStyle.heading : DocStyle.subheading;
      }
    }
  }

  // No usable style name, so fall back to how the text is formatted. Every run
  // bold and nothing else on the line is, in practice, a heading.
  final runs = p.findAllElements('r', namespaceUri: '*').toList();
  if (runs.isEmpty) return DocStyle.body;

  var allBold = true;
  var biggest = 0;
  for (final r in runs) {
    final rPr = r.getElement('rPr', namespaceUri: '*');
    if (rPr == null || rPr.getElement('b', namespaceUri: '*') == null) {
      allBold = false;
    }
    final szEl = rPr?.getElement('sz', namespaceUri: '*');
    final parsed = szEl == null ? 0 : int.tryParse(_attrVal(szEl) ?? '') ?? 0;
    if (parsed > biggest) biggest = parsed;
  }

  if (allBold && text.length <= 90) {
    if (biggest >= 36) return DocStyle.title;
    return biggest >= 28 ? DocStyle.heading : DocStyle.subheading;
  }
  return DocStyle.body;
}

/// `w:val` may arrive with or without its prefix resolved, depending on the
/// writer, so both spellings are tried.
String? _attrVal(XmlElement e) =>
    e.getAttribute('val', namespaceUri: '*') ?? e.getAttribute('w:val');
