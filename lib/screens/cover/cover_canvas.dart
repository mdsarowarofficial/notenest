import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/page_renderer.dart';
import '../../models/cover_spec.dart';

/// The cover page as it will be printed.
///
/// This widget *is* the output — [PageRenderer] photographs it and the PDF
/// holds that picture. So nothing here may depend on the app's theme: a cover
/// page that inherited the app's paper grey and ink colours would print grey.
/// Every colour and size is stated outright, in points.
///
/// The four templates are four different arrangements rather than one
/// arrangement in four colours. A student picking a template should be
/// choosing a layout, not a hue — the colour is a separate control.
class CoverCanvas extends StatelessWidget {
  const CoverCanvas({super.key, required this.spec, this.logo});

  final CoverSpec spec;

  /// The university logo, as PNG bytes, or null if none has been picked.
  /// The same image serves as the corner mark and as the watermark.
  final Uint8List? logo;

  @override
  Widget build(BuildContext context) {
    final accent = Color(spec.accent);
    final mark = logo;

    // The sheet is captured as-is, so the text defaults are set here rather
    // than inherited. Height 1.25 keeps the stacked lines from touching.
    return PaperSheet(
      marginPt: spec.template == CoverTemplate.minimal ? 56 : 46,
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Color(0xFF111111),
          fontSize: 11,
          height: 1.25,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w400,
        ),
        child: Stack(
          children: [
            // Behind everything, so no text has to fight it for space.
            if (mark != null && spec.showWatermark)
              Positioned.fill(child: _Watermark(logo: mark)),
            Positioned.fill(
              child: Column(
                children: [
                  Expanded(
                    child: switch (spec.template) {
                      CoverTemplate.framed =>
                        _Framed(spec: spec, accent: accent, logo: mark),
                      CoverTemplate.classic =>
                        _Classic(spec: spec, accent: accent, logo: mark),
                      CoverTemplate.ruled => _Ruled(spec: spec, accent: accent),
                      CoverTemplate.crest =>
                        _Crest(spec: spec, accent: accent, logo: mark),
                      CoverTemplate.minimal =>
                        _Minimal(spec: spec, accent: accent, logo: mark),
                    },
                  ),
                  // A small, quiet credit at the foot of the page. It has its own
                  // row, so it can never sit on top of the layout above it.
                  const SizedBox(height: 6),
                  const Text(
                    'NoteNest',
                    style: TextStyle(
                      fontSize: 7,
                      height: 1,
                      letterSpacing: 0.8,
                      color: Color(0xFF8A8A8A),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- type scale

const _institution = TextStyle(
  fontSize: 17,
  height: 1.2,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.1,
  color: Color(0xFF111111),
);

const _department = TextStyle(
  fontSize: 11,
  height: 1.3,
  letterSpacing: 0.4,
  color: Color(0xFF3A3A3A),
);

const _kindHeading = TextStyle(
  fontSize: 29,
  height: 1.1,
  fontWeight: FontWeight.w800,
  letterSpacing: 2.4,
  color: Color(0xFF111111),
);

const _title = TextStyle(
  fontSize: 15,
  height: 1.4,
  fontWeight: FontWeight.w500,
  color: Color(0xFF111111),
);

const _course = TextStyle(
  fontSize: 12,
  height: 1.35,
  color: Color(0xFF2A2A2A),
);

const _rowLabel = TextStyle(
  fontSize: 8,
  height: 1.2,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.3,
  color: Color(0xFF6A6A6A),
);

const _rowValue = TextStyle(
  fontSize: 10.5,
  height: 1.35,
  color: Color(0xFF111111),
);

const _blockTitle = TextStyle(
  fontSize: 9,
  height: 1.2,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.6,
  color: Color(0xFF111111),
);

const _dateStyle = TextStyle(
  fontSize: 10,
  height: 1.3,
  color: Color(0xFF3A3A3A),
);

// ------------------------------------------------------------ shared pieces

/// One "Submitted by" / "Submitted to" block.
class _PersonBlock extends StatelessWidget {
  const _PersonBlock({
    required this.heading,
    required this.rows,
    required this.accent,
    this.align = CrossAxisAlignment.start,
    this.showRule = true,
  });

  final String heading;
  final List<CoverRow> rows;
  final Color accent;
  final CrossAxisAlignment align;
  final bool showRule;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final centred = align == CrossAxisAlignment.center;

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(heading.toUpperCase(), style: _blockTitle),
        if (showRule) ...[
          const SizedBox(height: 4),
          Container(width: 34, height: 1.6, color: accent),
        ],
        const SizedBox(height: 8),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Column(
              crossAxisAlignment: align,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(row.label.toUpperCase(), style: _rowLabel),
                Text(
                  row.value,
                  style: _rowValue,
                  textAlign: centred ? TextAlign.center : TextAlign.start,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The institution, department and course, which every template opens with.
class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.spec,
    this.centred = true,
  });

  final CoverSpec spec;
  final bool centred;

  @override
  Widget build(BuildContext context) {
    final align = centred ? TextAlign.center : TextAlign.start;
    final cross =
        centred ? CrossAxisAlignment.center : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: cross,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (spec.institution.trim().isNotEmpty)
          Text(
            spec.institution.trim().toUpperCase(),
            style: _institution,
            textAlign: align,
            // The sheet is a fixed height and gets photographed. A long name
            // that overflowed would print Flutter's overflow stripe into the
            // PDF, so every field the student types into is bounded.
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        if (spec.department.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            spec.department.trim(),
            style: _department,
            textAlign: align,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (spec.courseLine.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            spec.courseLine,
            style: _course,
            textAlign: align,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

Widget _dateLine(CoverSpec spec, {TextAlign align = TextAlign.center}) {
  final on = spec.submittedOn;
  if (on == null) return const SizedBox.shrink();
  return Text(
    'Date of submission: ${coverDateLabel(on)}',
    style: _dateStyle,
    textAlign: align,
  );
}

// ------------------------------------------------------------------ classic

/// Centred, with a double rule over the heading and the two blocks side by
/// side at the foot. The arrangement most departments in Bangladesh hand out
/// as the expected one.
class _Classic extends StatelessWidget {
  const _Classic({required this.spec, required this.accent, this.logo});

  final CoverSpec spec;
  final Color accent;
  final Uint8List? logo;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        if (logo != null) ...[
          SizedBox(height: 52, child: Image.memory(logo!, fit: BoxFit.contain)),
          const SizedBox(height: 12),
        ],
        _Masthead(spec: spec),
        const Spacer(flex: 2),
        Container(width: double.infinity, height: 2.2, color: accent),
        const SizedBox(height: 3),
        Container(width: double.infinity, height: 0.8, color: accent),
        const SizedBox(height: 18),
        Text(spec.kind.heading,
            style: _kindHeading, textAlign: TextAlign.center),
        if (spec.serialLine != null) ...[
          const SizedBox(height: 8),
          Text(spec.serialLine!, style: _course, textAlign: TextAlign.center),
        ],
        if (spec.title.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(spec.title.trim(),
              style: _title,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 18),
        Container(width: 90, height: 0.8, color: const Color(0xFF9A9A9A)),
        const Spacer(flex: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PersonBlock(
                heading: 'Submitted by',
                rows: spec.submittedBy,
                accent: accent,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _PersonBlock(
                heading: 'Submitted to',
                rows: spec.submittedTo,
                accent: accent,
              ),
            ),
          ],
        ),
        const Spacer(),
        _dateLine(spec),
      ],
    );

    if (!spec.showBorder) return body;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: accent, width: 1.2),
      ),
      child: body,
    );
  }
}

// -------------------------------------------------------------------- ruled

/// Notebook rules behind the text, and a highlighter swipe under the heading.
/// The app's own visual language, carried onto paper.
class _Ruled extends StatelessWidget {
  const _Ruled({required this.spec, required this.accent});

  final CoverSpec spec;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _RulesPainter(accent: accent)),
        ),
        Positioned.fill(
          child: Padding(
            // Clear of the margin rule the painter draws down the left.
            padding: const EdgeInsets.only(left: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                _Masthead(spec: spec, centred: false),
                const Spacer(flex: 2),
                // The swipe sits behind the word, as a highlighter would.
                Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 4,
                      child: Container(
                        height: 17,
                        color: const Color(0xFFFFE45E),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(spec.kind.heading, style: _kindHeading),
                    ),
                  ],
                ),
                if (spec.serialLine != null) ...[
                  const SizedBox(height: 10),
                  Text(spec.serialLine!, style: _course),
                ],
                if (spec.title.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(spec.title.trim(),
                      style: _title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis),
                ],
                const Spacer(flex: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _PersonBlock(
                        heading: 'Submitted by',
                        rows: spec.submittedBy,
                        accent: accent,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: _PersonBlock(
                        heading: 'Submitted to',
                        rows: spec.submittedTo,
                        accent: accent,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _dateLine(spec, align: TextAlign.start),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RulesPainter extends CustomPainter {
  const _RulesPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()
      ..color = const Color(0xFFE3E7EE)
      ..strokeWidth = 0.7;

    // 22pt apart, which is a schoolbook line.
    for (var y = 34.0; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
    }

    final margin = Paint()
      ..color = accent.withAlpha(115)
      ..strokeWidth = 1.1;
    canvas.drawLine(const Offset(14, 0), Offset(14, size.height), margin);
  }

  @override
  bool shouldRepaint(_RulesPainter old) => old.accent != accent;
}

// -------------------------------------------------------------------- crest

/// A drawn seal at the top with everything stacked beneath it. Formal, and the
/// closest of the four to a thesis cover.
class _Crest extends StatelessWidget {
  const _Crest({required this.spec, required this.accent, this.logo});

  final CoverSpec spec;
  final Color accent;
  final Uint8List? logo;

  /// Up to three letters taken from the institution name — "DIU" from
  /// "Daffodil International University". An empty name leaves the seal blank
  /// rather than inventing initials.
  String get _initials {
    final words = spec.institution
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();
    if (words.isEmpty) return '';
    return words.take(3).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 6),
        if (logo != null)
          SizedBox(
            height: 86,
            child: Image.memory(logo!, fit: BoxFit.contain),
          )
        else
          SizedBox(
            width: 86,
            height: 86,
            child: CustomPaint(
              painter: _SealPainter(accent: accent),
              child: Center(
                child: Text(
                  _initials,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: accent,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 18),
        _Masthead(spec: spec),
        const Spacer(flex: 2),
        Text(spec.kind.heading,
            style: _kindHeading, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Container(width: 54, height: 2, color: accent),
        if (spec.serialLine != null) ...[
          const SizedBox(height: 12),
          Text(spec.serialLine!, style: _course, textAlign: TextAlign.center),
        ],
        if (spec.title.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(spec.title.trim(),
              style: _title,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis),
        ],
        const Spacer(flex: 3),
        _PersonBlock(
          heading: 'Submitted by',
          rows: spec.submittedBy,
          accent: accent,
          align: CrossAxisAlignment.center,
        ),
        const SizedBox(height: 20),
        _PersonBlock(
          heading: 'Submitted to',
          rows: spec.submittedTo,
          accent: accent,
          align: CrossAxisAlignment.center,
        ),
        const Spacer(),
        _dateLine(spec),
      ],
    );
  }
}

class _SealPainter extends CustomPainter {
  const _SealPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2;

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = accent;
    canvas.drawCircle(centre, outer - 1, ring);

    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = accent.withAlpha(140);
    canvas.drawCircle(centre, outer - 7, inner);

    // Twelve small marks around the rim, the way a stamped seal is toothed.
    final tooth = Paint()..color = accent.withAlpha(191);
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      final r = outer - 4;
      canvas.drawCircle(
        centre + Offset(math.cos(angle) * r, math.sin(angle) * r),
        1.1,
        tooth,
      );
    }
  }

  @override
  bool shouldRepaint(_SealPainter old) => old.accent != accent;
}

// ------------------------------------------------------------------ minimal

/// Left-aligned, one rule, a great deal of air. For a department that does not
/// hand out a template and will not mind a modern one.
class _Minimal extends StatelessWidget {
  const _Minimal({required this.spec, required this.accent, this.logo});

  final CoverSpec spec;
  final Color accent;
  final Uint8List? logo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 20, height: 3, color: accent),
            const SizedBox(width: 8),
            Text(
              spec.kind.label.toUpperCase(),
              style: _rowLabel.copyWith(color: accent, fontSize: 9),
            ),
            const Spacer(),
            if (logo != null)
              SizedBox(
                height: 40,
                child: Image.memory(logo!, fit: BoxFit.contain),
              ),
          ],
        ),
        const Spacer(flex: 2),
        if (spec.title.trim().isNotEmpty)
          Text(
            spec.title.trim(),
            style: const TextStyle(
              fontSize: 26,
              height: 1.25,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: Color(0xFF111111),
            ),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
        if (spec.serialLine != null) ...[
          const SizedBox(height: 10),
          Text(spec.serialLine!, style: _course),
        ],
        const SizedBox(height: 22),
        Container(width: double.infinity, height: 0.9, color: accent),
        const SizedBox(height: 14),
        _Masthead(spec: spec, centred: false),
        const Spacer(flex: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PersonBlock(
                heading: 'Submitted by',
                rows: spec.submittedBy,
                accent: accent,
                showRule: false,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _PersonBlock(
                heading: 'Submitted to',
                rows: spec.submittedTo,
                accent: accent,
                showRule: false,
              ),
            ),
          ],
        ),
        const Spacer(),
        _dateLine(spec, align: TextAlign.start),
      ],
    );
  }
}

// ------------------------------------------------------------------- framed

/// The default template: a ruled border, the logo in the corner, the details
/// in panels, and two signature blocks at the foot.
///
/// Almost everything here is driven by [CoverSpec] rather than fixed, because
/// a cover page with four filled fields and one with twelve want different
/// spacing. [CoverDensity.scale] multiplies every gap, so the same layout can
/// be tightened until the page is full or opened out until it breathes,
/// without a second template to maintain.
class _Framed extends StatelessWidget {
  const _Framed({required this.spec, required this.accent, this.logo});

  final CoverSpec spec;
  final Color accent;
  final Uint8List? logo;

  @override
  Widget build(BuildContext context) {
    final mark = logo;
    final g = spec.density.scale;

    return Stack(
      children: [
        if (spec.showBorder && spec.frameStyle != FrameStyle.none)
          Positioned.fill(
            child: CustomPaint(
              painter: _FramePainter(accent: accent, style: spec.frameStyle),
            ),
          ),
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(22, 18 * g, 22, 16 * g),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The logo sits over the masthead rather than above it. Giving
                // it a row of its own cost about fifty points of height and
                // left a band of nothing across the top of every page.
                Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: mark == null ? 0 : 6 * g),
                      child: Column(
                        children: [
                          if (spec.institution.trim().isNotEmpty)
                            Text(
                              spec.institution.trim(),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 25,
                                height: 1.12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                                color: accent,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          if (spec.department.trim().isNotEmpty) ...[
                            SizedBox(height: 6 * g),
                            Text(
                              spec.department.trim(),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _department.copyWith(fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (mark != null)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: SizedBox(
                          height: 48,
                          width: 86,
                          child: Image.memory(mark, fit: BoxFit.contain),
                        ),
                      ),
                  ],
                ),

                SizedBox(height: 13 * g),
                _Rule(accent: accent),
                SizedBox(height: 13 * g),

                _Panel(
                  accent: accent,
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12 * g,
                  ),
                  child: Column(
                    children: [
                      Text(
                        spec.kind.heading,
                        textAlign: TextAlign.center,
                        style: _kindHeading.copyWith(
                          fontSize: 25,
                          color: accent,
                        ),
                      ),
                      SizedBox(height: 6 * g),
                      Container(width: 118, height: 1, color: accent),
                      if (spec.courseCode.trim().isNotEmpty ||
                          spec.courseTitle.trim().isNotEmpty) ...[
                        SizedBox(height: 10 * g),
                        if (spec.courseCode.trim().isNotEmpty)
                          _Line('Course Code', spec.courseCode.trim()),
                        if (spec.courseTitle.trim().isNotEmpty) ...[
                          SizedBox(height: 4 * g),
                          _Line('Course Title', spec.courseTitle.trim()),
                        ],
                      ],
                    ],
                  ),
                ),

                if (spec.serialLine != null ||
                    spec.title.trim().isNotEmpty) ...[
                  SizedBox(height: 8 * g),
                  _Panel(
                    accent: accent,
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11 * g,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (spec.serialLine != null)
                          _Line(
                            spec.kind.serialLabel!,
                            spec.serial.trim(),
                            alignLeft: true,
                          ),
                        if (spec.title.trim().isNotEmpty) ...[
                          if (spec.serialLine != null) SizedBox(height: 4 * g),
                          _Line(
                            spec.kind.titleLabel,
                            spec.title.trim(),
                            alignLeft: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                SizedBox(height: 13 * g),
                _Rule(accent: accent),

                // One flexible gap above the signatures and a smaller one
                // below, so the blocks settle into the lower third rather than
                // floating in the middle of an empty page.
                const Spacer(flex: 5),
                _Signatures(spec: spec, accent: accent, gap: g),
                const Spacer(flex: 4),

                _Rule(accent: accent),
                SizedBox(height: 10 * g),
                if (spec.submittedOn != null)
                  Text(
                    'Submission date: ${coverDateLabel(spec.submittedOn!)}',
                    textAlign: TextAlign.center,
                    style: _dateStyle.copyWith(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The two signature blocks, in whichever arrangement was chosen.
///
/// Stepped is the default because it is what the faculty templates here use:
/// the eye reads down and to the right, and the step follows it. Level and
/// stacked are there because that is a convention, not a law, and a student
/// whose department wants them square should not have to argue with the app.
class _Signatures extends StatelessWidget {
  const _Signatures({
    required this.spec,
    required this.accent,
    required this.gap,
  });

  final CoverSpec spec;
  final Color accent;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final to = _SignatureBlock(
      heading: 'Submitted to',
      rows: spec.submittedTo,
      accent: accent,
      gap: gap,
    );
    final by = _SignatureBlock(
      heading: 'Submitted by',
      rows: spec.submittedBy,
      accent: accent,
      gap: gap,
    );

    switch (spec.signatureStyle) {
      case SignatureStyle.stacked:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [to, SizedBox(height: 10 * gap), by],
        );

      case SignatureStyle.level:
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: to),
              const SizedBox(width: 14),
              Expanded(child: by),
            ],
          ),
        );

      case SignatureStyle.staggered:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: to),
            const SizedBox(width: 14),
            Expanded(
              // The step. Big enough to read as deliberate, small enough that
              // the two still belong to the same band of the page.
              child: Padding(
                padding: EdgeInsets.only(top: 30 * gap),
                child: by,
              ),
            ),
          ],
        );
    }
  }
}

/// "Course Code: CSE 112" — the label in grey, the answer in ink.
class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.alignLeft = false});

  final String label;
  final String value;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment:
          alignLeft ? MainAxisAlignment.start : MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$label: ',
            style: _course.copyWith(color: const Color(0xFF5A5A5A))),
        Flexible(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _course.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// A rounded panel with a hairline border in the accent colour.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    required this.accent,
    required this.padding,
  });

