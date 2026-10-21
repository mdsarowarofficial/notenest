import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/nest_theme.dart';

/// A hand-drawn highlighter swipe behind its child.
///
/// This is the signature mark of NoteNest: anything the app considers "current"
/// is highlighted the way a student highlights a line in a book — slightly
/// crooked, slightly over the edges, never a neat rectangle.
class Highlighted extends StatelessWidget {
  const Highlighted({
    super.key,
    required this.child,
    this.active = true,
    this.color,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;
  final bool active;
  final Color? color;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: duration,
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: active ? 1 : 0),
      builder: (context, t, child) {
        return CustomPaint(
          painter: _SwipePainter(t, color ?? NestColor.highlight),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: child,
      ),
    );
  }
}

class _SwipePainter extends CustomPainter {
  _SwipePainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final w = size.width * t;
    final paint = Paint()..color = NestColor.o(color, 0.9);

    // Uneven corners + a slight tilt read as a marker stroke, not a chip.
    final rect = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, size.height * 0.16, w, size.height * 0.78),
      topLeft: const Radius.circular(9),
      bottomLeft: const Radius.circular(4),
      topRight: const Radius.circular(3),
      bottomRight: const Radius.circular(8),
    );

    canvas.save();
    canvas.translate(0, size.height * 0.06);
    canvas.rotate(-0.012);
    canvas.drawRRect(rect, paint);
    // Second lighter pass, as if the marker overlapped itself.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * 0.5, w * 0.94, size.height * 0.3),
        const Radius.circular(5),
      ),
      Paint()..color = NestColor.o(color, 0.55),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SwipePainter old) => old.t != t || old.color != color;
}

/// The inked progress rail used by [NestStepper].
///
/// Steps that are not reached yet are a dotted pencil guide; everything the
/// student has completed is drawn as a slightly wobbly pen stroke.
class PenRailPainter extends CustomPainter {
  PenRailPainter({
    required this.count,
    required this.progress,
    required this.centerY,
  });

  final int count;
  final double progress; // 0 .. count-1
  final double centerY;

  double _x(Size size, int i) => size.width * (i + 0.5) / count;

  @override
  void paint(Canvas canvas, Size size) {
    if (count < 2) return;
    final start = _x(size, 0);
    final end = _x(size, count - 1);

    // Dotted guide.
    final guide = Paint()
      ..color = NestColor.rule
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const dash = 5.0, gap = 6.0;
    for (double x = start; x < end; x += dash + gap) {
      canvas.drawLine(
        Offset(x, centerY),
        Offset(math.min(x + dash, end), centerY),
        guide,
      );
    }

    // Inked part.
    final inkedTo = start + (end - start) * (progress / (count - 1));
    if (inkedTo <= start + 0.5) return;

    final path = Path()..moveTo(start, centerY);
    for (double x = start; x <= inkedTo; x += 4) {
      path.lineTo(x, centerY + math.sin(x / 18) * 0.9);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = NestColor.pen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(PenRailPainter old) =>
      old.progress != progress || old.count != count;
}

/// Spiral binding drawn down the edge of the drawer.
///
/// The wire is drawn as a diagonal loop crossing the strip, which is how a
/// spiral notebook actually looks from the front. Drawing each ring as a
/// circle facing the reader instead makes a column of part-drawn circles that
/// reads as a row of loading spinners.
class SpiralEdgePainter extends CustomPainter {
  const SpiralEdgePainter({this.spacing = 30, this.top = 34});

  final double spacing;
  final double top;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final hole = Paint()..color = NestColor.o(NestColor.ink, 0.13);
    final wire = Paint()
      ..color = NestColor.o(NestColor.ink, 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final shine = Paint()
      ..color = NestColor.o(Colors.white, 0.70)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final reach = size.width / 2 + 1;

    for (double y = top; y < size.height - 12; y += spacing) {
      // The punched hole the wire passes through.
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, y), width: 8, height: 6),
        hole,
      );
      // The wire crossing the binding strip.
      canvas.drawLine(
        Offset(cx - reach, y + 9),
        Offset(cx + reach, y - 9),
        wire,
      );
      canvas.drawLine(
        Offset(cx - reach + 3, y + 6),
        Offset(cx + reach - 3, y - 6),
        shine,
      );
    }
  }

  @override
  bool shouldRepaint(SpiralEdgePainter old) => false;
}

/// A thin ruled line, used to separate blocks without a heavy divider.
class PaperRule extends StatelessWidget {
  const PaperRule({super.key, this.indent = 0});
  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: indent),
        child: Container(height: 1, color: NestColor.rule),
      );
}
