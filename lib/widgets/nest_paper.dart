import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/nest_theme.dart';

/// The stationery that drifts behind the entrance screens.
enum Stationery { pen, pencil, diary, book, sticky, clip, highlighter, ruler }

/// A soft wash of colour with study tools floating slowly across it.
///
/// The objects drift and turn on long, uneven cycles so the motion never
/// repeats visibly. A pale scrim sits over them, so the form in front stays
/// easy to read no matter which object floats behind it.
class PaperBackground extends StatefulWidget {
  const PaperBackground({super.key, required this.child});

  final Widget child;

  @override
  State<PaperBackground> createState() => _PaperBackgroundState();
}

class _PaperBackgroundState extends State<PaperBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  /// x and y are fractions of the screen, so the layout holds on any size.
  static const _items = <_FloatingSpec>[
    _FloatingSpec(Stationery.pen, 0.10, 0.13, 78, 0.00, -0.35),
    _FloatingSpec(Stationery.diary, 0.82, 0.09, 96, 0.22, 0.28),
    _FloatingSpec(Stationery.pencil, 0.88, 0.34, 74, 0.48, 0.55),
    _FloatingSpec(Stationery.sticky, 0.07, 0.42, 66, 0.65, -0.18),
    _FloatingSpec(Stationery.book, 0.16, 0.74, 92, 0.35, 0.22),
    _FloatingSpec(Stationery.highlighter, 0.86, 0.68, 72, 0.80, -0.42),
    _FloatingSpec(Stationery.clip, 0.30, 0.06, 54, 0.55, 0.40),
    _FloatingSpec(Stationery.ruler, 0.72, 0.90, 88, 0.12, -0.25),
    _FloatingSpec(Stationery.pen, 0.45, 0.93, 62, 0.70, 0.62),
    _FloatingSpec(Stationery.sticky, 0.93, 0.52, 52, 0.05, 0.33),
  ];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Colour wash.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  NestColor.o(NestColor.tabs[3], 0.16),
                  NestColor.paper,
                  NestColor.o(NestColor.tabs[1], 0.14),
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
        ),

        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) => AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Stack(
                children: [
                  for (final spec in _items)
                    _FloatingObject(spec: spec, box: box, t: _c.value),
                ],
              ),
            ),
          ),
        ),

        // Keeps every object quiet enough to read over.
        Positioned.fill(
          child: ColoredBox(color: NestColor.o(Colors.white, 0.34)),
        ),

        widget.child,
      ],
    );
  }
}

class _FloatingSpec {
  const _FloatingSpec(
    this.kind,
    this.x,
    this.y,
    this.size,
    this.phase,
    this.tilt,
  );

  final Stationery kind;
  final double x;
  final double y;
  final double size;

  /// Offsets this object's cycle so nothing moves in step with anything else.
  final double phase;

  /// Resting angle in radians.
  final double tilt;
}

class _FloatingObject extends StatelessWidget {
  const _FloatingObject({
    required this.spec,
    required this.box,
    required this.t,
  });

  final _FloatingSpec spec;
  final BoxConstraints box;
  final double t;

  @override
  Widget build(BuildContext context) {
    final cycle = (t + spec.phase) * 2 * math.pi;

    // Horizontal and vertical drift run at different rates, so the path is a
    // slow open loop rather than a circle.
    final dx = math.cos(cycle * 0.7) * 16;
    final dy = math.sin(cycle) * 22;
    final spin = spec.tilt + math.sin(cycle * 0.55) * 0.16;

    return Positioned(
      left: box.maxWidth * spec.x - spec.size / 2 + dx,
      top: box.maxHeight * spec.y - spec.size / 2 + dy,
      child: Transform.rotate(
        angle: spin,
        child: Opacity(
          opacity: 0.85,
          child: CustomPaint(
            size: Size(spec.size, spec.size),
            painter: StationeryPainter(spec.kind),
          ),
        ),
      ),
    );
  }
}

/// Draws one study tool inside a square box.
///
/// Everything is built from plain shapes in the app's own palette, so the
/// background belongs to the same world as the rest of the interface.
class StationeryPainter extends CustomPainter {
  const StationeryPainter(this.kind);

  final Stationery kind;

  @override
  void paint(Canvas canvas, Size size) {
    // All shapes are drawn on a 100 x 100 grid, then scaled to fit.
    canvas.scale(size.width / 100, size.height / 100);

    switch (kind) {
      case Stationery.pen:
        _pen(canvas);
      case Stationery.pencil:
        _pencil(canvas);
      case Stationery.diary:
        _diary(canvas);
      case Stationery.book:
        _book(canvas);
      case Stationery.sticky:
        _sticky(canvas);
      case Stationery.clip:
        _clip(canvas);
      case Stationery.highlighter:
        _highlighter(canvas);
      case Stationery.ruler:
        _ruler(canvas);
    }
  }

  Paint _fill(Color c) => Paint()..color = c;

  RRect _r(double l, double t, double w, double h, double radius) =>
      RRect.fromRectAndRadius(
        Rect.fromLTWH(l, t, w, h),
        Radius.circular(radius),
      );

  void _pen(Canvas canvas) {
    // Nib.
    final nib = Path()
      ..moveTo(50, 98)
      ..lineTo(39, 74)
      ..lineTo(61, 74)
      ..close();
    canvas.drawPath(nib, _fill(NestColor.penDeep));
    canvas.drawCircle(const Offset(50, 92), 2.6, _fill(NestColor.ink));

    canvas.drawRRect(_r(39, 22, 22, 54, 5), _fill(NestColor.pen));
    canvas.drawRRect(_r(37, 8, 26, 18, 8), _fill(NestColor.penDeep));
    canvas.drawRRect(_r(61, 14, 5, 22, 2.5), _fill(NestColor.penDeep));
    canvas.drawRRect(
      _r(43, 32, 4, 30, 2),
      _fill(NestColor.o(Colors.white, 0.35)),
    );
  }