  final Widget child;
  final Color accent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: accent.withAlpha(150), width: 1),
      ),
      child: child,
    );
  }
}

/// "SUBMITTED TO" and its rows, in a panel of its own.
class _SignatureBlock extends StatelessWidget {
  const _SignatureBlock({
    required this.heading,
    required this.rows,
    required this.accent,
    this.gap = 1,
  });

  final String heading;
  final List<CoverRow> rows;
  final Color accent;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    // The first row is the person; the rest describe them. Setting the name
    // larger means a marker finds their own name without reading a label.
    final first = rows.first;
    final rest = rows.skip(1);

    return Container(
      padding: EdgeInsets.fromLTRB(14, 11 * gap, 12, 12 * gap),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: accent.withAlpha(110), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            heading.toUpperCase(),
            style: _blockTitle.copyWith(color: accent, fontSize: 8.5),
          ),
          SizedBox(height: 5 * gap),
          Container(height: 1, color: accent.withAlpha(90)),
          SizedBox(height: 8 * gap),
          Text(
            first.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111111),
              decoration: TextDecoration.none,
            ),
          ),
          for (final row in rest) ...[
            SizedBox(height: 3 * gap),
            Text(
              '${row.label}: ${row.value}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                height: 1.3,
                color: Color(0xFF3A3A3A),
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A hairline with a small diamond at its centre.
class _Rule extends StatelessWidget {
  const _Rule({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 0.8, color: accent.withAlpha(90))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(width: 5, height: 5, color: accent),
          ),
        ),
        Expanded(child: Container(height: 0.8, color: accent.withAlpha(90))),
      ],
    );
  }
}

