import 'package:flutter/material.dart';

import '../theme/nest_theme.dart';

/// The wordmark, highlighted by a pen that draws the stroke on arrival.
///
/// The highlighter swipe is the app's signature mark, so rather than fading it
/// in, a pen travels across the word and leaves the stroke behind, then lifts
/// away. It runs once. Repeating it would turn the brand into a distraction.
class PenWordmark extends StatefulWidget {
  const PenWordmark({
    super.key,
    required this.text,
    this.style,
    this.delay = const Duration(milliseconds: 250),
  });

  final String text;
  final TextStyle? style;
  final Duration delay;

  @override
  State<PenWordmark> createState() => _PenWordmarkState();
}

class _PenWordmarkState extends State<PenWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  /// How much of the stroke has been laid down.
  late final Animation<double> _stroke;

  /// The pen lifting off the page once the stroke is finished.
  late final Animation<double> _lift;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _stroke = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.62, curve: Curves.easeInOutCubic),
    );
    _lift = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.62, 1, curve: Curves.easeOut),
    );

    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ??
        Theme.of(context).textTheme.displaySmall ??
        const TextStyle(fontSize: 30);

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return CustomPaint(
          painter: _StrokePainter(_stroke.value),
          foregroundPainter: _PenPainter(
            progress: _stroke.value,
            lift: _lift.value,
          ),
          child: Padding(
            // Room for the pen to sit above the line while it writes.
            padding: const EdgeInsets.fromLTRB(6, 26, 26, 4),
            child: Text(widget.text, style: style),
          ),
        );
      },
    );
  }
}

/// The highlighter stroke growing left to right, drawn behind the text.
class _StrokePainter extends CustomPainter {
  _StrokePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;

    final top = size.height * 0.42;
    final height = size.height * 0.44;
    final width = (size.width - 26) * t;

    canvas.save();
    canvas.rotate(-0.012);

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(2, top, width, height),
        topLeft: const Radius.circular(9),
        bottomLeft: const Radius.circular(4),
        topRight: const Radius.circular(3),
        bottomRight: const Radius.circular(8),
      ),
      Paint()..color = NestColor.o(NestColor.highlight, 0.9),
    );

    // A second, lighter pass, as if the marker overlapped itself.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, top + height * 0.55, width * 0.95, height * 0.34),
        const Radius.circular(5),
      ),
      Paint()..color = NestColor.o(NestColor.highlight, 0.5),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_StrokePainter old) => old.t != t;
}

/// The pen itself, riding the leading edge of the stroke.
class _PenPainter extends CustomPainter {
  _PenPainter({required this.progress, required this.lift});

  final double progress;
  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || lift >= 1) return;

    final x = 2 + (size.width - 26) * progress;
    final y = size.height * 0.42;

    canvas.save();
    // Lifts up and fades as the stroke finishes.
    canvas.translate(x, y - 26 * lift);
    canvas.rotate(-0.32 - 0.25 * lift);

    final opacity = 1 - lift;

    // Nib.
    final nib = Path()
      ..moveTo(0, 0)
      ..lineTo(-5, -9)
      ..lineTo(5, -9)
      ..close();
    canvas.drawPath(
      nib,
      Paint()..color = NestColor.o(NestColor.penDeep, opacity),
    );

    // Barrel.
    canvas.drawLine(
      const Offset(0, -9),
      const Offset(0, -34),
      Paint()
        ..color = NestColor.o(NestColor.pen, opacity)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );

    // Cap.
    canvas.drawLine(
      const Offset(0, -30),
      const Offset(0, -40),
      Paint()
        ..color = NestColor.o(NestColor.penDeep, opacity)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );

    // Highlight down the barrel.
    canvas.drawLine(
      const Offset(-2, -14),
      const Offset(-2, -26),
      Paint()
        ..color = NestColor.o(Colors.white, 0.35 * opacity)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_PenPainter old) =>
      old.progress != progress || old.lift != lift;
}
