/// Breaking a document into A4 pages.
///
/// Everything here is measured in PostScript points, the same unit
/// [PaperSheet] lays its children out in, so a page that the paginator says
/// fits really does fit when it is drawn.
///
/// Heights come from a real [TextPainter] rather than an estimate of
/// characters per line. An estimate is wrong the moment the text is Bengali,
/// where one cluster can be several code points wide and a line holds far
/// fewer characters than the same width of English.
library;

import 'package:flutter/widgets.dart';

import '../models/doc_text.dart';
import 'page_renderer.dart';

/// The type scale for a converted document, in points.
TextStyle docStyleFor(DocStyle style) {
  switch (style) {
    case DocStyle.title:
      return const TextStyle(
        fontSize: 22,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: Color(0xFF111111),
      );
    case DocStyle.heading:
      return const TextStyle(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: Color(0xFF111111),
      );
    case DocStyle.subheading:
      return const TextStyle(
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: Color(0xFF111111),
      );
    case DocStyle.quote:
      return const TextStyle(
        fontSize: 11,
        height: 1.55,
        fontStyle: FontStyle.italic,
        color: Color(0xFF333333),
      );
    default:
      return const TextStyle(
        fontSize: 11,
        height: 1.55,
        color: Color(0xFF111111),
      );
  }
}

/// The gap under a paragraph, in points.
double docSpacingAfter(DocStyle style) {
  switch (style) {
    case DocStyle.title:
      return 18;
    case DocStyle.heading:
      return 8;
    case DocStyle.subheading:
      return 6;
    case DocStyle.bullet:
    case DocStyle.numbered:
      return 4;
    default:
      return 10;
  }
}

/// How far a paragraph is pushed in from the left, in points.
double docIndent(DocStyle style) {
  switch (style) {
    case DocStyle.bullet:
    case DocStyle.numbered:
      return 16;
    case DocStyle.quote:
      return 20;
    default:
      return 0;
  }
}

/// The text as it is drawn — the bullet is added here, not stored in the text,
/// so a block never ends up with two of them.
String docDisplayText(DocBlock block) =>
    block.style == DocStyle.bullet ? '•   ${block.text}' : block.text;

/// A heading with only this much room under it is left stranded, so it is
/// moved to the top of the next page instead.
const _orphanGuardPt = 54.0;

/// The strip at the foot of each page that holds the page number.
///
/// The paginator has to know about it: text measured against the full height
/// and then drawn above a footer would lose its last line off the bottom.
const docFooterPt = 18.0;

double _heightOf(String text, TextStyle style, double width) {
  if (text.isEmpty) return 0;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    // No maxLines: the whole paragraph is measured, however tall it runs.
  )..layout(maxWidth: width);
  return painter.height;
}

/// The longest prefix of [text] that fits in [maxHeight], ending on a word
/// boundary. Returns 0 when not even one word fits.
int _prefixThatFits(
  String text,
  TextStyle style,
  double width,
  double maxHeight,
) {
  if (maxHeight <= 0) return 0;
  if (_heightOf(text, style, width) <= maxHeight) return text.length;

  // Binary search on the cut point. Measuring every candidate length would be
  // O(n) layouts for a long paragraph; this is about a dozen.
  var low = 0;
  var high = text.length;
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    if (_heightOf(text.substring(0, mid), style, width) <= maxHeight) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  if (low <= 0) return 0;

  // Back up to a space so a word is not cut in half. If the "word" is longer
  // than the space left, the hard cut stands — a URL has to break somewhere.
  final cut = text.lastIndexOf(' ', low);
  return cut > 0 ? cut : low;
}

/// Splits [blocks] into pages that fit a sheet of A4.
///
/// [marginPt] must match the margin the page is drawn with, or the measuring
/// and the drawing disagree and the last line of each page is clipped.
List<List<DocBlock>> paginateBlocks(
  List<DocBlock> blocks, {
  double marginPt = 56,
}) {
  final width = PageRenderer.a4WidthPt - marginPt * 2;
  final height = PageRenderer.a4HeightPt - marginPt * 2 - docFooterPt;

  final pages = <List<DocBlock>>[];
  var current = <DocBlock>[];
  var used = 0.0;

  void endPage() {
    pages.add(current);
    current = <DocBlock>[];
    used = 0.0;
  }

  for (final block in blocks) {
    final style = docStyleFor(block.style);
    final spacing = docSpacingAfter(block.style);
    final columnWidth = width - docIndent(block.style);

    var text = docDisplayText(block);
    if (text.trim().isEmpty) continue;

    while (true) {
      final needed = _heightOf(text, style, columnWidth) + spacing;
      final available = height - used;

      if (needed <= available) {
        // A heading that lands right at the foot of the page takes its
        // section with it to the next one.
        final stranded =
            block.isHeading && available - needed < _orphanGuardPt;
        if (stranded && current.isNotEmpty) {
          endPage();
          continue;
        }
        current.add(DocBlock(block.style, text));
        used += needed;
        break;
      }

      // A heading is never cut in half; it moves whole.
      if (block.isHeading && current.isNotEmpty) {
        endPage();
        continue;
      }

      final fits = _prefixThatFits(text, style, columnWidth, available - spacing);

      if (fits <= 0) {
        if (current.isEmpty) {
          // Will not fit even on an empty page, so take a full page of it and
          // carry the rest over. Without this the loop would never end.
          final forced =
              _prefixThatFits(text, style, columnWidth, height - spacing);
          final take = forced > 0 ? forced : text.length;
          current.add(DocBlock(block.style, text.substring(0, take).trimRight()));
          text = text.substring(take).trimLeft();
          endPage();
          if (text.isEmpty) break;
          continue;
        }
        endPage();
        continue;
      }

      current.add(DocBlock(block.style, text.substring(0, fits).trimRight()));
      text = text.substring(fits).trimLeft();
      endPage();
      if (text.isEmpty) break;
    }
  }

  if (current.isNotEmpty) pages.add(current);
  if (pages.isEmpty) pages.add(const <DocBlock>[]);
  return pages;
}