/// The logo again, large and faint, behind the page.
class _Watermark extends StatelessWidget {
  const _Watermark({required this.logo});

  final Uint8List logo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.68,
        child: Opacity(
          // Faint enough that text stays comfortably readable over it, which
          // on a laser printer means staying under about eight per cent.
          opacity: 0.07,
          child: Image.memory(logo, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// The border round the page, in whichever style was chosen.
class _FramePainter extends CustomPainter {
  const _FramePainter({required this.accent, required this.style});

  final Color accent;
  final FrameStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = accent;

    final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(3, 3, size.width - 6, size.height - 6),
      const Radius.circular(6),
    );

    switch (style) {
      case FrameStyle.none:
        return;

      case FrameStyle.hairline:
        canvas.drawRRect(outer, stroke..strokeWidth = 0.9);

      case FrameStyle.double:
        canvas.drawRRect(outer, stroke);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(9, 9, size.width - 18, size.height - 18),
            const Radius.circular(4),
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6
            ..color = accent.withAlpha(170),
        );

      case FrameStyle.dotted:
        canvas.drawRRect(outer, stroke);
        _dots(
          canvas,
          Rect.fromLTWH(9, 9, size.width - 18, size.height - 18),
          accent,
        );

      case FrameStyle.corners:
        // Four brackets instead of a closed frame. Lighter on the page, and
        // it does not fight a logo that sits near the edge.
        const arm = 46.0;
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = accent;
        final r = Rect.fromLTWH(6, 6, size.width - 12, size.height - 12);
        for (final corner in [
          (r.topLeft, 1.0, 1.0),
          (r.topRight, -1.0, 1.0),
          (r.bottomLeft, 1.0, -1.0),
          (r.bottomRight, -1.0, -1.0),
        ]) {
          final (origin, dx, dy) = corner;
          canvas.drawLine(origin, origin.translate(arm * dx, 0), p);
          canvas.drawLine(origin, origin.translate(0, arm * dy), p);
        }
    }
  }

  /// Dots walked along the path rather than a dashed stroke, which Flutter
  /// has not got — and walking keeps the spacing even round the corners.
  void _dots(Canvas canvas, Rect rect, Color color) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));
    final dot = Paint()..color = color;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 5.5) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent != null) canvas.drawCircle(tangent.position, 0.85, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.accent != accent || old.style != style;
}