  void _pencil(Canvas canvas) {
    const wood = Color(0xFFE8C79A);

    final tip = Path()
      ..moveTo(50, 4)
      ..lineTo(37, 30)
      ..lineTo(63, 30)
      ..close();
    canvas.drawPath(tip, _fill(wood));

    final lead = Path()
      ..moveTo(50, 4)
      ..lineTo(45, 14)
      ..lineTo(55, 14)
      ..close();
    canvas.drawPath(lead, _fill(NestColor.ink));

    canvas.drawRect(
      const Rect.fromLTWH(37, 30, 26, 48),
      _fill(NestColor.tabs[5]),
    );
    canvas.drawRect(
      const Rect.fromLTWH(37, 30, 8, 48),
      _fill(NestColor.o(NestColor.ink, 0.10)),
    );
    canvas.drawRect(
      const Rect.fromLTWH(37, 78, 26, 8),
      _fill(const Color(0xFFB9BEC7)),
    );
    canvas.drawRRect(_r(37, 86, 26, 12, 4), _fill(NestColor.tabs[1]));
  }

  void _diary(Canvas canvas) {
    canvas.drawRRect(_r(18, 10, 64, 80, 7), _fill(NestColor.tabs[1]));
    canvas.drawRRect(_r(18, 10, 13, 80, 6), _fill(NestColor.redPen));

    // Ruled cover label.
    canvas.drawRRect(
      _r(38, 26, 34, 22, 3),
      _fill(NestColor.o(Colors.white, 0.75)),
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        _r(42, 31.0 + i * 6, 26, 2.4, 1.2),
        _fill(NestColor.o(NestColor.ink, 0.18)),
      );
    }

    // Elastic closure.
    canvas.drawRect(
      const Rect.fromLTWH(66, 10, 6, 80),
      _fill(NestColor.o(NestColor.ink, 0.35)),
    );
  }

  void _book(Canvas canvas) {
    canvas.drawRRect(_r(16, 14, 68, 72, 5), _fill(NestColor.tabs[2]));
    canvas.drawRRect(_r(26, 20, 56, 60, 3), _fill(Colors.white));
    canvas.drawRect(
      const Rect.fromLTWH(26, 20, 4, 60),
      _fill(NestColor.o(NestColor.ink, 0.12)),
    );
    for (var i = 0; i < 5; i++) {
      canvas.drawRRect(
        _r(36, 30.0 + i * 10, i.isEven ? 38 : 28, 3, 1.5),
        _fill(NestColor.o(NestColor.inkFaint, 0.55)),
      );
    }
  }

  void _sticky(Canvas canvas) {
    final body = Path()
      ..moveTo(14, 14)
      ..lineTo(86, 14)
      ..lineTo(86, 68)
      ..lineTo(66, 88)
      ..lineTo(14, 88)
      ..close();
    canvas.drawPath(body, _fill(NestColor.tabs[0]));

    // The curled corner.
    final fold = Path()
      ..moveTo(86, 68)
      ..lineTo(66, 88)
      ..lineTo(66, 68)
      ..close();
    canvas.drawPath(fold, _fill(NestColor.o(NestColor.ink, 0.16)));

    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        _r(26, 30.0 + i * 12, i == 2 ? 30 : 48, 3.4, 1.7),
        _fill(NestColor.o(NestColor.ink, 0.22)),
      );
    }
  }

  void _clip(Canvas canvas) {
    final wire = Paint()
      ..color = NestColor.tabs[3]
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(36, 84)
      ..lineTo(36, 26)
      ..arcToPoint(const Offset(64, 26), radius: const Radius.circular(14))
      ..lineTo(64, 74)
      ..arcToPoint(const Offset(46, 74),
          radius: const Radius.circular(9), clockwise: false)
      ..lineTo(46, 36);
    canvas.drawPath(path, wire);
  }

  void _highlighter(Canvas canvas) {
    // Chisel tip.
    final tip = Path()
      ..moveTo(34, 72)
      ..lineTo(66, 72)
      ..lineTo(60, 94)
      ..lineTo(40, 94)
      ..close();
    canvas.drawPath(tip, _fill(NestColor.o(NestColor.tabs[5], 0.9)));

    canvas.drawRRect(_r(32, 20, 36, 54, 8), _fill(NestColor.tabs[5]));
    canvas.drawRRect(_r(32, 62, 36, 10, 3), _fill(NestColor.o(NestColor.ink, 0.18)));
    canvas.drawRRect(_r(34, 10, 32, 14, 6), _fill(NestColor.o(NestColor.ink, 0.28)));
    canvas.drawRRect(
      _r(38, 30, 5, 26, 2.5),
      _fill(NestColor.o(Colors.white, 0.4)),
    );
  }

  void _ruler(Canvas canvas) {
    canvas.drawRRect(_r(8, 38, 84, 24, 4), _fill(NestColor.tabs[4]));
    canvas.drawRRect(
      _r(8, 38, 84, 8, 4),
      _fill(NestColor.o(Colors.white, 0.35)),
    );
    for (var i = 0; i < 8; i++) {
      final long = i.isEven;
      canvas.drawRect(
        Rect.fromLTWH(16.0 + i * 9, 38, 2.4, long ? 12 : 7),
        _fill(NestColor.o(NestColor.ink, 0.35)),
      );
    }
  }

  @override
  bool shouldRepaint(StationeryPainter old) => old.kind != kind;
}
