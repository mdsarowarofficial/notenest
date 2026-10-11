import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/nest_theme.dart';

/// The exam dial: days left in the middle, revision progress around the edge.
///
/// Two numbers that only mean something together. "Six days" is not worrying
/// on its own, and "40% mastered" is not either; the pair is the whole point,
/// so they are drawn as one object rather than two statistics in a row.
class NestCountdownRing extends StatelessWidget {
  const NestCountdownRing({
    super.key,
    required this.days,
    required this.progress,
    this.diameter = 96,
    this.accent = NestColor.pen,
  });

  /// Whole days until the exam. Negative once it has passed.
  final int days;

  /// Share of the notes marked Mastered, 0..1.
  final double progress;

  final double diameter;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final target = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);

    final figure = days == 0 ? '' : '${days.abs()}';
    final label = days < 0
        ? 'AGO'
        : days == 0
            ? 'TODAY'
            : days == 1
                ? 'DAY'
                : 'DAYS';

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => SizedBox(
        width: diameter,
        height: diameter,
        child: CustomPaint(
          painter: _RingPainter(progress: value, accent: accent),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (figure.isNotEmpty)
                  Text(
                    figure,
                    style: TextStyle(
                      fontFamily: NestFont.display,
                      fontSize: diameter * 0.32,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                      color: NestColor.ink,
                    ),
                  ),
                Text(
                  label,
                  style: nestEyebrow.copyWith(
                    fontSize: 9,
                    color: days < 0 ? NestColor.inkFaint : NestColor.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height)
        .deflate(stroke / 2 + 1);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = NestColor.rule;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);

    if (progress <= 0) return;

    // The highlighter underlay, then the pen on top of it — the same two-layer
    // trick the rest of the app uses for anything marked as done.
    final wash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 5
      ..strokeCap = StrokeCap.round
      ..color = NestColor.o(NestColor.highlight, 0.55);
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = accent;

    final sweep = 2 * math.pi * progress;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, wash);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, ink);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.accent != accent;
}
