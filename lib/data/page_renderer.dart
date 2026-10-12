import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Turns what is on screen into the pixels that go into a PDF.
///
/// **Why a picture, and not text in the PDF.** The obvious way to make a PDF
/// is to let the `pdf` package draw the text. That works for English and
/// fails for Bengali: the package has no OpenType shaping engine, so it draws
/// each code point as its own glyph. Bengali needs conjuncts formed and
/// vowel signs reordered, and without shaping a word like "বিশ্ববিদ্যালয়"
/// comes out as disconnected pieces in the wrong order. The package's own
/// issue tracker has said so for years.
///
/// Flutter's text engine does shape text properly — it is the same engine
/// drawing the Bengali on screen correctly right now. So the page is drawn as
/// a Flutter widget, captured at print resolution, and the image is what goes
/// into the PDF.
///
/// The cost is stated plainly in the documentation: the text in the exported
/// PDF cannot be selected or searched, and the file is larger. For a cover
/// page that is the right trade. For a converted document it is the only way
/// the Bengali survives at all.
class PageRenderer {
  PageRenderer._();

  /// A4 in PostScript points, which is what a PDF measures in: 210mm × 297mm
  /// at 72 points to the inch.
  static const a4WidthPt = 595.28;
  static const a4HeightPt = 841.89;

  static const a4Ratio = a4WidthPt / a4HeightPt;

  /// Print resolution. 200 is the lowest that still looks clean on paper
  /// rather than soft; 300 doubles the file for a difference most printers
  /// will not show.
  static const defaultDpi = 200.0;

  /// Captures a [RepaintBoundary] as a PNG sized for A4 at [dpi].
  ///
  /// The boundary must be on screen and painted. An off-screen widget has no
  /// layer to capture, which is why the export screen shows each page as it
  /// renders it rather than working invisibly.
  static Future<Uint8List> capture(
    GlobalKey boundaryKey, {
    double dpi = defaultDpi,
  }) async {
    // Let the frame that holds this page finish before reading it back.
    await WidgetsBinding.instance.endOfFrame;

    final object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) {
      throw StateError('The page to capture is not on screen.');
    }

    // Still being painted, which happens when a capture is asked for in the
    // same frame the page was added. One more frame settles it.
    if (object.debugNeedsPaint) {
      await WidgetsBinding.instance.endOfFrame;
    }

    final logicalWidth = object.size.width;
    if (logicalWidth <= 0) {
      throw StateError('The page to capture has no size.');
    }

    // The preview on screen is whatever width fits the phone. Scaling by the
    // ratio of wanted pixels to logical pixels means the exported file is the
    // same resolution whichever device made it.
    final wantedPixels = a4WidthPt / 72.0 * dpi;
    final pixelRatio = wantedPixels / logicalWidth;

    final image = await object.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('The page could not be encoded.');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}

/// A sheet of A4, drawn to whatever width it is given.
///
/// Everything inside is laid out in points and then scaled as one, so the
/// preview on a phone and the captured page differ only in resolution. Padding
/// a page in logical pixels instead would make the margins change with the
/// screen.
class PaperSheet extends StatelessWidget {
  const PaperSheet({
    super.key,
    required this.child,
    this.marginPt = 48,
    this.background = const Color(0xFFFFFFFF),
  });

  final Widget child;

  /// The page margin in points. 48pt is about 17mm.
  final double marginPt;

  final Color background;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: PageRenderer.a4Ratio,
      child: Container(
        color: background,
        // One scale for the whole sheet, applied by FittedBox. Everything
        // below can then be written in points and never think about the
        // screen it landed on.
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: PageRenderer.a4WidthPt,
            height: PageRenderer.a4HeightPt,
            child: Padding(
              padding: EdgeInsets.all(marginPt),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
